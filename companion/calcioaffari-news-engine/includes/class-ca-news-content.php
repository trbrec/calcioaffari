<?php

if (!defined('ABSPATH')) {
    exit;
}

final class CA_News_Content {
    private static bool $hooks_registered = false;

    public static function register(): void {
        if (!post_type_exists('ca_affare')) {
            register_post_type('ca_affare', array(
                'labels' => array(
                    'name' => __('Calciomercato', 'calcioaffari-news-engine'),
                    'singular_name' => __('Affare', 'calcioaffari-news-engine'),
                    'add_new_item' => __('Aggiungi operazione', 'calcioaffari-news-engine'),
                    'edit_item' => __('Modifica operazione', 'calcioaffari-news-engine'),
                ),
                'public' => true,
                'show_in_rest' => true,
                'has_archive' => 'calciomercato',
                'rewrite' => array('slug' => 'calciomercato'),
                'menu_icon' => 'dashicons-randomize',
                'supports' => array('title', 'editor', 'excerpt', 'author', 'thumbnail', 'revisions'),
            ));
        }

        self::register_taxonomy('ca_squadra', __('Squadre', 'calcioaffari-news-engine'), array('post', 'ca_affare'));
        self::register_taxonomy('ca_campionato', __('Campionati', 'calcioaffari-news-engine'), array('post', 'ca_affare'));
        self::register_taxonomy('ca_stato_affare', __('Stato affare', 'calcioaffari-news-engine'), array('ca_affare'));

        foreach (self::meta_schema() as $key => $schema) {
            register_post_meta('', $key, array_merge(array(
                'single' => true,
                'show_in_rest' => true,
                'auth_callback' => static fn(): bool => current_user_can('edit_posts'),
            ), $schema));
        }

        if (!self::$hooks_registered) {
            add_action('add_meta_boxes', array(__CLASS__, 'add_review_box'));
            add_action('save_post', array(__CLASS__, 'save_review_box'));
            self::$hooks_registered = true;
        }
    }

    private static function register_taxonomy(string $taxonomy, string $label, array $object_types): void {
        if (taxonomy_exists($taxonomy)) {
            return;
        }
        register_taxonomy($taxonomy, $object_types, array(
            'label' => $label,
            'public' => true,
            'show_in_rest' => true,
            'hierarchical' => true,
            'rewrite' => array('slug' => str_replace('ca_', '', $taxonomy)),
        ));
    }

    private static function meta_schema(): array {
        $text = array('type' => 'string', 'sanitize_callback' => 'sanitize_text_field');
        return array(
            'ca_fonte_nome' => $text,
            'ca_fonte_url' => array('type' => 'string', 'sanitize_callback' => 'esc_url_raw'),
            'ca_fonti' => array(
                'type' => 'array',
                'sanitize_callback' => array(__CLASS__, 'sanitize_sources'),
                'show_in_rest' => array('schema' => array(
                    'type' => 'array',
                    'items' => array(
                        'type' => 'object',
                        'properties' => array(
                            'name' => array('type' => 'string'),
                            'url' => array('type' => 'string', 'format' => 'uri'),
                            'published_at' => array('type' => 'string'),
                        ),
                    ),
                )),
            ),
            'ca_ai_generated' => array('type' => 'boolean', 'sanitize_callback' => 'rest_sanitize_boolean'),
            'ca_ai_human_reviewed' => array('type' => 'boolean', 'sanitize_callback' => 'rest_sanitize_boolean'),
            'ca_ai_quarantined' => array('type' => 'boolean', 'sanitize_callback' => 'rest_sanitize_boolean'),
            'ca_ai_quarantine_reason' => $text,
            'ca_ai_model' => $text,
            'ca_ai_confidence' => array('type' => 'number', 'sanitize_callback' => array(__CLASS__, 'sanitize_confidence')),
            'ca_ai_job_id' => array('type' => 'integer', 'sanitize_callback' => 'absint'),
            'ca_ai_cluster_key' => $text,
            'ca_discovery_provider' => $text,
            'ca_ufficiale' => $text,
            'ca_giocatore' => $text,
            'ca_club_partenza' => $text,
            'ca_club_arrivo' => $text,
            'ca_formula' => $text,
            'ca_costo' => $text,
            'ca_scadenza_contratto' => $text,
            'ca_data_ufficialita' => $text,
            'ca_logo_domain' => $text,
        );
    }

    public static function sanitize_sources($sources): array {
        if (!is_array($sources)) {
            return array();
        }
        $clean = array();
        foreach (array_slice($sources, 0, 12) as $source) {
            if (!is_array($source)) {
                continue;
            }
            $url = isset($source['url']) ? esc_url_raw((string) $source['url']) : '';
            if (!$url) {
                continue;
            }
            $clean[] = array(
                'name' => sanitize_text_field((string) ($source['name'] ?? wp_parse_url($url, PHP_URL_HOST))),
                'url' => $url,
                'published_at' => sanitize_text_field((string) ($source['published_at'] ?? '')),
            );
        }
        return $clean;
    }

    public static function sanitize_confidence($value): float {
        return max(0.0, min(1.0, (float) $value));
    }

    public static function add_review_box(): void {
        foreach (array('post', 'ca_affare') as $post_type) {
            add_meta_box(
                'ca-news-editorial-review',
                __('Revisione editoriale IA', 'calcioaffari-news-engine'),
                array(__CLASS__, 'render_review_box'),
                $post_type,
                'side',
                'high'
            );
        }
    }

    public static function render_review_box(WP_Post $post): void {
        if (!get_post_meta($post->ID, 'ca_ai_generated', true)) {
            echo '<p>' . esc_html__('Questo contenuto non risulta prodotto dal motore IA.', 'calcioaffari-news-engine') . '</p>';
            return;
        }
        wp_nonce_field('ca_news_editorial_review_' . $post->ID, 'ca_news_editorial_review_nonce');
        $reviewed = (bool) get_post_meta($post->ID, 'ca_ai_human_reviewed', true);
        $warnings = array_values(array_filter((array) get_post_meta($post->ID, 'ca_ai_safety_flags', true)));
        if ($warnings) {
            echo '<div class="notice notice-warning inline"><p><strong>' . esc_html__('Controlli richiesti', 'calcioaffari-news-engine') . '</strong></p><ul>';
            foreach ($warnings as $warning) {
                echo '<li>' . esc_html((string) $warning) . '</li>';
            }
            echo '</ul></div>';
        }
        echo '<label><input type="checkbox" name="ca_ai_human_reviewed" value="1" ' . checked($reviewed, true, false) . '> <strong>' . esc_html__('Revisione sostanziale completata', 'calcioaffari-news-engine') . '</strong></label>';
        echo '<p class="description">' . esc_html__('Conferma solo dopo controllo dei fatti, delle fonti e della sostanza del testo, assumendone la responsabilità editoriale.', 'calcioaffari-news-engine') . '</p>';
    }

    public static function save_review_box(int $post_id): void {
        if (wp_is_post_autosave($post_id) || wp_is_post_revision($post_id) || !current_user_can('edit_post', $post_id)) {
            return;
        }
        if (!isset($_POST['ca_news_editorial_review_nonce']) || !wp_verify_nonce(sanitize_text_field(wp_unslash($_POST['ca_news_editorial_review_nonce'])), 'ca_news_editorial_review_' . $post_id)) {
            return;
        }
        update_post_meta($post_id, 'ca_ai_human_reviewed', empty($_POST['ca_ai_human_reviewed']) ? 0 : 1);
    }
}
