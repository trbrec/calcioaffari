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
        $scanned = 0;
        $duplicates = 0;
        $filtered_total = 0;
        try {
            CA_News_DB::cleanup();
            foreach (CA_News_Sources::all(true) as $source) {
                $result = self::ingest_source($source);
                $inserted += (int) ($result['inserted'] ?? 0);
                $scanned += (int) ($result['scanned'] ?? 0);
                $duplicates += (int) ($result['duplicates'] ?? 0);
                $filtered_total += (int) ($result['filtered'] ?? 0);
                $errors += empty($result['error']) ? 0 : 1;
            }
            self::refresh_jobs();
            CA_News_DB::log('info', 'ingest_complete', 'Raccolta fonti completata.', compact('scanned', 'inserted', 'duplicates', 'filtered_total', 'errors'));
        } catch (Throwable $error) {
            CA_News_DB::log('error', 'ingest_exception', $error->getMessage());
            $errors++;
        } finally {
            update_option('ca_news_last_ingest_at', time(), false);
            update_option('ca_news_last_ingest_report', compact('scanned', 'inserted', 'duplicates', 'filtered_total', 'errors'), false);
            delete_transient(self::LOCK_KEY);
        }
        return array('status' => 'complete', 'scanned' => $scanned, 'inserted' => $inserted, 'duplicates' => $duplicates, 'filtered' => $filtered_total, 'errors' => $errors);
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
        $duplicates = 0;
        $filtered = array();
        foreach ($items as $item) {
            $source_name = (string) $source['name'];
            $source_url = (string) $item->get_permalink();
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
            $categories = array();
            foreach ((array) $item->get_categories() as $category) {
                if (is_object($category) && method_exists($category, 'get_label')) {
                    $categories[] = self::clean_text((string) $category->get_label(), 120);
                }
            }
            $stored = self::store_item($source, array(
                'guid' => (string) $item->get_id(),
                'url' => (string) $item->get_permalink(),
                'source_name' => $source_name,
                'source_url' => $source_url,
                'title' => (string) $item->get_title(),
                'description' => (string) $item->get_description(),
                'content' => (string) $item->get_content(),
                'published_at' => (int) $item->get_date('U'),
                'categories' => $categories,
            ), true);
            if (!empty($stored['inserted'])) {
                $inserted++;
            } elseif (!empty($stored['duplicate'])) {
                $duplicates++;
            } elseif (!empty($stored['rejection'])) {
                $reason = (string) $stored['rejection'];
                $filtered[$reason] = (int) ($filtered[$reason] ?? 0) + 1;
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
        return array(
            'scanned' => count($items),
            'inserted' => $inserted,
            'duplicates' => $duplicates,
            'filtered' => array_sum($filtered),
            'error' => '',
        );
    }

    private static function ingest_gdelt(array $source): array {
        return array(
            'inserted' => 0,
            'error' => 'GDELT è disattivato: un titolo senza estratto verificabile non è una prova editoriale sufficiente.',
        );
    }

    /**
     * Store one item supplied by a trusted archive adapter. The same admission,
     * de-duplication and clustering rules are used by live feeds and backfill.
     */
    public static function ingest_external_item(array $source, array $entry): array {
        return self::store_item($source, $entry, false);
    }

    private static function store_item(array $source, array $entry, bool $enforce_lookback): array {
        global $wpdb;
        $settings = CA_News_DB::settings();
        $title = self::clean_text((string) ($entry['title'] ?? ''), 420);
        $description = self::clean_excerpt_text((string) ($entry['description'] ?? ''), 1800);
        $content = self::clean_excerpt_text((string) ($entry['content'] ?? ''), 1800);
        if (mb_strlen($content) > mb_strlen($description)) {
            $description = $content;
        }
        $categories = array_values(array_filter(array_map(
            static fn($value): string => sanitize_text_field((string) $value),
            (array) ($entry['categories'] ?? array())
        )));
        $rejection = self::editorial_item_rejection_reason($title, $description, (string) $source['language'], $categories);
        if ($rejection !== '') {
            return array('inserted' => 0, 'rejection' => $rejection);
        }

        $url = esc_url_raw((string) ($entry['url'] ?? ''), array('https'));
        if (!$url) {
            return array('inserted' => 0, 'rejection' => 'URL sorgente assente o non valido.');
        }
        $published_input = $entry['published_at'] ?? 0;
        $published = is_numeric($published_input) ? (int) $published_input : (int) strtotime((string) $published_input);
        $published = $published > 0 ? $published : time();
        if ($enforce_lookback && $published < time() - ((int) $settings['lookback_hours'] * HOUR_IN_SECONDS)) {
            return array('inserted' => 0, 'rejection' => 'Elemento precedente alla finestra live.');
        }
        $published_at = gmdate('Y-m-d H:i:s', $published);
        $items_table = CA_News_DB::table('items');
        $existing = $wpdb->get_row($wpdb->prepare(
            "SELECT id,cluster_key FROM {$items_table} WHERE source_id=%d AND source_url=%s LIMIT 1",
            (int) $source['id'],
            $url
        ), ARRAY_A);
        if ($existing) {
            return array('inserted' => 0, 'duplicate' => 1, 'cluster_key' => (string) $existing['cluster_key']);
        }

        $guid_seed = trim((string) ($entry['guid'] ?? '')) ?: $url;
        $guid = hash('sha256', (int) $source['id'] . '|' . strtolower($guid_seed));
        $fingerprint = hash('sha256', self::normalise_title($title));
        $cluster_key = self::find_cluster($title, $fingerprint, (int) $settings['lookback_hours'], $published_at);
        $saved = $wpdb->insert(
            $items_table,
            array(
                'source_id' => (int) $source['id'],
                'source_guid' => $guid,
                'source_url' => $url,
                'source_name' => self::clean_text((string) ($entry['source_name'] ?? $source['name']), 190),
                'title' => $title,
                'excerpt' => $description,
                'language' => sanitize_key((string) $source['language']),
                'market_scope' => self::has_market_category($categories) ? 1 : 0,
                'published_at' => $published_at,
                'fingerprint' => $fingerprint,
                'cluster_key' => $cluster_key,
                'created_at' => current_time('mysql', true),
            ),
            array('%d', '%s', '%s', '%s', '%s', '%s', '%s', '%d', '%s', '%s', '%s', '%s')
        );
        return array(
            'inserted' => $saved ? 1 : 0,
            'cluster_key' => $cluster_key,
            'rejection' => $saved ? '' : 'Elemento già acquisito o non salvabile.',
        );
    }

    private static function clean_text(string $value, int $length): string {
        $value = html_entity_decode(wp_strip_all_tags($value, true), ENT_QUOTES | ENT_HTML5, 'UTF-8');
        $value = preg_replace('/\s+/u', ' ', trim($value));
        return mb_substr((string) $value, 0, $length);
    }

    private static function clean_excerpt_text(string $value, int $length): string {
        $value = self::clean_text($value, $length * 2);
        $value = preg_replace('/[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}\p{Cyrillic}\p{Arabic}\p{Hebrew}]+/u', ' ', $value);
        $value = preg_replace('/\s+/u', ' ', trim((string) $value));
        return mb_substr((string) $value, 0, $length);
    }

    public static function is_editorially_relevant(string $headline): bool {
        $text = mb_strtolower(trim((string) preg_replace('/\s+/u', ' ', wp_strip_all_tags($headline))));
        if (self::is_explicitly_off_topic($headline)) {
            return false;
        }
        foreach (self::relevance_patterns() as $pattern) {
            if (preg_match($pattern, $text)) {
                return true;
            }
        }
        return false;
    }

    public static function is_explicitly_off_topic(string $headline): bool {
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
            'title target', 'talks with executives', 'board meeting', 'sign up', 'newsletter', 'daily quiz', 'fantasy football', 'fpl ',
        );
        foreach ($off_topic as $phrase) {
            if (str_contains($text, $phrase)) {
                return true;
            }
        }
        return false;
    }

    private static function relevance_patterns(): array {
        return array(
            '/\b(?:calciomercato|trasferiment\p{L}*|trattativ\p{L}*|cession\p{L}*|acquist\p{L}*|prestito|rinnov\p{L}*|svincol\p{L}*|ingaggi\p{L}*|riscatt\p{L}*|rescission\p{L}*|accordo|offerta|proposta|visite mediche|obiettivo di mercato|nel mirino|punta su|vicin\p{L}* a|mercato in uscita|mercato in entrata|addio|saluta|passa (?:al|alla|ai|alle)|arriva (?:al|alla|ai|alle)|si tratta con|tratta per|contatti con|interesse (?:di|del|della)|ha scelto)\b/u',
            '/\bfirma\b.{0,35}\b(?:con|per|fino|contratto)\b/u',
            '/\b(?:transfer market|transfer rumours?|official transfer|sign(?:s|ed|ing)?|new signing|new boy|joins?|loan(?: move)?|contract extension|contract termination|free agent|deal(?: agreed)?|agreement|bid|offer|chase|swoop|move for|push for|race (?:for|to sign)|close (?:on|to)|on the verge|set to (?:join|leave)|expected to (?:join|sign)|medical|arrives? for|exit|target(?:s|ed)?|wish list|linked with|interest in|reject(?:s|ed)? (?:a )?(?:bid|offer)|wanted to leave)\b/u',
            '/\b(?:complete|confirm|announce|seal|agree|finalise|finalize)(?:s|d)?\b.{0,70}\btransfer\b/u',
            '/\btransfer\b.{0,70}\b(?:complete|confirmed|announced|sealed|agreed|finalised|finalized)\b/u',
            '/\b(?:enter|enters|entered|join|joins|joined)\b.{0,90}\brace\b.{0,55}\b(?:for|to sign|asking price)\b/u',
            '/\b(?:contract termination|terminat(?:e|es|ed|ion)\b.{0,35}\bcontract)\b/u',
            '/\b(?:talks|negotiations?)\b.{0,90}\b(?:over|with|between)\b/u',
            '/\b(?:fichaje|traspaso|mercado de pases|cesión|renovación|acuerdo|oferta)\b/u',
            '/\b(?:transfert|mercato|prêt|prolongation|accord|offre)\b/u',
            '/\b(?:wechsel|transfermarkt|leihe|vertragsverlängerung|angebot)\b/u',
            '/\b(?:transferência|mercado da bola|empréstimo|renovação|acordo|proposta)\b/u',
        );
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
        return mb_strlen($excerpt) >= 100 && count($words) >= 16;
    }

    public static function has_market_category(array $categories): bool {
        foreach ($categories as $category) {
            $normal = mb_strtolower(trim((string) preg_replace('/\s+/u', ' ', wp_strip_all_tags((string) $category))));
            if (in_array($normal, array('mercato', 'calciomercato', 'transfer market', 'latest transfers', 'transfers'), true)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Feed entries that aggregate several operations cannot be grounded as one
     * article. Reject them before clustering instead of asking the model to
     * choose or combine unrelated stories.
     */
    public static function is_single_story_item(string $title): bool {
        $text = mb_strtolower(trim((string) preg_replace('/\s+/u', ' ', wp_strip_all_tags($title))));
        $aggregate_patterns = array(
            '/\b(?:football|soccer)\W+live\b/u',
            '/\b(?:transfer|calciomercato|mercato)\s+(?:news\s+)?live\b/u',
            '/\blive\s+(?:blog|updates?|tracker)\b/u',
            '/\b(?:transfer|football)\s+rumou?rs?\s*:/u',
            '/\b(?:transfer|mercato)\s+(?:round[ -]?up|digest|tracker)\b/u',
            '/\b(?:top news|tutte le notizie|mercato no stop|il punto sul mercato)\b/u',
            '/\b(?:and|e)\s+more\b/u',
            '/\b(?:duo|double|two signings|doppio colpo)\b/u',
            '/\bdeals?\s+for\s+(?:two|three|four)\b/u',
            '/\b(?:two|three|four)\s+more\s+players\b/u',
            '/\band\s+tell\b/u',
            '/,\s*can\s+help\b/u',
            '/\s[|;]\s/u',
        );
        foreach ($aggregate_patterns as $pattern) {
            if (preg_match($pattern, $text)) {
                return false;
            }
        }
        return true;
    }

    /** Return an empty string only when an item may enter the editorial queue. */
    public static function editorial_item_rejection_reason(string $title, string $excerpt, string $language, array $categories = array()): string {
        if ($title === '') {
            return 'Titolo assente.';
        }
        if (!in_array(sanitize_key($language), array('it', 'en', 'fr', 'es', 'de', 'pt'), true)) {
            return 'Lingua sorgente non supportata.';
        }
        if (self::has_unsupported_script($title)) {
            return 'Titolo in un alfabeto non supportato dal desk italiano.';
        }
        if (self::is_explicitly_off_topic($title)) {
            return 'Titolo fuori dal perimetro del calciomercato.';
        }
        if (!self::is_editorially_relevant($title) && !self::has_market_category($categories)) {
            return 'Titolo non esplicitamente riferito a un trasferimento o a una trattativa.';
        }
        if (!self::is_single_story_item($title)) {
            return 'Contenuto aggregato o live: non descrive una sola operazione verificabile.';
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
            (string) ($row['language'] ?? ''),
            !empty($row['market_scope']) ? array('mercato') : array()
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

    private static function find_cluster(string $title, string $fingerprint, int $lookback_hours, string $published_at): string {
        global $wpdb;
        $table = CA_News_DB::table('items');
        $jobs = CA_News_DB::table('jobs');
        $anchor = (int) strtotime($published_at);
        $anchor = $anchor > 0 ? $anchor : time();
        $radius = max(6, $lookback_hours) * HOUR_IN_SECONDS;
        $since = gmdate('Y-m-d H:i:s', $anchor - $radius);
        $until = gmdate('Y-m-d H:i:s', $anchor + $radius);
        $candidates = (array) $wpdb->get_results(
            $wpdb->prepare(
                "SELECT i.title,i.fingerprint,i.cluster_key FROM {$table} i LEFT JOIN {$jobs} j ON j.cluster_key=i.cluster_key WHERE i.published_at BETWEEN %s AND %s AND (j.status IS NULL OR j.status<>'rejected') ORDER BY i.id DESC LIMIT 600",
                $since,
                $until
            ),
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
        return hash('sha256', 'v1.0.1|' . $normal . '|' . gmdate('Y-m-d', $anchor));
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

    public static function refresh_jobs(array $specific_cluster_keys = array()): void {
        global $wpdb;
        $items = CA_News_DB::table('items');
        $sources = CA_News_DB::table('sources');
        $jobs = CA_News_DB::table('jobs');
        $settings = CA_News_DB::settings();
        if ($specific_cluster_keys) {
            $clusters = array_values(array_unique(array_filter(array_map(
                static fn($value): string => preg_match('/^[a-f0-9]{64}$/', (string) $value) ? (string) $value : '',
                $specific_cluster_keys
            ))));
        } else {
            $since = gmdate('Y-m-d H:i:s', time() - max(6, (int) $settings['lookback_hours']) * HOUR_IN_SECONDS);
            $clusters = (array) $wpdb->get_col($wpdb->prepare("SELECT DISTINCT cluster_key FROM {$items} WHERE published_at >= %s", $since));
        }

        foreach ($clusters as $cluster_key) {
            $all_evidence = (array) $wpdb->get_results(
                $wpdb->prepare(
                    "SELECT i.id, i.source_url AS url, i.source_name AS source, i.title, i.excerpt, i.language, i.market_scope, i.published_at, s.source_type, s.trust_score
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
