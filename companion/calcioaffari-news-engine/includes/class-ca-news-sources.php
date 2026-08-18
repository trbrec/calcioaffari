<?php

if (!defined('ABSPATH')) {
    exit;
}

final class CA_News_Sources {
    public static function seed_defaults(): void {
        global $wpdb;
        $table = CA_News_DB::table('sources');
        if ((int) $wpdb->get_var("SELECT COUNT(*) FROM {$table}") > 0) {
            return;
        }

        $defaults = array(array(
            'GDELT · Calciomercato mondiale',
            'https://api.gdeltproject.org/api/v2/doc/doc?query=%28%22football%20transfer%22%20OR%20%22soccer%20transfer%22%20OR%20%22transfer%20window%22%20OR%20%22football%20loan%20move%22%20OR%20%22football%20contract%20extension%22%29&mode=artlist&maxrecords=250&format=json&sort=datedesc&timespan=24h',
            'multi',
            'WORLD',
            'gdelt',
            0.760,
        ));

        foreach ($defaults as $source) {
            self::add(array(
                'name' => $source[0],
                'feed_url' => $source[1],
                'language' => $source[2],
                'country' => $source[3],
                'source_type' => $source[4] ?? 'aggregator',
                'trust_score' => $source[5] ?? 0.750,
                'enabled' => 1,
            ));
        }
    }

    public static function all(bool $enabled_only = false): array {
        global $wpdb;
        $table = CA_News_DB::table('sources');
        $where = $enabled_only ? ' WHERE enabled=1' : '';
        return (array) $wpdb->get_results("SELECT * FROM {$table}{$where} ORDER BY enabled DESC, name ASC", ARRAY_A);
    }

    public static function add(array $input): int|WP_Error {
        global $wpdb;
        $url = esc_url_raw(trim((string) ($input['feed_url'] ?? '')), array('https'));
        if (!$url || strtolower((string) wp_parse_url($url, PHP_URL_SCHEME)) !== 'https') {
            return new WP_Error('ca_news_invalid_feed', __('La fonte deve usare un URL HTTPS valido.', 'calcioaffari-news-engine'));
        }

        $name = sanitize_text_field((string) ($input['name'] ?? wp_parse_url($url, PHP_URL_HOST)));
        $hash = hash('sha256', strtolower($url));
        $now = current_time('mysql', true);
        $inserted = $wpdb->insert(
            CA_News_DB::table('sources'),
            array(
                'name' => $name ?: 'Fonte RSS',
                'feed_url' => $url,
                'feed_hash' => $hash,
                'language' => sanitize_key((string) ($input['language'] ?? 'it')),
                'country' => strtoupper(substr(sanitize_text_field((string) ($input['country'] ?? 'IT')), 0, 12)),
                'source_type' => in_array(($input['source_type'] ?? ''), array('rss', 'aggregator', 'official', 'gdelt'), true) ? $input['source_type'] : 'rss',
                'trust_score' => max(0.1, min(1.0, (float) ($input['trust_score'] ?? 0.75))),
                'enabled' => empty($input['enabled']) ? 0 : 1,
                'created_at' => $now,
                'updated_at' => $now,
            ),
            array('%s', '%s', '%s', '%s', '%s', '%s', '%f', '%d', '%s', '%s')
        );

        if (!$inserted) {
            return new WP_Error('ca_news_source_exists', __('Fonte già presente o non salvabile.', 'calcioaffari-news-engine'));
        }
        return (int) $wpdb->insert_id;
    }

    public static function set_enabled(int $id, bool $enabled): bool {
        global $wpdb;
        return false !== $wpdb->update(
            CA_News_DB::table('sources'),
            array('enabled' => $enabled ? 1 : 0, 'updated_at' => current_time('mysql', true)),
            array('id' => $id),
            array('%d', '%s'),
            array('%d')
        );
    }

    public static function delete(int $id): bool {
        global $wpdb;
        return false !== $wpdb->delete(CA_News_DB::table('sources'), array('id' => $id), array('%d'));
    }
}
