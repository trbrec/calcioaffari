<?php

if (!defined('ABSPATH')) {
    exit;
}

final class CA_News_Publisher {
    private const EVENT_TYPES = array('transfer', 'loan', 'renewal', 'release', 'rumour', 'official', 'other');

    public static function publish(array $job, array $result, string $model_name): array|WP_Error {
        $validated = self::validate($job, $result);
        if (is_wp_error($validated)) {
            return $validated;
        }

        $settings = CA_News_DB::settings();
        $evidence = json_decode((string) $job['evidence'], true);
        $evidence = is_array($evidence) ? $evidence : array();
        $sources = self::build_sources($evidence, $validated['source_ids']);
        $has_primary = self::has_primary_source($evidence, $validated['source_ids']);
        $is_official = !empty($validated['official']) && ($has_primary || empty($settings['require_primary_for_official']));

        $post_status = self::post_status($validated, count($sources), $has_primary, $settings);
        $post_type = in_array($validated['event_type'], self::EVENT_TYPES, true) && $validated['event_type'] !== 'other' ? 'ca_affare' : 'post';
        if (!post_type_exists($post_type)) {
            $post_type = 'post';
        }

        $post_id = wp_insert_post(array(
            'post_type' => $post_type,
            'post_status' => $post_status,
            'post_title' => $validated['title'],
            'post_excerpt' => $validated['excerpt'],
            'post_content' => $validated['body_html'],
            'post_author' => get_user_by('id', (int) $settings['default_author']) ? (int) $settings['default_author'] : get_current_user_id(),
            'meta_input' => array(
                'ca_fonte_nome' => $sources[0]['name'] ?? '',
                'ca_fonte_url' => $sources[0]['url'] ?? '',
                'ca_fonti' => $sources,
                'ca_ai_generated' => 1,
                'ca_ai_human_reviewed' => 0,
                'ca_ai_model' => sanitize_text_field($model_name),
                'ca_ai_confidence' => $validated['confidence'],
                'ca_ai_job_id' => (int) $job['id'],
                'ca_ai_cluster_key' => (string) $job['cluster_key'],
                'ca_discovery_provider' => self::uses_gdelt($evidence, $validated['source_ids']) ? 'GDELT' : '',
                'ca_ufficiale' => $is_official ? '1' : '0',
                'ca_giocatore' => $validated['deal']['player'],
                'ca_club_partenza' => $validated['deal']['from_club'],
                'ca_club_arrivo' => $validated['deal']['to_club'],
                'ca_formula' => $validated['deal']['formula'],
                'ca_costo' => $validated['deal']['fee'],
                'ca_scadenza_contratto' => $validated['deal']['contract_until'],
                'ca_data_ufficialita' => $is_official ? $validated['deal']['official_date'] : '',
                'ca_logo_domain' => self::source_domain($sources[0]['url'] ?? ''),
            ),
        ), true);

        if (is_wp_error($post_id)) {
            return $post_id;
        }

        self::assign_terms((int) $post_id, 'ca_squadra', $validated['teams']);
        self::assign_terms((int) $post_id, 'ca_campionato', $validated['competitions']);
        if ($post_type === 'ca_affare') {
            self::assign_terms((int) $post_id, 'ca_stato_affare', array($is_official ? 'Ufficiale' : 'Trattativa'));
        }

        CA_News_DB::log('info', 'article_created', 'Articolo creato dal motore locale.', array(
            'job_id' => (int) $job['id'],
            'post_id' => (int) $post_id,
            'post_status' => $post_status,
            'confidence' => $validated['confidence'],
            'sources' => count($sources),
        ));
        return array('post_id' => (int) $post_id, 'post_status' => $post_status, 'official' => $is_official);
    }

    private static function validate(array $job, array $result): array|WP_Error {
        $settings = CA_News_DB::settings();
        $title = sanitize_text_field((string) ($result['title'] ?? ''));
        $excerpt = sanitize_text_field((string) ($result['excerpt'] ?? ''));
        $body = wp_kses_post((string) ($result['body_html'] ?? ''));
        $plain_body = trim(wp_strip_all_tags($body));
        $word_count = count(preg_split('/\s+/u', $plain_body, -1, PREG_SPLIT_NO_EMPTY));

        if (mb_strlen($title) < 20 || mb_strlen($title) > 145) {
            return new WP_Error('ca_news_bad_title', __('Titolo assente o fuori lunghezza.', 'calcioaffari-news-engine'));
        }
        if (mb_strlen($excerpt) < 45 || mb_strlen($excerpt) > 360) {
            return new WP_Error('ca_news_bad_excerpt', __('Sommario assente o fuori lunghezza.', 'calcioaffari-news-engine'));
        }
        if ($word_count < (int) $settings['article_min_words'] || $word_count > (int) $settings['article_max_words']) {
            return new WP_Error('ca_news_bad_length', sprintf(__('Articolo fuori lunghezza: %d parole.', 'calcioaffari-news-engine'), $word_count));
        }
        if (preg_match('#https?://#i', $title . ' ' . $excerpt . ' ' . $body)) {
            return new WP_Error('ca_news_inline_url', __('Il testo contiene URL non consentiti: le fonti vengono gestite separatamente.', 'calcioaffari-news-engine'));
        }

        $evidence = json_decode((string) $job['evidence'], true);
        $evidence = is_array($evidence) ? $evidence : array();
        $allowed_ids = array_map('intval', wp_list_pluck($evidence, 'id'));
        $source_ids = array_values(array_unique(array_map('intval', (array) ($result['source_ids'] ?? array()))));
        $source_ids = array_values(array_intersect($source_ids, $allowed_ids));
        if (!$source_ids) {
            return new WP_Error('ca_news_no_sources', __('Nessuna fonte valida selezionata.', 'calcioaffari-news-engine'));
        }

        $claims = is_array($result['claims'] ?? null) ? $result['claims'] : array();
        foreach ($claims as $claim) {
            $claim_sources = array_intersect(array_map('intval', (array) ($claim['source_ids'] ?? array())), $allowed_ids);
            if (empty($claim['text']) || !$claim_sources) {
                return new WP_Error('ca_news_unsupported_claim', __('Una delle affermazioni non è collegata a fonti verificabili.', 'calcioaffari-news-engine'));
            }
        }

        if (self::has_long_source_overlap($plain_body, $evidence)) {
            return new WP_Error('ca_news_source_overlap', __('Il testo è troppo simile a una fonte e richiede revisione.', 'calcioaffari-news-engine'));
        }

        $event_type = sanitize_key((string) ($result['event_type'] ?? 'other'));
        if (!in_array($event_type, self::EVENT_TYPES, true)) {
            $event_type = 'other';
        }
        $deal_input = is_array($result['deal'] ?? null) ? $result['deal'] : array();
        $deal = array();
        foreach (array('player', 'from_club', 'to_club', 'formula', 'fee', 'contract_until', 'official_date') as $field) {
            $deal[$field] = sanitize_text_field((string) ($deal_input[$field] ?? ''));
        }

        return array(
            'title' => $title,
            'excerpt' => $excerpt,
            'body_html' => $body,
            'event_type' => $event_type,
            'official' => rest_sanitize_boolean($result['official'] ?? false),
            'confidence' => max(0.0, min(1.0, (float) ($result['confidence'] ?? 0))),
            'source_ids' => $source_ids,
            'claims' => $claims,
            'safety_flags' => array_values(array_filter(array_map('sanitize_text_field', (array) ($result['safety_flags'] ?? array())))),
            'teams' => self::clean_terms($result['teams'] ?? array()),
            'competitions' => self::clean_terms($result['competitions'] ?? array()),
            'deal' => $deal,
        );
    }

    private static function post_status(array $result, int $source_count, bool $has_primary, array $settings): string {
        if ($settings['publication_mode'] === 'draft') {
            return 'draft';
        }
        if ($settings['publication_mode'] === 'review') {
            return 'pending';
        }

        $safe = empty($result['safety_flags']);
        $enough_sources = $source_count >= (int) $settings['minimum_sources'] || $has_primary;
        $high_confidence = (float) $result['confidence'] >= (float) $settings['auto_confidence'];
        if (!$safe || !$enough_sources || !$high_confidence || self::daily_count() >= (int) $settings['max_posts_per_day']) {
            return 'pending';
        }
        return 'publish';
    }

    private static function daily_count(): int {
        $query = new WP_Query(array(
            'post_type' => array('post', 'ca_affare'),
            'post_status' => 'publish',
            'date_query' => array(array('after' => 'today midnight', 'inclusive' => true)),
            'meta_key' => 'ca_ai_generated',
            'meta_value' => '1',
            'fields' => 'ids',
            'posts_per_page' => 1,
            'no_found_rows' => false,
        ));
        return (int) $query->found_posts;
    }

    private static function build_sources(array $evidence, array $selected_ids): array {
        $sources = array();
        $seen = array();
        foreach ($evidence as $row) {
            if (!in_array((int) $row['id'], $selected_ids, true)) {
                continue;
            }
            $url = esc_url_raw((string) $row['url'], array('https'));
            $key = mb_strtolower(trim((string) $row['source'])) . '|' . $url;
            if (!$url || isset($seen[$key])) {
                continue;
            }
            $seen[$key] = true;
            $sources[] = array(
                'name' => sanitize_text_field((string) $row['source']),
                'url' => $url,
                'published_at' => sanitize_text_field((string) $row['published_at']),
            );
        }
        return CA_News_Content::sanitize_sources($sources);
    }

    private static function has_primary_source(array $evidence, array $selected_ids): bool {
        foreach ($evidence as $row) {
            if (in_array((int) $row['id'], $selected_ids, true) && ($row['source_type'] === 'official' || (float) $row['trust_score'] >= 0.98)) {
                return true;
            }
        }
        return false;
    }

    private static function uses_gdelt(array $evidence, array $selected_ids): bool {
        foreach ($evidence as $row) {
            if (in_array((int) $row['id'], $selected_ids, true) && $row['source_type'] === 'gdelt') {
                return true;
            }
        }
        return false;
    }

    private static function has_long_source_overlap(string $body, array $evidence): bool {
        $body = mb_strtolower(remove_accents($body));
        foreach ($evidence as $row) {
            $source = mb_strtolower(remove_accents((string) ($row['excerpt'] ?? '')));
            $words = preg_split('/\s+/u', preg_replace('/[^\p{L}\p{N}\s]/u', ' ', $source), -1, PREG_SPLIT_NO_EMPTY);
            for ($i = 0; $i + 15 < count($words); $i += 4) {
                $sequence = implode(' ', array_slice($words, $i, 16));
                if (mb_strlen($sequence) > 80 && str_contains($body, $sequence)) {
                    return true;
                }
            }
        }
        return false;
    }

    private static function clean_terms($values): array {
        $clean = array_filter(array_map(static fn($value): string => sanitize_text_field((string) $value), (array) $values));
        return array_slice(array_values(array_unique($clean)), 0, 12);
    }

    private static function assign_terms(int $post_id, string $taxonomy, array $terms): void {
        if (!$terms || !taxonomy_exists($taxonomy)) {
            return;
        }
        wp_set_object_terms($post_id, $terms, $taxonomy, false);
    }

    private static function source_domain(string $url): string {
        $host = (string) wp_parse_url($url, PHP_URL_HOST);
        return preg_replace('/^www\./i', '', $host);
    }
}
