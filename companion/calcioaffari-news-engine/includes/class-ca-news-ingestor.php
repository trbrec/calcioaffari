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
        $filtered = array();
        foreach ($items as $item) {
            $title = self::clean_text((string) $item->get_title(), 420);
            $description = self::clean_text((string) $item->get_description(), 1800);
            $content = self::clean_text((string) $item->get_content(), 1800);
            if (mb_strlen($content) > mb_strlen($description)) {
                $description = $content;
            }
            $rejection = self::editorial_item_rejection_reason($title, $description, (string) $source['language']);
            if ($rejection !== '') {
                $filtered[$rejection] = (int) ($filtered[$rejection] ?? 0) + 1;
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
        if ($filtered) {
            CA_News_DB::log('info', 'source_items_filtered', 'Elementi esclusi prima della coda editoriale.', array(
                'source_id' => (int) $source['id'],
                'name' => (string) $source['name'],
                'reasons' => $filtered,
            ));
        }
        return array('inserted' => $inserted, 'error' => '');
    }

    private static function ingest_gdelt(array $source): array {
        return array(
            'inserted' => 0,
            'error' => 'GDELT è disattivato: un titolo senza estratto verificabile non è una prova editoriale sufficiente.',
        );
    }

    private static function clean_text(string $value, int $length): string {
        $value = html_entity_decode(wp_strip_all_tags($value, true), ENT_QUOTES | ENT_HTML5, 'UTF-8');
        $value = preg_replace('/\s+/u', ' ', trim($value));
        return mb_substr((string) $value, 0, $length);
    }

    public static function is_editorially_relevant(string $headline): bool {
        $text = mb_strtolower(trim((string) preg_replace('/\s+/u', ' ', wp_strip_all_tags($headline))));
        $off_topic = array(
            'emittenti televisive', 'emittenti radiofoniche', 'mercato televisivo', 'mercato radiofonico',
            'tv market', 'radio market', 'media market', 'marché des médias', 'marché de la télévision',
            'stock market', 'financial market', 'mercato azionario', 'mercato finanziario', 'mercato del lavoro',
            'ncaa', 'transfer portal', 'eligibility case', 'college football', 'college basketball',
            'us open', 'australian open', 'wimbledon', 'roland garros', 'atp ', 'wta ', 'tennis',
            'nba ', 'nfl ', 'nhl ', 'mlb ', 'formula 1', 'motogp',
            'scores and fixtures', 'scores & fixtures', 'match preview', 'season opener',
            'kick-off time', 'kickoff time', 'starting xi', 'predicted lineup', 'match report',
            'title target',
        );
        foreach ($off_topic as $phrase) {
            if (str_contains($text, $phrase)) {
                return false;
            }
        }
        $patterns = array(
            '/\b(?:calciomercato|trasferiment\p{L}*|trattativ\p{L}*|cessione|acquist\p{L}*|prestito|rinnov\p{L}*|svincol\p{L}*|ingaggi\p{L}*|accordo|offerta|visite mediche|obiettivo di mercato|nel mirino|punta su|vicino a)\b/u',
            '/\bfirma\b.{0,35}\b(?:con|per|fino|contratto)\b/u',
            '/\b(?:transfer market|transfer rumours?|official transfer|sign(?:s|ed|ing)?|new signing|new boy|joins?|loan(?: move)?|contract extension|free agent|deal(?: agreed)?|agreement|bid|offer|chase|swoop|move for|push for|race (?:for|to sign)|close (?:on|to)|set to (?:join|leave)|expected to (?:join|sign)|medical|arrives? for|exit)\b/u',
            '/\b(?:complete|confirm|announce|seal|agree|finalise|finalize)(?:s|d)?\b.{0,70}\btransfer\b/u',
            '/\btransfer\b.{0,70}\b(?:complete|confirmed|announced|sealed|agreed|finalised|finalized)\b/u',
            '/\b(?:enter|enters|entered|join|joins|joined)\b.{0,90}\brace\b.{0,55}\b(?:for|to sign|asking price)\b/u',
            '/\b(?:contract termination|terminat(?:e|es|ed|ion)\b.{0,35}\bcontract)\b/u',
            '/\b(?:talks|negotiations?)\b.{0,90}\bover\b/u',
            '/\b(?:fichaje|traspaso|mercado de pases|cesión|renovación|acuerdo|oferta)\b/u',
            '/\b(?:transfert|mercato|prêt|prolongation|accord|offre)\b/u',
            '/\b(?:wechsel|transfermarkt|leihe|vertragsverlängerung|angebot)\b/u',
            '/\b(?:transferência|mercado da bola|empréstimo|renovação|acordo|proposta)\b/u',
        );
        foreach ($patterns as $pattern) {
            if (preg_match($pattern, $text)) {
                return true;
            }
        }
        return false;
    }

    public static function has_unsupported_script(string $text): bool {
        return 1 === preg_match('/[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}\p{Cyrillic}\p{Arabic}\p{Hebrew}]/u', $text);
    }

    public static function has_substantive_excerpt(string $title, string $excerpt): bool {
        $title = trim((string) preg_replace('/\s+/u', ' ', wp_strip_all_tags($title)));
        $excerpt = trim((string) preg_replace('/\s+/u', ' ', wp_strip_all_tags($excerpt)));
        if ($excerpt === '' || mb_strtolower($excerpt) === mb_strtolower($title)) {
            return false;
        }
        $words = preg_split('/\s+/u', $excerpt, -1, PREG_SPLIT_NO_EMPTY);
        return mb_strlen($excerpt) >= 180 && count($words) >= 28;
    }

    /** Return an empty string only when an item may enter the editorial queue. */
    public static function editorial_item_rejection_reason(string $title, string $excerpt, string $language): string {
        if ($title === '') {
            return 'Titolo assente.';
        }
        if (!in_array(sanitize_key($language), array('it', 'en', 'fr', 'es', 'de', 'pt'), true)) {
            return 'Lingua sorgente non supportata.';
        }
        if (self::has_unsupported_script($title . ' ' . $excerpt)) {
            return 'Alfabeto non supportato dal desk italiano.';
        }
        if (!self::is_editorially_relevant($title)) {
            return 'Titolo non esplicitamente riferito a un trasferimento o a una trattativa.';
        }
        if (!self::has_substantive_excerpt($title, $excerpt)) {
            return 'Estratto insufficiente: il solo titolo non costituisce una prova editoriale.';
        }
        return '';
    }

    public static function evidence_is_substantive(array $row): bool {
        return self::editorial_item_rejection_reason(
            (string) ($row['title'] ?? ''),
            (string) ($row['excerpt'] ?? ''),
            (string) ($row['language'] ?? '')
        ) === '';
    }

    /**
     * Revalidate every unprocessed job after a stricter admission policy.
     * Leases are deliberately cleared so an article generated from evidence
     * that is no longer admissible cannot be submitted after the migration.
     */
    public static function revalidate_open_jobs(): array {
        global $wpdb;
        $jobs = CA_News_DB::table('jobs');
        $settings = CA_News_DB::settings();
        $rows = (array) $wpdb->get_results(
            "SELECT id,status,evidence,error_message FROM {$jobs} WHERE status IN ('pending','awaiting','leased') OR (status='rejected' AND (error_message LIKE 'Quarantena audit 0.8.7:%' OR error_message='Notizia messa in quarantena: il titolo non descrive esplicitamente un trasferimento o una trattativa.')) ORDER BY id ASC LIMIT 2000",
            ARRAY_A
        );
        $result = array('checked' => 0, 'quarantined' => 0, 'restored' => 0);

        foreach ($rows as $row) {
            $result['checked']++;
            $decoded = json_decode((string) $row['evidence'], true);
            $evidence = is_array($decoded)
                ? array_values(array_filter($decoded, array(__CLASS__, 'evidence_is_substantive')))
                : array();
            $now = current_time('mysql', true);

            if (!$evidence) {
                $wpdb->update(
                    $jobs,
                    array(
                        'status' => 'rejected',
                        'error_message' => 'Notizia messa in quarantena: il titolo non descrive esplicitamente un trasferimento o una trattativa.',
                        'lease_hash' => null,
                        'lease_expires_at' => null,
                        'updated_at' => $now,
                    ),
                    array('id' => (int) $row['id']),
                    array('%s', '%s', '%s', '%s', '%s'),
                    array('%d')
                );
                $result['quarantined']++;
                continue;
            }

            $source_names = array_unique(array_map(static fn(array $item): string => mb_strtolower(trim((string) $item['source'])), $evidence));
            $has_primary = count(array_filter($evidence, static fn(array $item): bool => $item['source_type'] === 'official' || (float) $item['trust_score'] >= 0.98)) > 0;
            $source_count = count($source_names);
            $ready = $source_count >= (int) $settings['minimum_sources'] || $has_primary;
            if (!$ready && !empty($settings['single_source_drafts']) && $settings['publication_mode'] !== 'auto') {
                $ready = true;
            }
            $next_status = $ready ? 'pending' : 'awaiting';
            $wpdb->update(
                $jobs,
                array(
                    'status' => $next_status,
                    'evidence' => wp_json_encode($evidence, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                    'evidence_count' => count($evidence),
                    'source_count' => $source_count,
                    'attempt_count' => 0,
                    'last_attempt_at' => null,
                    'result_json' => null,
                    'confidence' => null,
                    'error_message' => null,
                    'lease_hash' => null,
                    'lease_expires_at' => null,
                    'updated_at' => $now,
                ),
                array('id' => (int) $row['id']),
                array('%s', '%s', '%d', '%d', '%d', '%s', '%s', '%s', '%s', '%s', '%s', '%s'),
                array('%d')
            );
            if ($row['status'] === 'rejected') {
                $result['restored']++;
            }
        }

        return $result;
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
        foreach ($candidates as $candidate) {
            if (hash_equals((string) $candidate['fingerprint'], $fingerprint)) {
                return (string) $candidate['cluster_key'];
            }
            if (self::titles_are_same_story($title, (string) $candidate['title'])) {
                return (string) $candidate['cluster_key'];
            }
        }
        $normal = self::normalise_title($title);
        return hash('sha256', $normal . '|' . gmdate('Y-m-d'));
    }

    /**
     * Prefer a missed duplicate to a false merge. Two shared name tokens such
     * as "Mikel Arteta" are not enough to prove that two headlines concern the
     * same event; at least three meaningful tokens and strong overlap are
     * required.
     */
    public static function titles_are_same_story(string $left, string $right): bool {
        $left_tokens = array_filter(explode(' ', self::normalise_title($left)));
        $right_tokens = array_filter(explode(' ', self::normalise_title($right)));
        $intersection = count(array_intersect($left_tokens, $right_tokens));
        $minimum = min(count($left_tokens), count($right_tokens));
        $union = count(array_unique(array_merge($left_tokens, $right_tokens)));
        $containment = $minimum ? $intersection / $minimum : 0;
        $jaccard = $union ? $intersection / $union : 0;
        return $intersection >= 3 && $containment >= 0.50 && $jaccard >= 0.30;
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
            $all_evidence = (array) $wpdb->get_results(
                $wpdb->prepare(
                    "SELECT i.id, i.source_url AS url, i.source_name AS source, i.title, i.excerpt, i.language, i.published_at, s.source_type, s.trust_score
                     FROM {$items} i INNER JOIN {$sources} s ON s.id=i.source_id
                     WHERE i.cluster_key=%s ORDER BY i.published_at ASC LIMIT 12",
                    $cluster_key
                ),
                ARRAY_A
            );
            $evidence = array_values(array_filter($all_evidence, array(__CLASS__, 'evidence_is_substantive')));
            if (!$evidence) {
                $existing = $wpdb->get_row($wpdb->prepare("SELECT id, status FROM {$jobs} WHERE cluster_key=%s", $cluster_key), ARRAY_A);
                if ($existing && $existing['status'] !== 'leased' && !in_array($existing['status'], array('published', 'processed', 'rejected'), true)) {
                    $wpdb->update(
                        $jobs,
                        array(
                            'status' => 'rejected',
                            'error_message' => 'Notizia messa in quarantena: prove insufficienti o contenuto fuori perimetro editoriale.',
                            'updated_at' => current_time('mysql', true),
                        ),
                        array('id' => (int) $existing['id']),
                        array('%s', '%s', '%s'),
                        array('%d')
                    );
                }
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
