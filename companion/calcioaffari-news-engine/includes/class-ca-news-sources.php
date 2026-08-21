<?php

if (!defined('ABSPATH')) {
    exit;
}

final class CA_News_Sources {
    private const PROFESSIONAL_DEFAULTS = array(
        array('BBC Sport · Football', 'https://feeds.bbci.co.uk/sport/football/rss.xml', 'en', 'GB', 'rss', 0.940),
        array('The Guardian · Football', 'https://www.theguardian.com/football/rss', 'en', 'GB', 'rss', 0.920),
        array('Sky Sports · Football', 'https://www.skysports.com/rss/12040', 'en', 'GB', 'rss', 0.920),
        array('Football Italia', 'https://football-italia.net/feed/', 'en', 'IT', 'rss', 0.900),
    );

    public static function seed_defaults(): void {
        global $wpdb;
        $table = CA_News_DB::table('sources');
        if ((int) $wpdb->get_var("SELECT COUNT(*) FROM {$table}") > 0) {
            return;
        }

        foreach (self::PROFESSIONAL_DEFAULTS as $source) {
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

    /**
     * Replace the legacy headline-only discovery source with feeds that carry
     * substantive excerpts. This migration runs once per release and never
     * changes a user's custom sources.
     */
    public static function install_professional_defaults(): array {
        global $wpdb;
        $table = CA_News_DB::table('sources');
        $added = 0;
        $enabled = 0;

        foreach (self::PROFESSIONAL_DEFAULTS as $source) {
            $hash = hash('sha256', strtolower($source[1]));
            $existing = $wpdb->get_row($wpdb->prepare("SELECT id, enabled FROM {$table} WHERE feed_hash=%s", $hash), ARRAY_A);
            if ($existing) {
                if (!(int) $existing['enabled'] && false !== $wpdb->update(
                    $table,
                    array('enabled' => 1, 'updated_at' => current_time('mysql', true)),
                    array('id' => (int) $existing['id']),
                    array('%d', '%s'),
                    array('%d')
                )) {
                    $enabled++;
                }
                continue;
            }

            $result = self::add(array(
                'name' => $source[0],
                'feed_url' => $source[1],
                'language' => $source[2],
                'country' => $source[3],
                'source_type' => $source[4],
                'trust_score' => $source[5],
                'enabled' => 1,
            ));
            if (!is_wp_error($result)) {
                $added++;
            }
        }

        $disabled = $wpdb->query($wpdb->prepare(
            "UPDATE {$table} SET enabled=0, last_error=%s, updated_at=%s WHERE source_type='gdelt' AND enabled=1",
            'Disattivata: GDELT fornisce soltanto titoli, insufficienti per una redazione professionale.',
            current_time('mysql', true)
        ));
        return array('added' => $added, 'enabled' => $enabled, 'gdelt_disabled' => max(0, (int) $disabled));
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
