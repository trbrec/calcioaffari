<?php
/**
 * Plugin Name: CalcioAffari News Engine
 * Plugin URI: https://calcioaffari.it
 * Description: Raccolta multi-fonte, deduplicazione e pubblicazione controllata di notizie di calciomercato con IA locale.
 * Version: 1.1.1
 * Author: CalcioAffari
 * Text Domain: calcioaffari-news-engine
 * Requires at least: 6.6
 * Requires PHP: 8.1
 * Update URI: https://github.com/trbrec/calcioaffari
 */

if (!defined('ABSPATH')) {
    exit;
}

define('CA_NEWS_VERSION', '1.1.1');
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
    private const PROFESSIONAL_SOURCES_VERSION = '1.0.5';
    private const STRICT_MARKET_FILTER_VERSION = '0.9.0';
    private const GROUNDING_AUDIT_VERSION = '1.0.0';
    private const GROUNDING_PROMPT_RECOVERY_VERSION = '1.0.2';
    private const OUTPUT_CONSISTENCY_VERSION = '1.0.3';
    private const CHRONOLOGICAL_QUEUE_VERSION = '1.0.4';
    private const BACKFILL_REVALIDATION_VERSION = '1.0.6';
    private const JOB_STATUS_RECONCILIATION_VERSION = '1.0.7';
    private const CONCISE_BRIEF_RECOVERY_VERSION = '1.0.9';
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
        add_action('transition_post_status', array($this, 'sync_job_status_from_post'), 10, 3);
        add_filter('cron_schedules', array($this, 'cron_schedules'));
        add_action('plugins_loaded', array($this, 'maybe_upgrade'));

        CA_News_REST::register_ajax_handlers();
        CA_News_Admin::register_actions();
        CA_News_Updater::register();
    }

    /** Keep queue counters aligned when an editor publishes or unpublishes an Affare. */
    public function sync_job_status_from_post(string $new_status, string $old_status, WP_Post $post): void {
        if ($post->post_type !== 'ca_affare' || $new_status === $old_status) {
            return;
        }

        $job_id = (int) get_post_meta($post->ID, 'ca_ai_job_id', true);
        if ($job_id < 1) {
            return;
        }

        global $wpdb;
        $table = CA_News_DB::table('jobs');
        $job_status = (string) $wpdb->get_var($wpdb->prepare("SELECT status FROM {$table} WHERE id=%d", $job_id));
        $target = '';
        if ($new_status === 'publish' && $job_status === 'processed') {
            $target = 'published';
        } elseif (in_array($new_status, array('draft', 'pending'), true) && $job_status === 'published') {
            $target = 'processed';
        }
        if ($target === '') {
            return;
        }

        $wpdb->update(
            $table,
            array('status' => $target, 'updated_at' => current_time('mysql', true)),
            array('id' => $job_id),
            array('%s', '%s'),
            array('%d')
        );
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
        self::recover_chronological_queue_rejections();
        self::revalidate_recovered_backfill();
        self::migrate_output_consistency();
        self::reconcile_job_post_statuses();
        self::migrate_five_minute_schedule();
        CA_News_Backfill::schedule();
        if (!wp_next_scheduled('ca_news_ingest_event')) {
            wp_schedule_event(time() + 60, 'ca_news_five_minutes', 'ca_news_ingest_event');
        }
    }

    /** Reconcile posts already changed manually before the transition hook existed. */
    private static function reconcile_job_post_statuses(): void {
        if (get_option('ca_news_job_status_reconciliation_version') === self::JOB_STATUS_RECONCILIATION_VERSION) {
            return;
        }
        global $wpdb;
        $table = CA_News_DB::table('jobs');
        $rows = (array) $wpdb->get_results(
            "SELECT id,status,post_id FROM {$table} WHERE status IN ('processed','published') AND post_id IS NOT NULL AND post_id > 0 ORDER BY id ASC LIMIT 2000",
            ARRAY_A
        );
        foreach ($rows as $row) {
            $post_status = get_post_status((int) $row['post_id']);
            $target = $post_status === 'publish' ? 'published' : (in_array($post_status, array('draft', 'pending'), true) ? 'processed' : '');
            if ($target === '' || $target === (string) $row['status']) {
                continue;
            }
            $wpdb->update(
                $table,
                array('status' => $target, 'updated_at' => current_time('mysql', true)),
                array('id' => (int) $row['id']),
                array('%s', '%s'),
                array('%d')
            );
        }
        update_option('ca_news_job_status_reconciliation_version', self::JOB_STATUS_RECONCILIATION_VERSION, false);
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

    /**
     * Keep every generated market story inside Affari. Legacy pending posts
     * created as ordinary Articles are quarantined, never deleted or published.
     */
    private static function migrate_output_consistency(): void {
        if (get_option('ca_news_output_consistency_version') === self::OUTPUT_CONSISTENCY_VERSION) {
            return;
        }

        global $wpdb;
        $jobs = CA_News_DB::table('jobs');
        $rows = (array) $wpdb->get_results(
            "SELECT id,post_id FROM {$jobs} WHERE status='processed' AND post_id IS NOT NULL AND post_id > 0 ORDER BY id ASC LIMIT 2000",
            ARRAY_A
        );
        $quarantined = 0;
        foreach ($rows as $row) {
            $post_id = (int) $row['post_id'];
            if (get_post_type($post_id) === 'ca_affare') {
                continue;
            }
            $post_status = get_post_status($post_id);
            if (!in_array($post_status, array('pending', 'draft'), true)) {
                continue;
            }
            if ($post_status === 'pending') {
                $updated = wp_update_post(array('ID' => $post_id, 'post_status' => 'draft'), true);
                if (is_wp_error($updated)) {
                    CA_News_DB::log('error', 'misrouted_post_quarantine_failed', $updated->get_error_message(), array('post_id' => $post_id));
                    continue;
                }
            }
            update_post_meta($post_id, 'ca_ai_quarantined', '1');
            update_post_meta($post_id, 'ca_ai_quarantine_reason', 'Contenuto generato fuori dalla sezione Affari o non riferito a una singola operazione.');
            $wpdb->update(
                $jobs,
                array(
                    'status' => 'rejected',
                    'error_message' => 'Notizia messa in quarantena: contenuto generato fuori dalla sezione Affari o non riferito a una singola operazione.',
                    'updated_at' => current_time('mysql', true),
                ),
                array('id' => (int) $row['id']),
                array('%s', '%s', '%s'),
                array('%d')
            );
            $quarantined++;
        }

        $queue = CA_News_Ingestor::revalidate_open_jobs();
        update_option('ca_news_output_consistency_version', self::OUTPUT_CONSISTENCY_VERSION, false);
        CA_News_DB::log('info', 'output_consistency_installed', 'Destinazione Affari e filtro singola operazione applicati.', array(
            'misrouted_posts_quarantined' => $quarantined,
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

    /**
     * Retry grounding quarantines only after the concise-brief agent is
     * connected. Delaying the migration prevents an older agent from
     * immediately rejecting the same backlog again.
     */
    public static function recover_concise_brief_rejections(): void {
        if (get_option('ca_news_concise_brief_recovery_version') === self::CONCISE_BRIEF_RECOVERY_VERSION) {
            return;
        }

        global $wpdb;
        $table = CA_News_DB::table('jobs');
        $updated = $wpdb->query($wpdb->prepare(
            "UPDATE {$table} SET status='pending', attempt_count=0, last_attempt_at=NULL, error_message=NULL, result_json=NULL, confidence=NULL, lease_hash=NULL, lease_expires_at=NULL, updated_at=%s WHERE status='rejected' AND post_id IS NULL AND (error_message LIKE %s OR error_message LIKE %s OR error_message LIKE %s OR error_message=%s)",
            current_time('mysql', true),
            $wpdb->esc_like('Quarantena editoriale:') . '%',
            $wpdb->esc_like('Testo insufficiente per la pubblicazione:') . '%',
            $wpdb->esc_like('Revisione editoriale non superata:') . '%',
            'La revisione editoriale segnala problemi o affermazioni non supportate.'
        ));
        if ($updated === false) {
            CA_News_DB::log('error', 'concise_brief_recovery_failed', 'Impossibile rimettere in coda le quarantene per prove brevi.');
            return;
        }
        update_option('ca_news_concise_brief_recovery_version', self::CONCISE_BRIEF_RECOVERY_VERSION, false);
        CA_News_DB::log('info', 'concise_brief_recovery_completed', sprintf('%d notizie rimesse in coda per la stesura breve aderente alle prove.', (int) $updated));
    }

    /** Retry post-less quarantines after isolating the title's primary transfer story. */
    private static function recover_chronological_queue_rejections(): void {
        if (get_option('ca_news_chronological_queue_version') === self::CHRONOLOGICAL_QUEUE_VERSION) {
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
            CA_News_DB::log('error', 'chronological_queue_recovery_failed', 'Impossibile rimettere in coda le quarantene dopo la correzione cronologica.');
            return;
        }
        update_option('ca_news_chronological_queue_version', self::CHRONOLOGICAL_QUEUE_VERSION, false);
        CA_News_DB::log('info', 'chronological_queue_recovery_completed', sprintf('%d notizie rimesse in coda con selezione cronologica e storia principale.', (int) $updated));
    }

    /**
     * The chronological recovery runs after the original strict-filter
     * migration. Re-run the admission gate once so recovered quarantines do
     * not consume local-LLM time unless their evidence still passes.
     */
    private static function revalidate_recovered_backfill(): void {
        if (get_option('ca_news_backfill_revalidation_version') === self::BACKFILL_REVALIDATION_VERSION) {
            return;
        }
        $result = CA_News_Ingestor::revalidate_open_jobs();
        update_option('ca_news_backfill_revalidation_version', self::BACKFILL_REVALIDATION_VERSION, false);
        CA_News_DB::log('info', 'backfill_revalidation_completed', sprintf(
            '%d job controllati, %d non pertinenti rimossi dalla coda, %d ripristinati.',
            (int) ($result['checked'] ?? 0),
            (int) ($result['quarantined'] ?? 0),
            (int) ($result['restored'] ?? 0)
        ));
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
