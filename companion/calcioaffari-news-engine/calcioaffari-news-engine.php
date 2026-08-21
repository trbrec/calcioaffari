<?php
/**
 * Plugin Name: CalcioAffari News Engine
 * Plugin URI: https://calcioaffari.it
 * Description: Raccolta multi-fonte, deduplicazione e pubblicazione controllata di notizie di calciomercato con IA locale.
 * Version: 1.0.2
 * Author: CalcioAffari
 * Text Domain: calcioaffari-news-engine
 * Requires at least: 6.6
 * Requires PHP: 8.1
 * Update URI: https://github.com/trbrec/calcioaffari
 */

if (!defined('ABSPATH')) {
    exit;
}

define('CA_NEWS_VERSION', '1.0.2');
define('CA_NEWS_FILE', __FILE__);
define('CA_NEWS_DIR', plugin_dir_path(__FILE__));
define('CA_NEWS_URL', plugin_dir_url(__FILE__));

require_once CA_NEWS_DIR . 'includes/class-ca-news-db.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-content.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-sources.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-ingestor.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-backfill.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-publisher.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-rest.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-admin.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-updater.php';

final class CA_News_Engine {
    private const EXCERPT_RECOVERY_VERSION = '0.8.2';
    private const LENGTH_RECOVERY_VERSION = '0.8.3';
    private const EDITORIAL_RECOVERY_VERSION = '0.8.5';
    private const PROFESSIONAL_SOURCES_VERSION = '1.0.1';
    private const STRICT_MARKET_FILTER_VERSION = '0.9.0';
    private const GROUNDING_AUDIT_VERSION = '1.0.0';
    private const GROUNDING_PROMPT_RECOVERY_VERSION = '1.0.2';
    private const LIVE_SCHEDULE_VERSION = '1.0.1';
    private static ?self $instance = null;

    public static function instance(): self {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        add_action('init', array('CA_News_Content', 'register'));
        add_action('rest_api_init', array('CA_News_REST', 'register_routes'));
        add_action('admin_menu', array('CA_News_Admin', 'register_menu'));
        add_action('admin_init', array('CA_News_Admin', 'register_settings'));
        add_action('admin_enqueue_scripts', array('CA_News_Admin', 'enqueue_assets'));
        add_action('ca_news_ingest_event', array('CA_News_Ingestor', 'run'));
        add_action('ca_news_backfill_event', array('CA_News_Backfill', 'run_batch'));
        add_filter('cron_schedules', array($this, 'cron_schedules'));
        add_action('plugins_loaded', array($this, 'maybe_upgrade'));

        CA_News_REST::register_ajax_handlers();
        CA_News_Admin::register_actions();
        CA_News_Updater::register();
    }

    public function maybe_upgrade(): void {
        if (get_option('ca_news_db_version') !== CA_NEWS_VERSION) {
            CA_News_DB::install();
            CA_News_Sources::seed_defaults();
        }
        self::recover_excerpt_rejections();
        self::recover_length_rejections();
        self::recover_editorial_rejections();
        self::migrate_professional_sources();
        self::migrate_strict_market_filter();
        self::migrate_grounding_audit();
        self::recover_grounding_prompt_rejections();
        self::migrate_five_minute_schedule();
        CA_News_Backfill::schedule();
        if (!wp_next_scheduled('ca_news_ingest_event')) {
            wp_schedule_event(time() + 60, 'ca_news_five_minutes', 'ca_news_ingest_event');
        }
    }

    private static function migrate_five_minute_schedule(): void {
        if (get_option('ca_news_live_schedule_version') === self::LIVE_SCHEDULE_VERSION) {
            return;
        }
        wp_clear_scheduled_hook('ca_news_ingest_event');
        $settings = CA_News_DB::settings();
        $settings['source_cache_minutes'] = 5;
        update_option('ca_news_settings', $settings, false);
        wp_schedule_event(time() + 30, 'ca_news_five_minutes', 'ca_news_ingest_event');
        update_option('ca_news_live_schedule_version', self::LIVE_SCHEDULE_VERSION, false);
        CA_News_DB::log('info', 'five_minute_schedule_installed', 'Raccolta live e cache fonti impostate a cinque minuti.');
    }

    private static function migrate_professional_sources(): void {
        if (get_option('ca_news_professional_sources_version') === self::PROFESSIONAL_SOURCES_VERSION) {
            return;
        }

        global $wpdb;
        $result = CA_News_Sources::install_professional_defaults();
        $enabled = count(CA_News_Sources::all(true));
        if ($enabled < 1) {
            CA_News_DB::log('error', 'professional_sources_failed', 'Nessuna fonte editoriale professionale è stata attivata; migrazione non completata.');
            return;
        }

        $jobs = CA_News_DB::table('jobs');
        $quarantined = $wpdb->query($wpdb->prepare(
            "UPDATE {$jobs} SET status='rejected', error_message=%s, lease_hash=NULL, lease_expires_at=NULL, updated_at=%s WHERE status IN ('pending','awaiting') AND evidence LIKE %s",
            'Notizia messa in quarantena: GDELT forniva soltanto un titolo, non una prova editoriale verificabile.',
            current_time('mysql', true),
            '%"source_type":"gdelt"%'
        ));
        if ($quarantined === false) {
            CA_News_DB::log('error', 'legacy_quarantine_failed', 'Impossibile mettere in quarantena la vecchia coda GDELT.');
            return;
        }

        update_option('ca_news_professional_sources_version', self::PROFESSIONAL_SOURCES_VERSION, false);
        CA_News_DB::log('info', 'professional_sources_installed', 'Fonti professionali attivate e raccolta headline-only disabilitata.', array_merge($result, array(
            'enabled_total' => $enabled,
            'legacy_jobs_quarantined' => (int) $quarantined,
        )));
    }

    private static function migrate_strict_market_filter(): void {
        if (get_option('ca_news_strict_market_filter_version') === self::STRICT_MARKET_FILTER_VERSION) {
            return;
        }
        $result = CA_News_Ingestor::revalidate_open_jobs();
        update_option('ca_news_strict_market_filter_version', self::STRICT_MARKET_FILTER_VERSION, false);
        CA_News_DB::log(
            'info',
            'strict_market_filter_installed',
            'Coda non elaborata ricontrollata con il filtro calciomercato basato sul titolo.',
            $result
        );
    }

    /**
     * Quarantine legacy pending drafts that were created without the v1.0
     * evidence-quote and independent-review gates. Published content is never
     * changed automatically; it is only counted for a human audit.
     */
    private static function migrate_grounding_audit(): void {
        if (get_option('ca_news_grounding_audit_version') === self::GROUNDING_AUDIT_VERSION) {
            return;
        }

        global $wpdb;
        $jobs = CA_News_DB::table('jobs');
        $rows = (array) $wpdb->get_results(
            "SELECT id,post_id,status,result_json FROM {$jobs} WHERE post_id IS NOT NULL AND post_id > 0 AND (result_json IS NULL OR result_json NOT LIKE '%\"editorial_audit\"%') ORDER BY id ASC LIMIT 2000",
            ARRAY_A
        );
        $quarantined = 0;
        $published_requires_audit = 0;
        foreach ($rows as $row) {
            $post_id = (int) $row['post_id'];
            $post_status = get_post_status($post_id);
            if ($post_status === 'publish') {
                $published_requires_audit++;
                continue;
            }
            if (!in_array($post_status, array('pending', 'draft'), true)) {
                continue;
            }
            if ($post_status === 'pending') {
                $updated_post = wp_update_post(array('ID' => $post_id, 'post_status' => 'draft'), true);
                if (is_wp_error($updated_post)) {
                    CA_News_DB::log('error', 'legacy_post_quarantine_failed', $updated_post->get_error_message(), array('post_id' => $post_id, 'job_id' => (int) $row['id']));
                    continue;
                }
            }
            update_post_meta($post_id, 'ca_ai_quarantined', '1');
            update_post_meta($post_id, 'ca_ai_quarantine_reason', 'Generato prima del controllo indipendente con estratti-prova v1.0.');
            $wpdb->update(
                $jobs,
                array(
                    'status' => 'rejected',
                    'error_message' => 'Quarantena audit 1.0: articolo legacy privo di revisione indipendente ed estratti-prova.',
                    'lease_hash' => null,
                    'lease_expires_at' => null,
                    'updated_at' => current_time('mysql', true),
                ),
                array('id' => (int) $row['id']),
                array('%s', '%s', '%s', '%s', '%s'),
                array('%d')
            );
            $quarantined++;
        }

        $queue = CA_News_Ingestor::revalidate_open_jobs();
        update_option('ca_news_grounding_audit_version', self::GROUNDING_AUDIT_VERSION, false);
        CA_News_DB::log('info', 'grounding_audit_installed', 'Installato il doppio controllo editoriale con prove letterali.', array(
            'legacy_drafts_quarantined' => $quarantined,
            'published_requires_audit' => $published_requires_audit,
            'queue' => $queue,
        ));
    }

    private static function recover_excerpt_rejections(): void {
        if (get_option('ca_news_excerpt_recovery_version') === self::EXCERPT_RECOVERY_VERSION) {
            return;
        }

        global $wpdb;
        $table = CA_News_DB::table('jobs');
        $updated = $wpdb->query($wpdb->prepare(
            "UPDATE {$table} SET status='pending', attempt_count=0, last_attempt_at=NULL, error_message=NULL, result_json=NULL, confidence=NULL, lease_hash=NULL, lease_expires_at=NULL, updated_at=%s WHERE status='rejected' AND error_message=%s",
            current_time('mysql', true),
            'Sommario assente o fuori lunghezza.'
        ));

        if ($updated === false) {
            CA_News_DB::log('error', 'excerpt_recovery_failed', 'Impossibile ripristinare automaticamente le notizie respinte per il precedente errore sul sommario.');
            return;
        }

        update_option('ca_news_excerpt_recovery_version', self::EXCERPT_RECOVERY_VERSION, false);
        if ($updated > 0) {
            CA_News_DB::log('info', 'excerpt_recovery_completed', sprintf('%d notizie rimesse automaticamente in coda.', (int) $updated));
        }
    }

    /** Retry only post-less jobs rejected by the over-expansive grounding prompt. */
    private static function recover_grounding_prompt_rejections(): void {
        if (get_option('ca_news_grounding_prompt_recovery_version') === self::GROUNDING_PROMPT_RECOVERY_VERSION) {
            return;
        }

        global $wpdb;
        $table = CA_News_DB::table('jobs');
        $updated = $wpdb->query($wpdb->prepare(
            "UPDATE {$table} SET status='pending', attempt_count=0, last_attempt_at=NULL, error_message=NULL, result_json=NULL, confidence=NULL, lease_hash=NULL, lease_expires_at=NULL, updated_at=%s WHERE status='rejected' AND post_id IS NULL AND error_message LIKE %s",
            current_time('mysql', true),
            $wpdb->esc_like('Quarantena editoriale:') . '%'
        ));
        if ($updated === false) {
            CA_News_DB::log('error', 'grounding_prompt_recovery_failed', 'Impossibile rimettere in coda le notizie respinte dal prompt precedente.');
            return;
        }
        update_option('ca_news_grounding_prompt_recovery_version', self::GROUNDING_PROMPT_RECOVERY_VERSION, false);
        CA_News_DB::log('info', 'grounding_prompt_recovery_completed', sprintf('%d notizie rimesse in coda con il prompt aderente alle prove.', (int) $updated));
    }

    private static function recover_length_rejections(): void {
        if (get_option('ca_news_length_recovery_version') === self::LENGTH_RECOVERY_VERSION) {
            return;
        }

        global $wpdb;
        $table = CA_News_DB::table('jobs');
        $updated = $wpdb->query($wpdb->prepare(
            "UPDATE {$table} SET status='pending', attempt_count=0, last_attempt_at=NULL, error_message=NULL, result_json=NULL, confidence=NULL, lease_hash=NULL, lease_expires_at=NULL, updated_at=%s WHERE status='rejected' AND error_message LIKE %s",
            current_time('mysql', true),
            $wpdb->esc_like('Articolo fuori lunghezza:') . '%'
        ));

        if ($updated === false) {
            CA_News_DB::log('error', 'length_recovery_failed', 'Impossibile ripristinare automaticamente le notizie respinte per lunghezza.');
            return;
        }

        update_option('ca_news_length_recovery_version', self::LENGTH_RECOVERY_VERSION, false);
        if ($updated > 0) {
            CA_News_DB::log('info', 'length_recovery_completed', sprintf('%d notizie respinte per lunghezza rimesse automaticamente in coda.', (int) $updated));
        }
    }

    private static function recover_editorial_rejections(): void {
        if (get_option('ca_news_editorial_recovery_version') === self::EDITORIAL_RECOVERY_VERSION) {
            return;
        }

        global $wpdb;
        $table = CA_News_DB::table('jobs');
        $updated = $wpdb->query($wpdb->prepare(
            "UPDATE {$table} SET status='pending', attempt_count=0, last_attempt_at=NULL, error_message=NULL, result_json=NULL, confidence=NULL, lease_hash=NULL, lease_expires_at=NULL, updated_at=%s WHERE status='rejected' AND (error_message LIKE %s OR error_message LIKE %s OR error_message=%s)",
            current_time('mysql', true),
            $wpdb->esc_like('Qwen3 non ha rispettato la lunghezza editoriale dopo tre controlli (') . '%',
            $wpdb->esc_like('Articolo fuori lunghezza:') . '%',
            'Il testo contiene URL non consentiti: le fonti vengono gestite separatamente.'
        ));

        if ($updated === false) {
            CA_News_DB::log('error', 'editorial_recovery_failed', 'Impossibile ripristinare automaticamente le notizie respinte dai precedenti controlli editoriali.');
            return;
        }

        update_option('ca_news_editorial_recovery_version', self::EDITORIAL_RECOVERY_VERSION, false);
        if ($updated > 0) {
            CA_News_DB::log('info', 'editorial_recovery_completed', sprintf('%d notizie rimesse automaticamente in coda dopo la correzione editoriale.', (int) $updated));
        }
    }

    public function cron_schedules(array $schedules): array {
        $schedules['ca_news_five_minutes'] = array(
            'interval' => 5 * MINUTE_IN_SECONDS,
            'display' => __('Ogni 5 minuti', 'calcioaffari-news-engine'),
        );
        return $schedules;
    }

    public static function activate(): void {
        CA_News_DB::install();
        CA_News_Content::register();
        CA_News_Sources::seed_defaults();
        if (!wp_next_scheduled('ca_news_ingest_event')) {
            wp_schedule_event(time() + 60, 'ca_news_five_minutes', 'ca_news_ingest_event');
        }
        CA_News_Backfill::schedule();
        flush_rewrite_rules();
    }

    public static function deactivate(): void {
        wp_clear_scheduled_hook('ca_news_ingest_event');
        wp_clear_scheduled_hook('ca_news_backfill_event');
        flush_rewrite_rules();
    }
}

register_activation_hook(__FILE__, array('CA_News_Engine', 'activate'));
register_deactivation_hook(__FILE__, array('CA_News_Engine', 'deactivate'));
CA_News_Engine::instance();
