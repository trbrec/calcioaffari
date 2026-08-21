<?php
/**
 * Plugin Name: CalcioAffari News Engine
 * Plugin URI: https://calcioaffari.it
 * Description: Raccolta multi-fonte, deduplicazione e pubblicazione controllata di notizie di calciomercato con IA locale.
 * Version: 0.8.4
 * Author: CalcioAffari
 * Text Domain: calcioaffari-news-engine
 * Requires at least: 6.6
 * Requires PHP: 8.1
 * Update URI: https://github.com/trbrec/calcioaffari
 */

if (!defined('ABSPATH')) {
    exit;
}

define('CA_NEWS_VERSION', '0.8.4');
define('CA_NEWS_FILE', __FILE__);
define('CA_NEWS_DIR', plugin_dir_path(__FILE__));
define('CA_NEWS_URL', plugin_dir_url(__FILE__));

require_once CA_NEWS_DIR . 'includes/class-ca-news-db.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-content.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-sources.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-ingestor.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-publisher.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-rest.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-admin.php';
require_once CA_NEWS_DIR . 'includes/class-ca-news-updater.php';

final class CA_News_Engine {
    private const EXCERPT_RECOVERY_VERSION = '0.8.2';
    private const LENGTH_RECOVERY_VERSION = '0.8.3';
    private const EDITORIAL_RECOVERY_VERSION = '0.8.4';
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
        if (!wp_next_scheduled('ca_news_ingest_event')) {
            wp_schedule_event(time() + 60, 'ca_news_ten_minutes', 'ca_news_ingest_event');
        }
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
        $schedules['ca_news_ten_minutes'] = array(
            'interval' => 10 * MINUTE_IN_SECONDS,
            'display' => __('Ogni 10 minuti', 'calcioaffari-news-engine'),
        );
        return $schedules;
    }

    public static function activate(): void {
        CA_News_DB::install();
        CA_News_Content::register();
        CA_News_Sources::seed_defaults();
        if (!wp_next_scheduled('ca_news_ingest_event')) {
            wp_schedule_event(time() + 60, 'ca_news_ten_minutes', 'ca_news_ingest_event');
        }
        flush_rewrite_rules();
    }

    public static function deactivate(): void {
        $timestamp = wp_next_scheduled('ca_news_ingest_event');
        if ($timestamp) {
            wp_unschedule_event($timestamp, 'ca_news_ingest_event');
        }
        flush_rewrite_rules();
    }
}

register_activation_hook(__FILE__, array('CA_News_Engine', 'activate'));
register_deactivation_hook(__FILE__, array('CA_News_Engine', 'deactivate'));
CA_News_Engine::instance();
