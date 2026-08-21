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
                'ca_ai_safety_flags' => $validated['safety_flags'],
                'ca_ai_editorial_audit' => $validated['editorial_audit'],
                'ca_ai_word_count' => $validated['word_count'],
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
        $evidence = json_decode((string) $job['evidence'], true);
        $evidence = is_array($evidence) ? $evidence : array();
        $raw_title = (string) ($result['title'] ?? '');
        $raw_excerpt = (string) ($result['excerpt'] ?? '');
        $raw_body = (string) ($result['body_html'] ?? '');
        $title_without_sources = self::sanitize_source_mentions(self::sanitize_internal_markers(self::sanitize_inline_urls($raw_title)), $evidence);
        $excerpt_without_sources = self::sanitize_source_mentions(self::sanitize_internal_markers(self::sanitize_inline_urls($raw_excerpt)), $evidence);
        $body_without_sources = self::sanitize_source_mentions(self::sanitize_internal_markers(self::sanitize_inline_urls($raw_body, true)), $evidence);
        $source_mentions_removed = $title_without_sources !== self::sanitize_internal_markers(self::sanitize_inline_urls($raw_title))
            || $excerpt_without_sources !== self::sanitize_internal_markers(self::sanitize_inline_urls($raw_excerpt))
            || $body_without_sources !== self::sanitize_internal_markers(self::sanitize_inline_urls($raw_body, true));
        $title = sanitize_text_field(self::normalize_italian_copy($title_without_sources));
        $excerpt = sanitize_text_field(self::normalize_italian_copy($excerpt_without_sources));
        $body = wp_kses_post(self::remove_redundant_leading_heading(self::normalize_italian_copy($body_without_sources), $title));
        $plain_body = trim(wp_strip_all_tags($body));
        $excerpt = self::normalize_excerpt($excerpt, $plain_body);
        $word_count = count(preg_split('/\s+/u', $plain_body, -1, PREG_SPLIT_NO_EMPTY));
        $length_warning = self::editorial_length_warning($word_count, (int) $settings['article_min_words'], (int) $settings['article_max_words']);

        $editorial_audit = self::validate_editorial_audit($result['editorial_audit'] ?? null);
        if (is_wp_error($editorial_audit)) {
            return $editorial_audit;
        }

        if (mb_strlen($title) < 20 || mb_strlen($title) > 145) {
            return new WP_Error('ca_news_bad_title', __('Titolo assente o fuori lunghezza.', 'calcioaffari-news-engine'));
        }
        if (mb_strlen($excerpt) < 45 || mb_strlen($excerpt) > 360) {
            return new WP_Error('ca_news_bad_excerpt', __('Sommario assente o fuori lunghezza.', 'calcioaffari-news-engine'));
        }
        if (self::has_non_italian_copy($title, $plain_body)) {
            return new WP_Error('ca_news_non_italian_copy', __('Titolo o testo non sono in italiano editoriale.', 'calcioaffari-news-engine'));
        }
        if ($word_count < 80) {
            return new WP_Error('ca_news_body_too_short', sprintf(__('Testo insufficiente per la pubblicazione: %d parole; minimo redazionale 80.', 'calcioaffari-news-engine'), $word_count));
        }
        if (preg_match('#https?://#i', $title . ' ' . $excerpt . ' ' . $body)) {
            return new WP_Error('ca_news_inline_url', __('Il testo contiene URL non consentiti: le fonti vengono gestite separatamente.', 'calcioaffari-news-engine'));
        }
        if (preg_match('/<h[1-6]\b/i', $body)) {
            return new WP_Error('ca_news_article_heading', __('La notizia breve contiene sottotitoli non ammessi.', 'calcioaffari-news-engine'));
        }
        if (preg_match('/\b(?:una|diverse) font[ei] giornalistic[ae]\b/iu', $title . ' ' . $excerpt . ' ' . $plain_body)) {
            return new WP_Error('ca_news_generic_attribution', __('Attribuzione generica non ammessa: la testata deve essere indicata esplicitamente.', 'calcioaffari-news-engine'));
        }

        $allowed_ids = array_map('intval', wp_list_pluck($evidence, 'id'));
        $declared_source_ids = array_values(array_unique(array_map('intval', (array) ($result['source_ids'] ?? array()))));
        $source_ids = array_values(array_intersect($declared_source_ids, $allowed_ids));
        if (count($source_ids) !== count($declared_source_ids)) {
            return new WP_Error('ca_news_invalid_source_mapping', __('La risposta contiene riferimenti a prove non disponibili.', 'calcioaffari-news-engine'));
        }

        $claims = is_array($result['claims'] ?? null) ? $result['claims'] : array();
        $valid_claims = array();
        $claim_source_ids = array();
        foreach ($claims as $claim) {
            $claim_text = sanitize_text_field((string) ($claim['text'] ?? ''));
            $claim_sources = array_values(array_unique(array_intersect(array_map('intval', (array) ($claim['source_ids'] ?? array())), $allowed_ids)));
            if ($claim_text === '' || !$claim_sources) {
                return new WP_Error('ca_news_incomplete_claim_mapping', __('Mappatura delle affermazioni incompleta.', 'calcioaffari-news-engine'));
            }
            if (!self::claim_is_represented($claim_text, $title . ' ' . $excerpt . ' ' . $plain_body)) {
                return new WP_Error('ca_news_unmapped_article_claim', __('Una dichiarazione strutturata non è rintracciabile nel testo dell’articolo.', 'calcioaffari-news-engine'));
            }
            $quotes = self::validate_evidence_quotes($claim['evidence_quotes'] ?? null, $claim_sources, $evidence);
            if (is_wp_error($quotes)) {
                return $quotes;
            }
            $valid_claims[] = array('text' => $claim_text, 'source_ids' => $claim_sources, 'evidence_quotes' => $quotes);
            $claim_source_ids = array_merge($claim_source_ids, $claim_sources);
        }
        $claim_source_ids = array_values(array_unique($claim_source_ids));
        sort($source_ids, SORT_NUMERIC);
        sort($claim_source_ids, SORT_NUMERIC);
        if (!$source_ids || !$valid_claims) {
            return new WP_Error('ca_news_no_sources', __('Nessuna fonte valida selezionata.', 'calcioaffari-news-engine'));
        }
        if ($source_ids !== $claim_source_ids) {
            return new WP_Error('ca_news_source_union_mismatch', __('source_ids non coincide esattamente con le prove usate nelle affermazioni.', 'calcioaffari-news-engine'));
        }
        $selected_evidence = array_values(array_filter($evidence, static fn(array $row): bool => in_array((int) ($row['id'] ?? 0), $source_ids, true)));
        if (!$selected_evidence || !array_filter($selected_evidence, array('CA_News_Ingestor', 'evidence_is_substantive'))) {
            return new WP_Error('ca_news_insufficient_evidence', __('Prove insufficienti: il solo titolo non può generare un articolo.', 'calcioaffari-news-engine'));
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
        if ($deal['player'] === '' || ($deal['from_club'] === '' && $deal['to_club'] === '')) {
            $event_type = 'other';
        }

        $safety_flags = array_values(array_filter(array_map('sanitize_text_field', (array) ($result['safety_flags'] ?? array()))));
        foreach ($safety_flags as $flag) {
            if (preg_match('/prove insufficienti|mappatura.+incompleta|affermazion.+non supportat|storie.+distinte|fatti.+inventat/iu', $flag)) {
                return new WP_Error('ca_news_blocking_safety_flag', sprintf(__('Notizia messa in quarantena: %s', 'calcioaffari-news-engine'), $flag));
            }
        }
        if ($source_mentions_removed) {
            $safety_flags[] = __('Riferimenti tecnici alle fonti rimossi automaticamente.', 'calcioaffari-news-engine');
        }
        if (self::has_thin_evidence($evidence, $source_ids)) {
            $safety_flags[] = __('Prove disponibili molto sintetiche: verificare il testo sulla fonte originale.', 'calcioaffari-news-engine');
        }
        if ($length_warning !== '') {
            $safety_flags[] = $length_warning;
        }

        return array(
            'title' => $title,
            'excerpt' => $excerpt,
            'body_html' => $body,
            'event_type' => $event_type,
            'official' => rest_sanitize_boolean($result['official'] ?? false),
            'confidence' => max(0.0, min(1.0, (float) ($result['confidence'] ?? 0))),
            'source_ids' => $source_ids,
            'claims' => $valid_claims,
            'editorial_audit' => $editorial_audit,
            'safety_flags' => array_values(array_unique($safety_flags)),
            'word_count' => $word_count,
            'teams' => self::clean_terms($result['teams'] ?? array()),
            'competitions' => self::clean_terms($result['competitions'] ?? array()),
            'deal' => $deal,
        );
    }

    public static function validate_editorial_audit(mixed $value): array|WP_Error {
        if (!is_array($value)) {
            return new WP_Error('ca_news_missing_editorial_audit', __('Revisione editoriale indipendente assente.', 'calcioaffari-news-engine'));
        }
        foreach (array('approved', 'single_story', 'language_ok', 'grammar_ok', 'source_grounded') as $field) {
            if (!rest_sanitize_boolean($value[$field] ?? false)) {
                return new WP_Error('ca_news_failed_editorial_audit', sprintf(__('Revisione editoriale non superata: %s.', 'calcioaffari-news-engine'), $field));
            }
        }
        $issues = array_values(array_filter(array_map('sanitize_text_field', (array) ($value['issues'] ?? array()))));
        $unsupported = array_values(array_filter(array_map('sanitize_text_field', (array) ($value['unsupported_claims'] ?? array()))));
        if ($issues || $unsupported) {
            return new WP_Error('ca_news_failed_editorial_audit', __('La revisione editoriale segnala problemi o affermazioni non supportate.', 'calcioaffari-news-engine'));
        }
        $app_version = sanitize_text_field((string) ($value['app_version'] ?? ''));
        if ($app_version === '' || version_compare($app_version, '1.1.0', '<')) {
            return new WP_Error('ca_news_outdated_editorial_audit', __('La revisione è stata prodotta da una versione dell’app non supportata.', 'calcioaffari-news-engine'));
        }
        return array(
            'approved' => true,
            'single_story' => true,
            'language_ok' => true,
            'grammar_ok' => true,
            'source_grounded' => true,
            'issues' => array(),
            'unsupported_claims' => array(),
            'verifier' => sanitize_text_field((string) ($value['verifier'] ?? '')),
            'app_version' => $app_version,
        );
    }

    public static function claim_is_represented(string $claim, string $article): bool {
        $claim = self::normalise_for_comparison($claim);
        $article = self::normalise_for_comparison($article);
        return mb_strlen($claim) >= 12 && str_contains($article, $claim);
    }

    public static function validate_evidence_quotes(mixed $value, array $claim_sources, array $evidence): array|WP_Error {
        if (!is_array($value) || !$value) {
            return new WP_Error('ca_news_missing_evidence_quotes', __('Ogni affermazione deve includere estratti-prova verificabili.', 'calcioaffari-news-engine'));
        }
        $evidence_by_id = array();
        foreach ($evidence as $row) {
            $evidence_by_id[(int) ($row['id'] ?? 0)] = self::normalise_for_comparison((string) ($row['title'] ?? '') . ' ' . (string) ($row['excerpt'] ?? ''));
        }
        $validated = array();
        $quoted_sources = array();
        foreach ($value as $entry) {
            if (!is_array($entry)) {
                return new WP_Error('ca_news_invalid_evidence_quote', __('Formato dell’estratto-prova non valido.', 'calcioaffari-news-engine'));
            }
            $source_id = (int) ($entry['source_id'] ?? 0);
            $quote = sanitize_text_field((string) ($entry['quote'] ?? ''));
            $normal_quote = self::normalise_for_comparison($quote);
            if (!in_array($source_id, $claim_sources, true) || mb_strlen($normal_quote) < 12 || !isset($evidence_by_id[$source_id]) || !str_contains($evidence_by_id[$source_id], $normal_quote)) {
                return new WP_Error('ca_news_unverifiable_evidence_quote', __('Un estratto-prova non è presente nella fonte dichiarata.', 'calcioaffari-news-engine'));
            }
            $validated[] = array('source_id' => $source_id, 'quote' => $quote);
            $quoted_sources[] = $source_id;
        }
        $quoted_sources = array_values(array_unique($quoted_sources));
        sort($quoted_sources, SORT_NUMERIC);
        $required_sources = array_values(array_unique(array_map('intval', $claim_sources)));
        sort($required_sources, SORT_NUMERIC);
        if ($quoted_sources !== $required_sources) {
            return new WP_Error('ca_news_incomplete_evidence_quotes', __('Manca un estratto-prova per una delle fonti dichiarate.', 'calcioaffari-news-engine'));
        }
        return $validated;
    }

    /**
     * Keep a valid model response publishable when only its short summary is
     * outside the editorial character range. The article body is already
     * subject to the stricter word-count and source validation below.
     */
    public static function normalize_excerpt(string $excerpt, string $plain_body): string {
        $excerpt = trim((string) preg_replace('/\s+/u', ' ', $excerpt));
        $plain_body = trim((string) preg_replace('/\s+/u', ' ', $plain_body));

        if (mb_strlen($excerpt) < 45 && mb_strlen($plain_body) >= 45) {
            $excerpt = $plain_body;
        }
        if (mb_strlen($excerpt) > 320) {
            $excerpt = mb_substr($excerpt, 0, 320);
            $last_space = mb_strrpos($excerpt, ' ');
            if ($last_space !== false && $last_space >= 45) {
                $excerpt = mb_substr($excerpt, 0, $last_space);
            }
            $excerpt = rtrim($excerpt, " \t\n\r\0\x0B,;:") . '…';
        }
        return $excerpt;
    }

    /**
     * The source list is stored in dedicated metadata, so model-generated
     * inline URLs are removed without discarding the surrounding copy.
     */
    public static function sanitize_inline_urls(string $value, bool $html = false): string {
        if ($html) {
            $value = (string) preg_replace('~<a\b[^>]*>(.*?)</a>~isu', '$1', $value);
        }
        $value = (string) preg_replace('~\bhttps?://[^\s<>"\']+~iu', '', $value);
        return trim((string) preg_replace('/[ \t]{2,}/u', ' ', $value));
    }

    /**
     * Remove internal evidence identifiers that are useful to the model but
     * must never be shown to readers (for example "(ID: 5)").
     */
    public static function sanitize_internal_markers(string $value): string {
        $value = (string) preg_replace('~[\(\[]\s*(?:source[_\s-]*id|job[_\s-]*id|id)\s*[:#]?\s*\d+\s*[\)\]]~iu', '', $value);
        $value = (string) preg_replace('~\b(?:source[_\s-]*id|job[_\s-]*id)\s*[:#]\s*\d+\b~iu', '', $value);
        return trim((string) preg_replace('/[ \t]{2,}/u', ' ', $value));
    }

    /** Preserve the testata name for transparent attribution; remove domains only. */
    public static function sanitize_source_mentions(string $value, array $evidence): string {
        $needles = array();
        foreach ($evidence as $row) {
            $host = strtolower((string) parse_url((string) ($row['url'] ?? ''), PHP_URL_HOST));
            $host = preg_replace('/^www\./i', '', $host);
            if (mb_strlen((string) $host) >= 4 && str_contains((string) $host, '.')) {
                $needles[mb_strtolower((string) $host)] = (string) $host;
            }
        }

        foreach ($needles as $needle) {
            $quoted = preg_quote($needle, '~');
            $value = (string) preg_replace('~(?<![\p{L}\p{N}])(?:www\.)?' . $quoted . '(?![\p{L}\p{N}])~iu', '', $value);
        }
        return trim((string) preg_replace('/[ \t]{2,}/u', ' ', $value));
    }

    /**
     * Correct a deliberately small set of deterministic errors observed in
     * production. This is not a free-form grammar rewrite and therefore cannot
     * introduce new facts.
     */
    public static function normalize_italian_copy(string $value): string {
        $value = (string) preg_replace('/\bArseanal\b/u', 'Arsenal', $value);
        $clubs_with_elision = array('Arsenal', 'Inter', 'Atalanta', 'Udinese', 'Empoli');
        foreach ($clubs_with_elision as $club) {
            $value = (string) preg_replace('/\bdi\s+' . preg_quote($club, '/') . '\b/iu', "dell’{$club}", $value);
        }
        $masculine_clubs = array('Chelsea', 'Manchester United', 'Manchester City', 'Newcastle United', 'Liverpool', 'Real Madrid', 'Barcellona', 'PSG');
        foreach ($masculine_clubs as $club) {
            $quoted = preg_quote($club, '/');
            $value = (string) preg_replace('/\bla\s+' . $quoted . '\b/iu', "il {$club}", $value);
            $value = (string) preg_replace('/\bdi\s+' . $quoted . '\b/iu', "del {$club}", $value);
        }
        return $value;
    }

    public static function remove_redundant_leading_heading(string $body, string $title): string {
        if (!preg_match('/^\s*<h2\b[^>]*>(.*?)<\/h2>/isu', $body, $match)) {
            return $body;
        }
        $heading = self::normalise_for_comparison(wp_strip_all_tags($match[1]));
        $normal_title = self::normalise_for_comparison($title);
        if ($heading !== '' && ($heading === $normal_title || (mb_strlen($heading) >= 20 && str_contains($normal_title, $heading)))) {
            return ltrim((string) preg_replace('/^\s*<h2\b[^>]*>.*?<\/h2>\s*/isu', '', $body, 1));
        }
        return $body;
    }

    public static function has_non_italian_copy(string $title, string $plain_body): bool {
        $combined = $title . ' ' . $plain_body;
        if (CA_News_Ingestor::has_unsupported_script($combined)) {
            return true;
        }

        $normal_title = ' ' . mb_strtolower(self::normalise_for_comparison($title)) . ' ';
        foreach (array(' set to ', ' signs for ', ' deal agreed ', ' close to signing ', ' completes signing ') as $phrase) {
            if (str_contains($normal_title, $phrase)) {
                return true;
            }
        }
        $english_title_words = self::count_words_from_list($normal_title, array(
            'the', 'with', 'from', 'after', 'ahead', 'signing', 'signs', 'joins', 'join', 'agrees', 'agreement',
            'reach', 'reaches', 'complete', 'completes', 'could', 'would', 'linked', 'move', 'loan', 'target',
        ));
        if ($english_title_words >= 2) {
            return true;
        }

        $normal_body = ' ' . mb_strtolower(self::normalise_for_comparison($plain_body)) . ' ';
        $english_body_words = self::count_words_from_list($normal_body, array('the', 'and', 'with', 'from', 'that', 'this', 'after', 'have', 'has', 'will', 'their', 'his', 'her', 'for', 'into'));
        $italian_body_words = self::count_words_from_list($normal_body, array('il', 'lo', 'la', 'i', 'gli', 'le', 'di', 'del', 'della', 'che', 'con', 'per', 'una', 'un', 'ha', 'sono'));
        return $english_body_words >= 6 && $english_body_words > ($italian_body_words * 2);
    }

    private static function normalise_for_comparison(string $value): string {
        $value = mb_strtolower(remove_accents($value));
        $value = (string) preg_replace('/[^\p{L}\p{N}\s]/u', ' ', $value);
        return trim((string) preg_replace('/\s+/u', ' ', $value));
    }

    private static function count_words_from_list(string $normal_text, array $words): int {
        $count = 0;
        foreach ($words as $word) {
            if (preg_match('/\b' . preg_quote($word, '/') . '\b/u', $normal_text)) {
                $count++;
            }
        }
        return $count;
    }

    /**
     * Retained as a review signal for custom feeds. Headline-only evidence is
     * now blocked before publication and can no longer create a WordPress post.
     */
    public static function has_thin_evidence(array $evidence, array $selected_ids): bool {
        $substantive = 0;
        foreach ($evidence as $row) {
            if (!in_array((int) ($row['id'] ?? 0), $selected_ids, true)) {
                continue;
            }
            $title = trim((string) preg_replace('/\s+/u', ' ', wp_strip_all_tags((string) ($row['title'] ?? ''))));
            $excerpt = trim((string) preg_replace('/\s+/u', ' ', wp_strip_all_tags((string) ($row['excerpt'] ?? ''))));
            if ($excerpt !== '' && mb_strtolower($excerpt) !== mb_strtolower($title)) {
                $substantive += mb_strlen($excerpt);
            }
        }
        return $substantive < 240;
    }

    /**
     * Length is a review signal, never a reason to discard completed work.
     * Safety flags already force an article to pending review in automatic
     * mode, so this keeps the queue moving without weakening publication.
     */
    public static function editorial_length_warning(int $word_count, int $minimum, int $maximum): string {
        if ($word_count >= $minimum && $word_count <= $maximum) {
            return '';
        }
        return sprintf(__('Lunghezza editoriale fuori target: %d parole (obiettivo %d-%d).', 'calcioaffari-news-engine'), $word_count, $minimum, $maximum);
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
