<?php

if (!defined('ABSPATH')) {
    exit;
}

final class CA_News_Admin {
    private const PAGE = 'calcioaffari-news-engine';

    public static function register_menu(): void {
        add_menu_page(
            __('CalcioAffari IA', 'calcioaffari-news-engine'),
            __('CalcioAffari IA', 'calcioaffari-news-engine'),
            'manage_options',
            self::PAGE,
            array(__CLASS__, 'render'),
            'dashicons-rss',
            25
        );
    }

    public static function register_settings(): void {
        register_setting('ca_news_settings_group', 'ca_news_settings', array(
            'type' => 'object',
            'sanitize_callback' => array(__CLASS__, 'sanitize_settings'),
            'default' => CA_News_DB::default_settings(),
        ));
    }

    public static function register_actions(): void {
        add_action('admin_post_ca_news_run', array(__CLASS__, 'run_now'));
        add_action('admin_post_ca_news_add_source', array(__CLASS__, 'add_source'));
        add_action('admin_post_ca_news_toggle_source', array(__CLASS__, 'toggle_source'));
        add_action('admin_post_ca_news_delete_source', array(__CLASS__, 'delete_source'));
        add_action('admin_post_ca_news_retry_job', array(__CLASS__, 'retry_job'));
        add_action('admin_post_ca_news_retry_rejected_jobs', array(__CLASS__, 'retry_rejected_jobs'));
        add_action('admin_post_ca_news_generate_pairing_code', array(__CLASS__, 'generate_pairing_code'));
    }

    public static function enqueue_assets(string $hook): void {
        if ($hook !== 'toplevel_page_' . self::PAGE) {
            return;
        }
        wp_enqueue_style('ca-news-admin', CA_NEWS_URL . 'assets/admin.css', array(), CA_NEWS_VERSION);
    }

    public static function sanitize_settings($input): array {
        $defaults = CA_News_DB::default_settings();
        $input = is_array($input) ? $input : array();
        $mode = sanitize_key((string) ($input['publication_mode'] ?? $defaults['publication_mode']));
        if (!in_array($mode, array('draft', 'review', 'auto'), true)) {
            $mode = 'review';
        }
        return array(
            'publication_mode' => $mode,
            'minimum_sources' => max(1, min(5, absint($input['minimum_sources'] ?? $defaults['minimum_sources']))),
            'auto_confidence' => max(0.70, min(0.99, (float) ($input['auto_confidence'] ?? $defaults['auto_confidence']))),
            'max_posts_per_day' => max(1, min(100, absint($input['max_posts_per_day'] ?? $defaults['max_posts_per_day']))),
            'max_items_per_source' => max(1, min(30, absint($input['max_items_per_source'] ?? $defaults['max_items_per_source']))),
            'lookback_hours' => max(6, min(96, absint($input['lookback_hours'] ?? $defaults['lookback_hours']))),
            'article_min_words' => max(160, min(500, absint($input['article_min_words'] ?? $defaults['article_min_words']))),
            'article_max_words' => max(260, min(900, absint($input['article_max_words'] ?? $defaults['article_max_words']))),
            'default_author' => absint($input['default_author'] ?? $defaults['default_author']),
            'agent_lease_minutes' => max(5, min(60, absint($input['agent_lease_minutes'] ?? $defaults['agent_lease_minutes']))),
            'max_job_attempts' => max(1, min(10, absint($input['max_job_attempts'] ?? $defaults['max_job_attempts']))),
            'source_cache_minutes' => max(5, min(60, absint($input['source_cache_minutes'] ?? $defaults['source_cache_minutes']))),
            'require_primary_for_official' => empty($input['require_primary_for_official']) ? 0 : 1,
            'single_source_drafts' => empty($input['single_source_drafts']) ? 0 : 1,
            'model_name' => sanitize_text_field((string) ($input['model_name'] ?? $defaults['model_name'])),
        );
    }

    public static function render(): void {
        if (!current_user_can('manage_options')) {
            return;
        }
        global $wpdb;
        $settings = CA_News_DB::settings();
        $sources = CA_News_Sources::all();
        $jobs_table = CA_News_DB::table('jobs');
        $jobs = (array) $wpdb->get_results("SELECT * FROM {$jobs_table} ORDER BY updated_at DESC LIMIT 20", ARRAY_A);
        $counts = (array) $wpdb->get_results("SELECT status, COUNT(*) AS total FROM {$jobs_table} GROUP BY status", OBJECT_K);
        $last_agent = get_option('ca_news_last_agent_seen', 'Mai collegato');
        ?>
        <div class="wrap ca-news-admin">
            <header class="ca-news-admin__hero">
                <div><span>CALCIOAFFARI · LOCAL NEWSROOM</span><h1>Motore editoriale IA</h1><p>Fonti mondiali, sintesi locale, controllo delle prove e pubblicazione governata.</p></div>
                <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                    <?php wp_nonce_field('ca_news_run'); ?><input type="hidden" name="action" value="ca_news_run">
                    <button class="button button-primary button-hero" type="submit">Raccogli ora</button>
                </form>
            </header>

            <?php self::notice(); ?>

            <?php $pairing_code = get_transient('ca_news_pairing_code_' . get_current_user_id()); ?>
            <?php if ($pairing_code) delete_transient('ca_news_pairing_code_' . get_current_user_id()); ?>
            <section class="ca-news-panel ca-news-panel--wide">
                <h2>Collega l’applicazione locale</h2>
                <p>Genera un codice dedicato a CalcioAffari. Non serve più la password WordPress e il codice può essere sostituito in qualsiasi momento.</p>
                <?php if ($pairing_code) : ?>
                    <p><strong>Codice di collegamento — copialo ora:</strong></p>
                    <input type="text" readonly value="<?php echo esc_attr((string) $pairing_code); ?>" onclick="this.select();" style="width:100%;max-width:620px;font-family:monospace;font-size:16px">
                <?php endif; ?>
                <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                    <?php wp_nonce_field('ca_news_generate_pairing_code'); ?><input type="hidden" name="action" value="ca_news_generate_pairing_code">
                    <button class="button button-primary" type="submit"><?php echo CA_News_DB::agent_token_hash() ? 'Genera un nuovo codice' : 'Genera codice di collegamento'; ?></button>
                </form>
                <p class="description">Generandone uno nuovo, il precedente viene revocato immediatamente.</p>
            </section>

            <section class="ca-news-stats">
                <?php foreach (array('awaiting' => 'In attesa fonti', 'pending' => 'Pronte per IA', 'leased' => 'In elaborazione', 'processed' => 'Da revisionare', 'published' => 'Pubblicate', 'rejected' => 'Respinte') as $key => $label) : ?>
                    <div><strong><?php echo esc_html((string) (isset($counts[$key]) ? (int) $counts[$key]->total : 0)); ?></strong><span><?php echo esc_html($label); ?></span></div>
                <?php endforeach; ?>
                <div><strong><?php echo esc_html((string) count(array_filter($sources, static fn(array $source): bool => (bool) $source['enabled']))); ?></strong><span>Fonti attive</span></div>
                <div><strong><?php echo esc_html((string) $last_agent); ?></strong><span>Ultimo contatto agente</span></div>
            </section>

            <div class="ca-news-grid">
                <section class="ca-news-panel">
                    <h2>Regole editoriali</h2>
                    <form method="post" action="options.php">
                        <?php settings_fields('ca_news_settings_group'); ?>
                        <div class="ca-news-fields">
                            <label><span>Modalità</span><select name="ca_news_settings[publication_mode]">
                                <option value="draft" <?php selected($settings['publication_mode'], 'draft'); ?>>Bozze</option>
                                <option value="review" <?php selected($settings['publication_mode'], 'review'); ?>>Revisione editoriale</option>
                                <option value="auto" <?php selected($settings['publication_mode'], 'auto'); ?>>Pubblicazione automatica</option>
                            </select></label>
                            <label><span>Fonti indipendenti minime</span><input type="number" min="1" max="5" name="ca_news_settings[minimum_sources]" value="<?php echo esc_attr((string) $settings['minimum_sources']); ?>"></label>
                            <label><span>Soglia automatica</span><input type="number" min="0.70" max="0.99" step="0.01" name="ca_news_settings[auto_confidence]" value="<?php echo esc_attr((string) $settings['auto_confidence']); ?>"></label>
                            <label><span>Massimo articoli/giorno</span><input type="number" min="1" max="100" name="ca_news_settings[max_posts_per_day]" value="<?php echo esc_attr((string) $settings['max_posts_per_day']); ?>"></label>
                            <label><span>Elementi per fonte</span><input type="number" min="1" max="30" name="ca_news_settings[max_items_per_source]" value="<?php echo esc_attr((string) $settings['max_items_per_source']); ?>"></label>
                            <label><span>Finestra notizie (ore)</span><input type="number" min="6" max="96" name="ca_news_settings[lookback_hours]" value="<?php echo esc_attr((string) $settings['lookback_hours']); ?>"></label>
                            <label><span>Parole minime</span><input type="number" min="160" max="500" name="ca_news_settings[article_min_words]" value="<?php echo esc_attr((string) $settings['article_min_words']); ?>"></label>
                            <label><span>Parole massime</span><input type="number" min="260" max="900" name="ca_news_settings[article_max_words]" value="<?php echo esc_attr((string) $settings['article_max_words']); ?>"></label>
                            <label><span>Modello locale</span><input type="text" name="ca_news_settings[model_name]" value="<?php echo esc_attr((string) $settings['model_name']); ?>"></label>
                            <label><span>Autore WordPress (ID)</span><input type="number" min="1" name="ca_news_settings[default_author]" value="<?php echo esc_attr((string) $settings['default_author']); ?>"></label>
                            <input type="hidden" name="ca_news_settings[agent_lease_minutes]" value="<?php echo esc_attr((string) $settings['agent_lease_minutes']); ?>">
                            <input type="hidden" name="ca_news_settings[max_job_attempts]" value="<?php echo esc_attr((string) $settings['max_job_attempts']); ?>">
                            <input type="hidden" name="ca_news_settings[source_cache_minutes]" value="<?php echo esc_attr((string) $settings['source_cache_minutes']); ?>">
                            <label class="ca-news-check"><input type="checkbox" name="ca_news_settings[require_primary_for_official]" value="1" <?php checked($settings['require_primary_for_official']); ?>><span>Fonte primaria obbligatoria per “Ufficiale”</span></label>
                            <label class="ca-news-check"><input type="checkbox" name="ca_news_settings[single_source_drafts]" value="1" <?php checked($settings['single_source_drafts']); ?>><span>Ammetti singola fonte solo in bozza/revisione</span></label>
                        </div>
                        <?php submit_button('Salva regole'); ?>
                    </form>
                </section>

                <section class="ca-news-panel">
                    <h2>Aggiungi fonte RSS/Atom</h2>
                    <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>" class="ca-news-source-form">
                        <?php wp_nonce_field('ca_news_add_source'); ?><input type="hidden" name="action" value="ca_news_add_source">
                        <label><span>Nome</span><input required type="text" name="name"></label>
                        <label><span>URL feed HTTPS</span><input required type="url" name="feed_url" placeholder="https://..."></label>
                        <label><span>Lingua</span><input required type="text" name="language" value="it" maxlength="12"></label>
                        <label><span>Paese</span><input required type="text" name="country" value="IT" maxlength="12"></label>
                        <label><span>Tipo</span><select name="source_type"><option value="rss">Testata autorizzata</option><option value="aggregator">Aggregatore autorizzato</option><option value="official">Fonte primaria ufficiale</option><option value="gdelt">GDELT</option></select></label>
                        <label><span>Affidabilità</span><input type="number" name="trust_score" min="0.10" max="1" step="0.01" value="0.75"></label>
                        <input type="hidden" name="enabled" value="1">
                        <button class="button button-primary" type="submit">Aggiungi fonte</button>
                    </form>
                    <p class="description">Aggiungi soltanto feed che autorizzano questo utilizzo. Le fonti ufficiali vanno riservate a club, leghe, federazioni o comunicati primari.</p>
                </section>
            </div>

            <section class="ca-news-panel ca-news-panel--wide">
                <h2>Fonti</h2>
                <div class="ca-news-table-wrap"><table class="widefat striped"><thead><tr><th>Fonte</th><th>Lingua</th><th>Tipo</th><th>Esito</th><th>Stato</th><th></th></tr></thead><tbody>
                <?php foreach ($sources as $source) : ?>
                    <tr><td><strong><?php echo esc_html($source['name']); ?></strong><small><?php echo esc_html(wp_parse_url($source['feed_url'], PHP_URL_HOST)); ?></small></td><td><?php echo esc_html(strtoupper($source['language'])); ?></td><td><?php echo esc_html($source['source_type']); ?> · <?php echo esc_html($source['trust_score']); ?></td><td><?php echo $source['last_error'] ? '<span class="ca-bad">' . esc_html($source['last_error']) . '</span>' : esc_html($source['last_success'] ?: 'Non ancora letta'); ?></td><td><?php echo $source['enabled'] ? '<span class="ca-good">Attiva</span>' : 'Sospesa'; ?></td><td class="ca-actions">
                        <?php self::row_action('ca_news_toggle_source', (int) $source['id'], $source['enabled'] ? 'Sospendi' : 'Attiva'); ?>
                        <?php self::row_action('ca_news_delete_source', (int) $source['id'], 'Elimina', true); ?>
                    </td></tr>
                <?php endforeach; ?>
                </tbody></table></div>
            </section>

            <section class="ca-news-panel ca-news-panel--wide">
                <div style="display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap">
                    <h2>Coda editoriale recente</h2>
                    <?php if (!empty($counts['rejected']) && (int) $counts['rejected']->total > 0) : ?>
                        <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                            <?php wp_nonce_field('ca_news_retry_rejected_jobs'); ?><input type="hidden" name="action" value="ca_news_retry_rejected_jobs">
                            <button class="button button-primary" type="submit">Riprova tutte le respinte</button>
                        </form>
                    <?php endif; ?>
                </div>
                <div class="ca-news-table-wrap"><table class="widefat striped"><thead><tr><th>ID</th><th>Stato</th><th>Tentativi</th><th>Fonti</th><th>Confidenza</th><th>Articolo</th><th>Errore</th><th></th></tr></thead><tbody>
                <?php foreach ($jobs as $job) : ?>
                    <tr><td>#<?php echo esc_html((string) $job['id']); ?></td><td><?php echo esc_html($job['status']); ?></td><td><?php echo esc_html((string) ($job['attempt_count'] ?? 0)); ?> / <?php echo esc_html((string) $settings['max_job_attempts']); ?></td><td><?php echo esc_html((string) $job['source_count']); ?></td><td><?php echo $job['confidence'] !== null ? esc_html(number_format_i18n((float) $job['confidence'] * 100, 0) . '%') : '—'; ?></td><td><?php echo $job['post_id'] ? '<a href="' . esc_url(get_edit_post_link((int) $job['post_id'])) . '">#' . esc_html((string) $job['post_id']) . '</a>' : '—'; ?></td><td><?php echo esc_html((string) $job['error_message']); ?></td><td><?php if (in_array($job['status'], array('rejected', 'processed'), true)) self::row_action('ca_news_retry_job', (int) $job['id'], 'Riprova'); ?></td></tr>
                <?php endforeach; ?>
                </tbody></table></div>
            </section>
        </div>
        <?php
    }

    private static function row_action(string $action, int $id, string $label, bool $danger = false): void {
        $url = wp_nonce_url(admin_url('admin-post.php?action=' . $action . '&id=' . $id), $action . '_' . $id);
        echo '<a class="button button-small ' . ($danger ? 'ca-danger' : '') . '" href="' . esc_url($url) . '">' . esc_html($label) . '</a>';
    }

    private static function notice(): void {
        if (empty($_GET['ca_notice'])) {
            return;
        }
        $message = sanitize_text_field(wp_unslash((string) $_GET['ca_notice']));
        echo '<div class="notice notice-success is-dismissible"><p>' . esc_html($message) . '</p></div>';
    }

    private static function guard(string $nonce_action, ?int $id = null): void {
        if (!current_user_can('manage_options')) {
            wp_die(esc_html__('Permessi insufficienti.', 'calcioaffari-news-engine'));
        }
        check_admin_referer($id === null ? $nonce_action : $nonce_action . '_' . $id);
    }

    private static function redirect(string $message): void {
        wp_safe_redirect(add_query_arg(array('page' => self::PAGE, 'ca_notice' => $message), admin_url('admin.php')));
        exit;
    }

    public static function run_now(): void {
        self::guard('ca_news_run');
        $result = CA_News_Ingestor::run();
        self::redirect(sprintf('Raccolta completata: %d nuovi elementi, %d errori.', (int) $result['inserted'], (int) ($result['errors'] ?? 0)));
    }

    public static function add_source(): void {
        self::guard('ca_news_add_source');
        $result = CA_News_Sources::add(wp_unslash($_POST));
        self::redirect(is_wp_error($result) ? $result->get_error_message() : 'Fonte aggiunta.');
    }

    public static function toggle_source(): void {
        global $wpdb;
        $id = absint($_GET['id'] ?? 0);
        self::guard('ca_news_toggle_source', $id);
        $table = CA_News_DB::table('sources');
        $current = (int) $wpdb->get_var($wpdb->prepare("SELECT enabled FROM {$table} WHERE id=%d", $id));
        CA_News_Sources::set_enabled($id, !$current);
        self::redirect($current ? 'Fonte sospesa.' : 'Fonte attivata.');
    }

    public static function delete_source(): void {
        $id = absint($_GET['id'] ?? 0);
        self::guard('ca_news_delete_source', $id);
        CA_News_Sources::delete($id);
        self::redirect('Fonte eliminata.');
    }

    public static function retry_job(): void {
        global $wpdb;
        $id = absint($_GET['id'] ?? 0);
        self::guard('ca_news_retry_job', $id);
        $wpdb->update(CA_News_DB::table('jobs'), array('status' => 'pending', 'attempt_count' => 0, 'last_attempt_at' => null, 'error_message' => null, 'lease_hash' => null, 'lease_expires_at' => null, 'updated_at' => current_time('mysql', true)), array('id' => $id), array('%s', '%d', '%s', '%s', '%s', '%s', '%s'), array('%d'));
        self::redirect('Notizia rimessa in coda.');
    }

    public static function retry_rejected_jobs(): void {
        global $wpdb;
        self::guard('ca_news_retry_rejected_jobs');
        $table = CA_News_DB::table('jobs');
        $updated = $wpdb->query($wpdb->prepare(
            "UPDATE {$table} SET status='pending', attempt_count=0, last_attempt_at=NULL, error_message=NULL, result_json=NULL, confidence=NULL, lease_hash=NULL, lease_expires_at=NULL, updated_at=%s WHERE status='rejected'",
            current_time('mysql', true)
        ));
        self::redirect(sprintf('%d notizie respinte rimesse in coda.', max(0, (int) $updated)));
    }

    public static function generate_pairing_code(): void {
        self::guard('ca_news_generate_pairing_code');
        $token = wp_generate_password(48, false, false);
        $hash = hash('sha256', $token);
        if (!CA_News_DB::store_agent_token_hash($hash)) {
            wp_die(esc_html__('Il database non ha confermato il salvataggio del codice. Nessun codice è stato attivato.', 'calcioaffari-news-engine'));
        }
        set_transient('ca_news_pairing_code_' . get_current_user_id(), $token, 5 * MINUTE_IN_SECONDS);
        self::redirect('Nuovo codice generato. Copialo nell’applicazione locale.');
    }
}
