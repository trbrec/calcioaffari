<?php

if (!defined('ABSPATH')) {
    exit;
}

final class CA_News_Ingestor {
    private const LOCK_KEY = 'ca_news_ingestor_lock';

    public static function run(): array {
        if (get_transient(self::LOCK_KEY)) {
            return array('status' => 'locked', 'inserted' => 0);
        }
        set_transient(self::LOCK_KEY, '1', 9 * MINUTE_IN_SECONDS);

        $inserted = 0;
        $errors = 0;
        try {
            CA_News_DB::cleanup();
            foreach (CA_News_Sources::all(true) as $source) {
                $result = self::ingest_source($source);
                $inserted += (int) ($result['inserted'] ?? 0);
                $errors += empty($result['error']) ? 0 : 1;
            }
            self::refresh_jobs();
            CA_News_DB::log('info', 'ingest_complete', 'Raccolta fonti completata.', compact('inserted', 'errors'));
        } catch (Throwable $error) {
            CA_News_DB::log('error', 'ingest_exception', $error->getMessage());
            $errors++;
        } finally {
            update_option('ca_news_last_ingest_at', time(), false);
            delete_transient(self::LOCK_KEY);
        }
        return array('status' => 'complete', 'inserted' => $inserted, 'errors' => $errors);
    }

    private static function ingest_source(array $source): array {
        if ($source['source_type'] === 'gdelt') {
            return self::ingest_gdelt($source);
        }
        global $wpdb;
        $sources_table = CA_News_DB::table('sources');
        $now = current_time('mysql', true);
        $settings = CA_News_DB::settings();

        $cache_filter = static function () use ($settings): int {
            return max(5, (int) $settings['source_cache_minutes']) * MINUTE_IN_SECONDS;
        };
        add_filter('wp_feed_cache_transient_lifetime', $cache_filter);
        require_once ABSPATH . WPINC . '/feed.php';
        $feed = fetch_feed($source['feed_url']);
        remove_filter('wp_feed_cache_transient_lifetime', $cache_filter);

        if (is_wp_error($feed)) {
            $message = $feed->get_error_message();
            $wpdb->update($sources_table, array('last_checked' => $now, 'last_error' => $message), array('id' => $source['id']), array('%s', '%s'), array('%d'));
            CA_News_DB::log('warning', 'source_failed', $message, array('source_id' => (int) $source['id'], 'name' => $source['name']));
            return array('inserted' => 0, 'error' => $message);
        }

        $limit = max(1, min(30, (int) $settings['max_items_per_source']));
        $items = $feed->get_items(0, $limit);
        $inserted = 0;
        foreach ($items as $item) {
            $title = self::clean_text((string) $item->get_title(), 420);
            $description = self::clean_text((string) ($item->get_description() ?: $item->get_content()), 1800);
            if (!$title || !self::is_relevant($title . ' ' . $description)) {
                continue;
            }

            $url = esc_url_raw((string) $item->get_permalink(), array('https'));
            if (!$url) {
                continue;
            }

            $source_name = (string) $source['name'];
            $source_url = $url;
            $embedded_source = $item->get_source();
            if ($embedded_source) {
                $embedded_name = self::clean_text((string) $embedded_source->get_title(), 190);
                $embedded_url = esc_url_raw((string) $embedded_source->get_link(), array('https'));
                if ($embedded_name) {
                    $source_name = $embedded_name;
                }
                if ($embedded_url) {
                    $source_url = $embedded_url;
                }
            }

            $published = $item->get_date('U');
            $published_at = $published ? gmdate('Y-m-d H:i:s', (int) $published) : $now;
            if ((int) $published && (int) $published < time() - ((int) $settings['lookback_hours'] * HOUR_IN_SECONDS)) {
                continue;
            }
            $guid = hash('sha256', strtolower(trim((string) ($item->get_id() ?: $url))) . '|' . $published_at);
            $fingerprint = hash('sha256', self::normalise_title($title));
            $cluster_key = self::find_cluster($title, $fingerprint, (int) $settings['lookback_hours']);

            $saved = $wpdb->insert(
                CA_News_DB::table('items'),
                array(
                    'source_id' => (int) $source['id'],
                    'source_guid' => $guid,
                    'source_url' => $url,
                    'source_name' => $source_name,
                    'title' => $title,
                    'excerpt' => $description,
                    'language' => sanitize_key((string) $source['language']),
                    'published_at' => $published_at,
                    'fingerprint' => $fingerprint,
                    'cluster_key' => $cluster_key,
                    'created_at' => $now,
                ),
                array('%d', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s')
            );
            if ($saved) {
                $inserted++;
            }
        }

        $wpdb->update(
            $sources_table,
            array('last_checked' => $now, 'last_success' => $now, 'last_error' => null),
            array('id' => $source['id']),
            array('%s', '%s', '%s'),
            array('%d')
        );
        return array('inserted' => $inserted, 'error' => '');
    }

    private static function ingest_gdelt(array $source): array {
        global $wpdb;
        $host = strtolower((string) wp_parse_url($source['feed_url'], PHP_URL_HOST));
        if ($host !== 'api.gdeltproject.org') {
            return array('inserted' => 0, 'error' => 'Endpoint GDELT non valido.');
        }
        $response = wp_safe_remote_get($source['feed_url'], array(
            'timeout' => 30,
            'redirection' => 2,
            'limit_response_size' => 2 * MB_IN_BYTES,
            'headers' => array('Accept' => 'application/json', 'User-Agent' => 'CalcioAffari-NewsEngine/' . CA_NEWS_VERSION),
        ));
        $now = current_time('mysql', true);
        if (is_wp_error($response) || wp_remote_retrieve_response_code($response) !== 200) {
            $message = is_wp_error($response) ? $response->get_error_message() : 'HTTP ' . wp_remote_retrieve_response_code($response);
            $wpdb->update(CA_News_DB::table('sources'), array('last_checked' => $now, 'last_error' => $message), array('id' => $source['id']), array('%s', '%s'), array('%d'));
            return array('inserted' => 0, 'error' => $message);
        }
        $data = json_decode(wp_remote_retrieve_body($response), true);
        if (!is_array($data) || !is_array($data['articles'] ?? null)) {
            return array('inserted' => 0, 'error' => 'Risposta GDELT non valida.');
        }

        $settings = CA_News_DB::settings();
        $limit = max(1, min(30, (int) $settings['max_items_per_source']));
        $inserted = 0;
        foreach (array_slice($data['articles'], 0, $limit) as $article) {
            $title = self::clean_text((string) ($article['title'] ?? ''), 420);
            $url = esc_url_raw((string) ($article['url'] ?? ''), array('https'));
            if (!$title || !$url) {
                continue;
            }
            $seen = sanitize_text_field((string) ($article['seendate'] ?? ''));
            $timestamp = $seen ? strtotime($seen . ' UTC') : false;
            $published_at = $timestamp ? gmdate('Y-m-d H:i:s', $timestamp) : $now;
            $source_name = sanitize_text_field((string) ($article['domain'] ?? wp_parse_url($url, PHP_URL_HOST)));
            $guid = hash('sha256', strtolower($url) . '|' . $published_at);
            $fingerprint = hash('sha256', self::normalise_title($title));
            $cluster_key = self::find_cluster($title, $fingerprint, (int) $settings['lookback_hours']);
            $saved = $wpdb->insert(
                CA_News_DB::table('items'),
                array(
                    'source_id' => (int) $source['id'],
                    'source_guid' => $guid,
                    'source_url' => $url,
                    'source_name' => $source_name,
                    'title' => $title,
                    'excerpt' => $title,
                    'language' => sanitize_key((string) ($article['language'] ?? 'unknown')),
                    'published_at' => $published_at,
                    'fingerprint' => $fingerprint,
                    'cluster_key' => $cluster_key,
                    'created_at' => $now,
                ),
                array('%d', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s')
            );
            if ($saved) {
                $inserted++;
            }
        }
        $wpdb->update(CA_News_DB::table('sources'), array('last_checked' => $now, 'last_success' => $now, 'last_error' => null), array('id' => $source['id']), array('%s', '%s', '%s'), array('%d'));
        return array('inserted' => $inserted, 'error' => '');
    }

    private static function clean_text(string $value, int $length): string {
        $value = html_entity_decode(wp_strip_all_tags($value, true), ENT_QUOTES | ENT_HTML5, 'UTF-8');
        $value = preg_replace('/\s+/u', ' ', trim($value));
        return mb_substr((string) $value, 0, $length);
    }

    private static function is_relevant(string $text): bool {
        $text = mb_strtolower($text);
        $off_topic = array(
            'emittenti televisive', 'emittenti radiofoniche', 'mercato televisivo', 'mercato radiofonico',
            'tv market', 'radio market', 'media market', 'marché des médias', 'marché de la télévision',
            'stock market', 'financial market', 'mercato azionario', 'mercato finanziario', 'mercato del lavoro',
        );
        foreach ($off_topic as $phrase) {
            if (str_contains($text, $phrase)) {
                return false;
            }
        }
        $keywords = array(
            'calciomercato', 'trasferiment', 'trattativ', 'cessione', 'acquisto', 'prestito', 'rinnovo', 'svincol', 'firma',
            'transfer', 'signing', 'signs for', 'loan move', 'contract extension', 'free agent', 'deal agreed',
            'fichaje', 'traspaso', 'mercado de pases', 'cesión', 'renovación',
            'transfert', 'mercato', 'prêt', 'prolongation',
            'wechsel', 'transfermarkt', 'leihe', 'vertragsverlängerung',
            'transferência', 'mercado da bola', 'empréstimo', 'renovação',
            'transfer haber', 'kiralık', 'sözleşme', '移籍', '契約更新', 'انتقالات', 'إعارة',
        );
        foreach ($keywords as $keyword) {
            if (str_contains($text, $keyword)) {
                return true;
            }
        }
        return false;
    }

    private static function normalise_title(string $title): string {
        $title = remove_accents(mb_strtolower($title));
        $title = preg_replace('/[^\p{L}\p{N}\s]/u', ' ', $title);
        $tokens = preg_split('/\s+/u', trim((string) $title), -1, PREG_SPLIT_NO_EMPTY);
        $stop = array_flip(array(
            'calciomercato', 'mercato', 'transfer', 'transfers', 'news', 'latest', 'breaking', 'live', 'football', 'calcio',
            'the', 'and', 'for', 'from', 'with', 'del', 'della', 'dello', 'dei', 'degli', 'delle', 'per', 'con', 'tra', 'una', 'un',
            'les', 'des', 'une', 'sur', 'pour', 'los', 'las', 'una', 'para', 'con', 'der', 'die', 'das', 'und', 'mit', 'von',
            'de', 'da', 'do', 'dos', 'das', 'para', 'com', 'por', 'son', 'dakika', 'haberleri',
        ));
        $tokens = array_values(array_unique(array_filter($tokens, static function ($token) use ($stop): bool {
            return mb_strlen($token) >= 3 && !isset($stop[$token]);
        })));
        $aliases = array(
            'juve' => 'juventus',
            'bianconeri' => 'juventus',
            'nerazzurri' => 'inter',
            'rossoneri' => 'milan',
            'giallorossi' => 'roma',
            'biancocelesti' => 'lazio',
            'partenopei' => 'napoli',
            'psg' => 'paris',
        );
        $tokens = array_map(static fn(string $token): string => $aliases[$token] ?? $token, $tokens);
        $tokens = array_values(array_unique($tokens));
        sort($tokens, SORT_STRING);
        return implode(' ', array_slice($tokens, 0, 18));
    }

    private static function find_cluster(string $title, string $fingerprint, int $lookback_hours): string {
        global $wpdb;
        $table = CA_News_DB::table('items');
        $since = gmdate('Y-m-d H:i:s', time() - max(6, $lookback_hours) * HOUR_IN_SECONDS);
        $candidates = (array) $wpdb->get_results(
            $wpdb->prepare("SELECT title, fingerprint, cluster_key FROM {$table} WHERE published_at >= %s ORDER BY id DESC LIMIT 300", $since),
            ARRAY_A
        );
        $normal = self::normalise_title($title);
        $tokens = array_filter(explode(' ', $normal));
        foreach ($candidates as $candidate) {
            if (hash_equals((string) $candidate['fingerprint'], $fingerprint)) {
                return (string) $candidate['cluster_key'];
            }
            $other = array_filter(explode(' ', self::normalise_title((string) $candidate['title'])));
            $intersection = count(array_intersect($tokens, $other));
            $minimum = min(count($tokens), count($other));
            $similarity = $minimum ? $intersection / $minimum : 0;
            if ($intersection >= 2 && ($similarity >= 0.34 || $intersection >= 3)) {
                return (string) $candidate['cluster_key'];
            }
        }
        return hash('sha256', $normal . '|' . gmdate('Y-m-d'));
    }

    public static function refresh_jobs(): void {
        global $wpdb;
        $items = CA_News_DB::table('items');
        $sources = CA_News_DB::table('sources');
        $jobs = CA_News_DB::table('jobs');
        $settings = CA_News_DB::settings();
        $since = gmdate('Y-m-d H:i:s', time() - max(6, (int) $settings['lookback_hours']) * HOUR_IN_SECONDS);
        $clusters = (array) $wpdb->get_col($wpdb->prepare("SELECT DISTINCT cluster_key FROM {$items} WHERE published_at >= %s", $since));

        foreach ($clusters as $cluster_key) {
            $evidence = (array) $wpdb->get_results(
                $wpdb->prepare(
                    "SELECT i.id, i.source_url AS url, i.source_name AS source, i.title, i.excerpt, i.language, i.published_at, s.source_type, s.trust_score
                     FROM {$items} i INNER JOIN {$sources} s ON s.id=i.source_id
                     WHERE i.cluster_key=%s ORDER BY i.published_at ASC LIMIT 12",
                    $cluster_key
                ),
                ARRAY_A
            );
            if (!$evidence) {
                continue;
            }
            $source_names = array_unique(array_map(static fn(array $row): string => mb_strtolower(trim($row['source'])), $evidence));
            $has_primary = count(array_filter($evidence, static fn(array $row): bool => $row['source_type'] === 'official' || (float) $row['trust_score'] >= 0.98)) > 0;
            $source_count = count($source_names);
            $ready = $source_count >= (int) $settings['minimum_sources'] || $has_primary;
            if (!$ready && !empty($settings['single_source_drafts']) && $settings['publication_mode'] !== 'auto') {
                $ready = true;
            }
            $status = $ready ? 'pending' : 'awaiting';
            $encoded = wp_json_encode($evidence, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            $existing = $wpdb->get_row($wpdb->prepare("SELECT id, status FROM {$jobs} WHERE cluster_key=%s", $cluster_key), ARRAY_A);
            if ($existing) {
                if (in_array($existing['status'], array('published', 'processed', 'rejected'), true)) {
                    continue;
                }
                $next_status = $existing['status'] === 'leased' ? 'leased' : $status;
                $wpdb->update(
                    $jobs,
                    array('status' => $next_status, 'evidence' => $encoded, 'evidence_count' => count($evidence), 'source_count' => $source_count, 'updated_at' => current_time('mysql', true)),
                    array('id' => $existing['id']),
                    array('%s', '%s', '%d', '%d', '%s'),
                    array('%d')
                );
            } else {
                $now = current_time('mysql', true);
                $wpdb->insert(
                    $jobs,
                    array('cluster_key' => $cluster_key, 'status' => $status, 'evidence' => $encoded, 'evidence_count' => count($evidence), 'source_count' => $source_count, 'created_at' => $now, 'updated_at' => $now),
                    array('%s', '%s', '%s', '%d', '%d', '%s', '%s')
                );
            }
        }
    }
}
