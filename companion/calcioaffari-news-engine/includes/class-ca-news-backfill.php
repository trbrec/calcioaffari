<?php

if (!defined('ABSPATH')) {
    exit;
}

/** Recover the editorial gap from 29 July 2026 without blocking an HTTP request. */
final class CA_News_Backfill {
    private const STATE_OPTION = 'ca_news_backfill_20260729';
    private const LOCK_KEY = 'ca_news_backfill_lock';
    private const EVENT = 'ca_news_backfill_event';
    private const START_GMT = '2026-07-29 00:00:00';
    private const PAGE_SIZE = 50;
    private const SOURCES = array(
        'calciomercato_it' => array(
            'feed_url' => 'https://www.calciomercato.it/feed/',
            'api_url' => 'https://www.calciomercato.it/wp-json/wp/v2/posts',
            'bounded_api' => true,
        ),
        'football_italia' => array(
            'feed_url' => 'https://football-italia.net/feed/',
            'api_url' => 'https://football-italia.net/wp-json/wp/v2/posts',
            'bounded_api' => false,
        ),
    );

    public static function schedule(): void {
        $state = self::state();
        if (!empty($state['completed']) || wp_next_scheduled(self::EVENT)) {
            return;
        }
        wp_schedule_single_event(time() + 5, self::EVENT);
    }

    public static function status(): array {
        $state = self::state();
        unset($state['cluster_keys']);
        return $state;
    }

    public static function run_batch(): array {
        if (get_transient(self::LOCK_KEY)) {
            return array_merge(self::status(), array('locked' => true));
        }
        set_transient(self::LOCK_KEY, '1', 2 * MINUTE_IN_SECONDS);
        $state = self::state();
        try {
            foreach (self::SOURCES as $key => $definition) {
                if (!empty($state['sources'][$key]['completed'])) {
                    continue;
                }
                self::process_source_page($key, $definition, $state);
            }

            $all_completed = true;
            foreach ($state['sources'] as $source_state) {
                if (empty($source_state['completed'])) {
                    $all_completed = false;
                    break;
                }
            }
            if ($all_completed) {
                $state['completed'] = true;
                $state['completed_at'] = current_time('mysql', true);
                CA_News_Ingestor::refresh_jobs((array) $state['cluster_keys']);
                CA_News_DB::log('info', 'backfill_completed', 'Recupero storico dal 29/07/2026 completato.', array(
                    'scanned' => (int) $state['scanned'],
                    'inserted' => (int) $state['inserted'],
                    'filtered' => (int) $state['filtered'],
                    'clusters' => count((array) $state['cluster_keys']),
                ));
            }
            update_option(self::STATE_OPTION, $state, false);
        } catch (Throwable $error) {
            $state['last_error'] = sanitize_text_field($error->getMessage());
            $state['last_error_at'] = current_time('mysql', true);
            update_option(self::STATE_OPTION, $state, false);
            CA_News_DB::log('error', 'backfill_failed', $error->getMessage());
        } finally {
            delete_transient(self::LOCK_KEY);
        }

        if (empty($state['completed'])) {
            wp_schedule_single_event(time() + 10, self::EVENT);
        }
        return self::status();
    }

    private static function state(): array {
        $stored = get_option(self::STATE_OPTION, array());
        if (is_array($stored) && !empty($stored['started_at'])) {
            return $stored;
        }
        $sources = array();
        foreach (array_keys(self::SOURCES) as $key) {
            $sources[$key] = array(
                'page' => 1,
                'completed' => false,
                'scanned' => 0,
                'inserted' => 0,
                'filtered' => 0,
                'last_date' => null,
                'last_error' => null,
            );
        }
        return array(
            'started_at' => current_time('mysql', true),
            'start_gmt' => self::START_GMT,
            'cutoff_gmt' => current_time('mysql', true),
            'completed' => false,
            'completed_at' => null,
            'scanned' => 0,
            'inserted' => 0,
            'filtered' => 0,
            'last_error' => null,
            'last_error_at' => null,
            'sources' => $sources,
            'cluster_keys' => array(),
        );
    }

    private static function process_source_page(string $key, array $definition, array &$state): void {
        global $wpdb;
        $hash = hash('sha256', strtolower((string) $definition['feed_url']));
        $source = $wpdb->get_row($wpdb->prepare(
            'SELECT * FROM ' . CA_News_DB::table('sources') . ' WHERE feed_hash=%s LIMIT 1',
            $hash
        ), ARRAY_A);
        if (!$source) {
            throw new RuntimeException(sprintf('Fonte del backfill non installata: %s', $definition['feed_url']));
        }

        $page = max(1, (int) $state['sources'][$key]['page']);
        $query = array(
            'page' => $page,
            'per_page' => self::PAGE_SIZE,
            'orderby' => 'date',
            'order' => 'desc',
            '_embed' => 1,
            '_fields' => 'id,date,date_gmt,link,title,excerpt,content,_links,_embedded',
        );
        if (!empty($definition['bounded_api'])) {
            $query['after'] = str_replace(' ', 'T', self::START_GMT);
            $query['before'] = str_replace(' ', 'T', (string) $state['cutoff_gmt']);
        }
        $url = add_query_arg($query, (string) $definition['api_url']);
        $response = wp_remote_get($url, array(
            'timeout' => 25,
            'redirection' => 3,
            'user-agent' => 'CalcioAffari-NewsEngine/' . CA_NEWS_VERSION,
            'headers' => array('Accept' => 'application/json'),
        ));
        if (is_wp_error($response)) {
            $state['sources'][$key]['last_error'] = $response->get_error_message();
            throw new RuntimeException($response->get_error_message());
        }
        $status = (int) wp_remote_retrieve_response_code($response);
        $decoded = json_decode((string) wp_remote_retrieve_body($response), true);
        if ($status === 400 && is_array($decoded) && ($decoded['code'] ?? '') === 'rest_post_invalid_page_number') {
            $state['sources'][$key]['completed'] = true;
            return;
        }
        if ($status !== 200 || !is_array($decoded)) {
            $message = sprintf('Archivio %s non disponibile (HTTP %d).', $key, $status);
            $state['sources'][$key]['last_error'] = $message;
            throw new RuntimeException($message);
        }

        $reached_start = false;
        foreach ($decoded as $post) {
            if (!is_array($post)) {
                continue;
            }
            $published_raw = (string) ($post['date_gmt'] ?? $post['date'] ?? '');
            $published = (int) strtotime($published_raw . (str_contains($published_raw, 'Z') ? '' : ' UTC'));
            if ($published <= 0) {
                continue;
            }
            $state['scanned']++;
            $state['sources'][$key]['scanned']++;
            $state['sources'][$key]['last_date'] = gmdate('Y-m-d H:i:s', $published);
            if ($published < strtotime(self::START_GMT . ' UTC')) {
                $reached_start = true;
                continue;
            }
            if ($published > strtotime((string) $state['cutoff_gmt'] . ' UTC')) {
                continue;
            }
            $categories = self::extract_categories($post);
            $stored = CA_News_Ingestor::ingest_external_item($source, array(
                'guid' => (string) ($post['id'] ?? ''),
                'url' => (string) ($post['link'] ?? ''),
                'source_name' => (string) $source['name'],
                'title' => (string) ($post['title']['rendered'] ?? ''),
                'description' => (string) ($post['excerpt']['rendered'] ?? ''),
                'content' => (string) ($post['content']['rendered'] ?? ''),
                'published_at' => $published,
                'categories' => $categories,
            ));
            if (!empty($stored['cluster_key'])) {
                $state['cluster_keys'][] = (string) $stored['cluster_key'];
            }
            if (!empty($stored['inserted'])) {
                $state['inserted']++;
                $state['sources'][$key]['inserted']++;
            } elseif (empty($stored['duplicate'])) {
                $state['filtered']++;
                $state['sources'][$key]['filtered']++;
            }
        }
        $state['cluster_keys'] = array_values(array_unique((array) $state['cluster_keys']));
        $state['sources'][$key]['last_error'] = null;
        if ($reached_start || count($decoded) < self::PAGE_SIZE) {
            $state['sources'][$key]['completed'] = true;
        } else {
            $state['sources'][$key]['page'] = $page + 1;
        }
    }

    private static function extract_categories(array $post): array {
        $categories = array();
        foreach ((array) ($post['_embedded']['wp:term'] ?? array()) as $terms) {
            foreach ((array) $terms as $term) {
                if (is_array($term) && !empty($term['name'])) {
                    $categories[] = sanitize_text_field((string) $term['name']);
                }
            }
        }
        return array_values(array_unique($categories));
    }
}
