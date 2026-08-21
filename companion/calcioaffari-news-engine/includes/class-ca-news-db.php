<?php

if (!defined('ABSPATH')) {
    exit;
}

final class CA_News_DB {
    public static function table(string $name): string {
        global $wpdb;
        return $wpdb->prefix . 'ca_news_' . $name;
    }

    public static function install(): void {
        global $wpdb;
        require_once ABSPATH . 'wp-admin/includes/upgrade.php';

        $charset = $wpdb->get_charset_collate();
        $sources = self::table('sources');
        $items = self::table('items');
        $jobs = self::table('jobs');
        $logs = self::table('logs');
        $pairing = self::table('pairing');

        dbDelta("CREATE TABLE {$sources} (
            id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
            name varchar(190) NOT NULL,
            feed_url text NOT NULL,
            feed_hash char(64) NOT NULL,
            language varchar(12) NOT NULL DEFAULT 'it',
            country varchar(12) NOT NULL DEFAULT 'IT',
            source_type varchar(24) NOT NULL DEFAULT 'rss',
            trust_score decimal(4,3) NOT NULL DEFAULT 0.750,
            enabled tinyint(1) NOT NULL DEFAULT 1,
            last_checked datetime NULL,
            last_success datetime NULL,
            last_error text NULL,
            created_at datetime NOT NULL,
            updated_at datetime NOT NULL,
            PRIMARY KEY  (id),
            UNIQUE KEY feed_hash (feed_hash),
            KEY enabled (enabled)
        ) {$charset};");

        dbDelta("CREATE TABLE {$items} (
            id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
            source_id bigint(20) unsigned NOT NULL,
            source_guid char(64) NOT NULL,
            source_url text NOT NULL,
            source_name varchar(190) NOT NULL,
            title text NOT NULL,
            excerpt longtext NULL,
            language varchar(12) NOT NULL DEFAULT 'it',
            market_scope tinyint(1) NOT NULL DEFAULT 0,
            published_at datetime NULL,
            fingerprint char(64) NOT NULL,
            cluster_key char(64) NOT NULL,
            created_at datetime NOT NULL,
            PRIMARY KEY  (id),
            UNIQUE KEY source_guid (source_guid),
            KEY cluster_key (cluster_key),
            KEY published_at (published_at)
        ) {$charset};");

        dbDelta("CREATE TABLE {$jobs} (
            id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
            cluster_key char(64) NOT NULL,
            status varchar(24) NOT NULL DEFAULT 'awaiting',
            evidence longtext NOT NULL,
            evidence_count smallint(5) unsigned NOT NULL DEFAULT 0,
            source_count smallint(5) unsigned NOT NULL DEFAULT 0,
            lease_hash char(64) NULL,
            lease_expires_at datetime NULL,
            attempt_count smallint(5) unsigned NOT NULL DEFAULT 0,
            last_attempt_at datetime NULL,
            worker_name varchar(190) NULL,
            model_name varchar(190) NULL,
            result_json longtext NULL,
            confidence decimal(4,3) NULL,
            post_id bigint(20) unsigned NULL,
            error_message text NULL,
            created_at datetime NOT NULL,
            updated_at datetime NOT NULL,
            PRIMARY KEY  (id),
            UNIQUE KEY cluster_key (cluster_key),
            KEY status (status),
            KEY lease_expires_at (lease_expires_at)
        ) {$charset};");

        dbDelta("CREATE TABLE {$logs} (
            id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
            level varchar(16) NOT NULL DEFAULT 'info',
            event varchar(80) NOT NULL,
            message text NOT NULL,
            context longtext NULL,
            created_at datetime NOT NULL,
            PRIMARY KEY  (id),
            KEY event (event),
            KEY created_at (created_at)
        ) {$charset};");

        dbDelta("CREATE TABLE {$pairing} (
            id tinyint(3) unsigned NOT NULL,
            token_hash char(64) NOT NULL,
            created_at datetime NOT NULL,
            PRIMARY KEY  (id)
        ) {$charset};");

        $legacy_hash = (string) get_option('ca_news_agent_token_hash', '');
        if (preg_match('/^[a-f0-9]{64}$/', $legacy_hash) && self::agent_token_hash() === '') {
            self::store_agent_token_hash($legacy_hash);
        }

        if (!get_option('ca_news_settings')) {
            add_option('ca_news_settings', self::default_settings(), '', false);
        }
        update_option('ca_news_db_version', CA_NEWS_VERSION, false);
    }

    public static function store_agent_token_hash(string $hash): bool {
        global $wpdb;
        if (!preg_match('/^[a-f0-9]{64}$/', $hash)) {
            return false;
        }
        $written = $wpdb->replace(
            self::table('pairing'),
            array('id' => 1, 'token_hash' => $hash, 'created_at' => current_time('mysql', true)),
            array('%d', '%s', '%s')
        );
        return $written !== false && hash_equals($hash, self::agent_token_hash());
    }

    public static function agent_token_hash(): string {
        global $wpdb;
        $hash = (string) $wpdb->get_var("SELECT token_hash FROM " . self::table('pairing') . " WHERE id=1 LIMIT 1");
        return preg_match('/^[a-f0-9]{64}$/', $hash) ? $hash : '';
    }

    public static function default_settings(): array {
        return array(
            'publication_mode' => 'review',
            'minimum_sources' => 2,
            'auto_confidence' => 0.90,
            'max_posts_per_day' => 18,
            'max_items_per_source' => 30,
            'lookback_hours' => 36,
            'article_min_words' => 160,
            'article_max_words' => 360,
            'default_author' => 1,
            'agent_lease_minutes' => 15,
            'max_job_attempts' => 3,
            'source_cache_minutes' => 5,
            'require_primary_for_official' => 1,
            'single_source_drafts' => 1,
            'model_name' => 'qwen3:14b',
        );
    }

    public static function settings(): array {
        return wp_parse_args((array) get_option('ca_news_settings', array()), self::default_settings());
    }

    public static function log(string $level, string $event, string $message, array $context = array()): void {
        global $wpdb;
        $wpdb->insert(
            self::table('logs'),
            array(
                'level' => sanitize_key($level),
                'event' => sanitize_key($event),
                'message' => sanitize_textarea_field($message),
                'context' => $context ? wp_json_encode($context, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null,
                'created_at' => current_time('mysql', true),
            ),
            array('%s', '%s', '%s', '%s', '%s')
        );
    }

    public static function cleanup(): void {
        global $wpdb;
        $items = self::table('items');
        $logs = self::table('logs');
        $jobs = self::table('jobs');
        $wpdb->query($wpdb->prepare("DELETE FROM {$items} WHERE created_at < %s", gmdate('Y-m-d H:i:s', time() - 45 * DAY_IN_SECONDS)));
        $wpdb->query($wpdb->prepare("DELETE FROM {$logs} WHERE created_at < %s", gmdate('Y-m-d H:i:s', time() - 30 * DAY_IN_SECONDS)));
        $maximum = max(1, (int) self::settings()['max_job_attempts']);
        $wpdb->query($wpdb->prepare(
            "UPDATE {$jobs} SET status=IF(attempt_count >= %d, 'rejected', 'pending'), error_message=IF(attempt_count >= %d, 'Numero massimo di tentativi raggiunto dopo la scadenza del lavoro.', error_message), lease_hash=NULL, lease_expires_at=NULL WHERE status='leased' AND lease_expires_at < %s",
            $maximum,
            $maximum,
            current_time('mysql', true)
        ));
    }
}
