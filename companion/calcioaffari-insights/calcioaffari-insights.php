<?php
/**
 * Plugin Name: CalcioAffari Insights
 * Plugin URI: https://calcioaffari.it
 * Description: Statistiche aggregate senza cookie, preferenze squadra e monitoraggio dell'agente editoriale locale.
 * Version: 1.0.0
 * Author: CalcioAffari
 * Text Domain: calcioaffari-insights
 * Requires at least: 6.6
 * Requires PHP: 8.1
 */

if (!defined('ABSPATH')) {
    exit;
}

final class CA_Insights {
    private const VERSION = '1.0.0';
    private const TABLE_SUFFIX = 'ca_visit_hours';
    private const PAGE_SLUG = 'calcioaffari-insights';
    private const COOKIE_PAGE_PATH = 'cookie-policy';
    private const ALERT_AFTER_MINUTES = 12;
    private const INGEST_FRESH_MINUTES = 12;

    public static function boot(): void {
        add_filter('cron_schedules', array(__CLASS__, 'cron_schedules'));
        add_action('template_redirect', array(__CLASS__, 'count_view'), 99);
        add_action('admin_menu', array(__CLASS__, 'register_admin_page'), 30);
        add_action('admin_init', array(__CLASS__, 'register_settings'));
        add_action('ca_insights_monitor_event', array(__CLASS__, 'monitor_newsroom'));
        add_action('wp_ajax_ca_save_team_preference', array(__CLASS__, 'save_team_preference'));
        add_action('init', array(__CLASS__, 'ensure_schedule'));
    }

    public static function activate(): void {
        global $wpdb;
        require_once ABSPATH . 'wp-admin/includes/upgrade.php';
        $table = self::table();
        $charset = $wpdb->get_charset_collate();
        dbDelta("CREATE TABLE {$table} (
            hour_start datetime NOT NULL,
            page_group varchar(32) NOT NULL,
            views bigint(20) unsigned NOT NULL DEFAULT 0,
            PRIMARY KEY  (hour_start,page_group),
            KEY page_group (page_group)
        ) {$charset};");
        self::ensure_cookie_page();
        self::ensure_schedule();
        update_option('ca_insights_version', self::VERSION, false);
    }

    public static function deactivate(): void {
        wp_clear_scheduled_hook('ca_insights_monitor_event');
    }

    private static function table(): string {
        global $wpdb;
        return $wpdb->prefix . self::TABLE_SUFFIX;
    }

    public static function cron_schedules(array $schedules): array {
        $schedules['ca_insights_five_minutes'] = array(
            'interval' => 5 * MINUTE_IN_SECONDS,
            'display' => 'Ogni cinque minuti (CalcioAffari)',
        );
        return $schedules;
    }

    public static function ensure_schedule(): void {
        if (!wp_next_scheduled('ca_insights_monitor_event')) {
            wp_schedule_event(time() + 120, 'ca_insights_five_minutes', 'ca_insights_monitor_event');
        }
    }

    public static function count_view(): void {
        if (is_admin() || wp_doing_ajax() || wp_doing_cron() || is_user_logged_in() || is_preview() || is_feed() || is_robots()) {
            return;
        }
        if (strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET')) !== 'GET') {
            return;
        }
        $agent = strtolower((string) ($_SERVER['HTTP_USER_AGENT'] ?? ''));
        if ($agent === '' || preg_match('/bot|crawler|spider|slurp|headless|monitor|preview|facebookexternalhit|whatsapp|telegram/i', $agent)) {
            return;
        }

        $group = 'other';
        if (is_front_page()) {
            $group = 'home';
        } elseif (is_post_type_archive('ca_affare') || is_tax(array('ca_squadra', 'ca_campionato', 'ca_tipo_affare', 'ca_stato_affare'))) {
            $group = 'market_archive';
        } elseif (is_singular('ca_affare')) {
            $group = 'market_article';
        } elseif (is_singular('post')) {
            $group = 'article';
        } elseif (is_page()) {
            $group = 'page';
        }

        global $wpdb;
        $hour = current_time('Y-m-d H:00:00');
        $table = self::table();
        $wpdb->query($wpdb->prepare(
            "INSERT INTO {$table} (hour_start,page_group,views) VALUES (%s,%s,1) ON DUPLICATE KEY UPDATE views=views+1",
            $hour,
            $group
        ));
    }

    public static function register_admin_page(): void {
        add_submenu_page(
            'calcioaffari-news-engine',
            'Statistiche e continuità',
            'Statistiche',
            'manage_options',
            self::PAGE_SLUG,
            array(__CLASS__, 'render_admin_page')
        );
    }

    public static function register_settings(): void {
        register_setting('ca_insights_settings', 'ca_insights_alert_email', array(
            'type' => 'string',
            'sanitize_callback' => 'sanitize_email',
            'default' => get_option('admin_email'),
        ));
    }

    private static function sum_between(string $start, string $end): int {
        global $wpdb;
        return (int) $wpdb->get_var($wpdb->prepare(
            'SELECT COALESCE(SUM(views),0) FROM ' . self::table() . ' WHERE hour_start >= %s AND hour_start < %s',
            $start,
            $end
        ));
    }

    private static function trend(int $current, int $previous): string {
        if ($previous <= 0) {
            return $current > 0 ? 'Nuovo traffico' : '—';
        }
        $delta = (($current - $previous) / $previous) * 100;
        return sprintf('%s%.1f%%', $delta > 0 ? '+' : '', $delta);
    }

    private static function hourly_series(int $hours): array {
        global $wpdb;
        $start = wp_date('Y-m-d H:00:00', time() - (($hours - 1) * HOUR_IN_SECONDS));
        $rows = (array) $wpdb->get_results($wpdb->prepare(
            'SELECT hour_start,SUM(views) total FROM ' . self::table() . ' WHERE hour_start >= %s GROUP BY hour_start ORDER BY hour_start ASC',
            $start
        ), ARRAY_A);
        $indexed = array_column($rows, 'total', 'hour_start');
        $series = array();
        for ($offset = $hours - 1; $offset >= 0; $offset--) {
            $key = wp_date('Y-m-d H:00:00', time() - ($offset * HOUR_IN_SECONDS));
            $series[$key] = (int) ($indexed[$key] ?? 0);
        }
        return $series;
    }

    private static function daily_series(int $days): array {
        global $wpdb;
        $start = wp_date('Y-m-d 00:00:00', time() - (($days - 1) * DAY_IN_SECONDS));
        $rows = (array) $wpdb->get_results($wpdb->prepare(
            'SELECT DATE(hour_start) day,SUM(views) total FROM ' . self::table() . ' WHERE hour_start >= %s GROUP BY DATE(hour_start) ORDER BY day ASC',
            $start
        ), ARRAY_A);
        $indexed = array_column($rows, 'total', 'day');
        $series = array();
        for ($offset = $days - 1; $offset >= 0; $offset--) {
            $key = wp_date('Y-m-d', time() - ($offset * DAY_IN_SECONDS));
            $series[$key] = (int) ($indexed[$key] ?? 0);
        }
        return $series;
    }

    private static function weekly_series(int $weeks): array {
        $timezone = wp_timezone();
        $current_monday = new DateTimeImmutable('monday this week 00:00:00', $timezone);
        $series = array();
        for ($offset = $weeks - 1; $offset >= 0; $offset--) {
            $start = $current_monday->modify('-' . $offset . ' weeks');
            $end = $start->modify('+1 week');
            $series[$start->format('Y-m-d')] = self::sum_between($start->format('Y-m-d H:i:s'), $end->format('Y-m-d H:i:s'));
        }
        return $series;
    }

    private static function render_bars(array $series, string $format): void {
        $maximum = max(1, ...array_values($series));
        echo '<div class="ca-insights-bars">';
        foreach ($series as $label => $value) {
            $height = max(3, (int) round(($value / $maximum) * 100));
            echo '<div><span style="height:' . esc_attr((string) $height) . '%"></span><b>' . esc_html((string) $value) . '</b><small>' . esc_html(wp_date($format, strtotime($label))) . '</small></div>';
        }
        echo '</div>';
    }

    private static function newsroom_status(): array {
        global $wpdb;
        $last_seen = (string) get_option('ca_news_last_agent_seen', '');
        $last_ingest = (int) get_option('ca_news_last_ingest_at', 0);
        $jobs_table = $wpdb->prefix . 'ca_news_jobs';
        $exists = $wpdb->get_var($wpdb->prepare('SHOW TABLES LIKE %s', $jobs_table)) === $jobs_table;
        $pending = $exists ? (int) $wpdb->get_var("SELECT COUNT(*) FROM {$jobs_table} WHERE status IN ('pending','leased')") : 0;
        $seen_ts = $last_seen !== '' ? strtotime($last_seen . ' ' . wp_timezone_string()) : 0;
        $agent_age = $seen_ts > 0 ? time() - $seen_ts : PHP_INT_MAX;
        $ingest_age = $last_ingest > 0 ? time() - $last_ingest : PHP_INT_MAX;
        $local_stopped = $pending > 0
            && $agent_age > self::ALERT_AFTER_MINUTES * MINUTE_IN_SECONDS
            && $ingest_age <= self::INGEST_FRESH_MINUTES * MINUTE_IN_SECONDS;
        return compact('last_seen', 'last_ingest', 'pending', 'agent_age', 'ingest_age', 'local_stopped');
    }

    public static function monitor_newsroom(): void {
        $status = self::newsroom_status();
        $open = (bool) get_option('ca_insights_local_alert_open', false);
        if (!$status['local_stopped']) {
            if ($open) {
                delete_option('ca_insights_local_alert_open');
            }
            return;
        }
        if ($open) {
            return;
        }
        $email = sanitize_email((string) get_option('ca_insights_alert_email', get_option('admin_email')));
        if (!$email) {
            return;
        }
        $subject = '[CalcioAffari] Agente locale fermo';
        $message = "WordPress continua a raccogliere le fonti, ma l'app CalcioAffari Local Newsroom non contatta il sito da oltre " . self::ALERT_AFTER_MINUTES . " minuti.\n\n"
            . 'Job in attesa: ' . (int) $status['pending'] . "\n"
            . 'Ultimo contatto agente: ' . ($status['last_seen'] ?: 'mai') . "\n\n"
            . "Controlla che il PC sia acceso e che CalcioAffari Local Newsroom sia in esecuzione. Nessun articolo è stato pubblicato automaticamente.";
        if (wp_mail($email, $subject, $message)) {
            update_option('ca_insights_local_alert_open', 1, false);
            update_option('ca_insights_last_alert_sent', current_time('mysql'), false);
        }
    }

    public static function save_team_preference(): void {
        if (!is_user_logged_in()) {
            wp_send_json_error(array('message' => 'Accesso richiesto.'), 401);
        }
        check_ajax_referer('ca_team_preference', 'nonce');
        $allowed = array('inter','juventus','milan','napoli','roma','lazio','atalanta','fiorentina','bologna','torino','genoa','cagliari','como','parma','udinese','lecce','sassuolo','monza','frosinone','venezia');
        $team = sanitize_key((string) ($_POST['team'] ?? ''));
        if (!in_array($team, $allowed, true)) {
            wp_send_json_error(array('message' => 'Squadra non valida.'), 400);
        }
        update_user_meta(get_current_user_id(), 'ca_preferred_team', $team);
        wp_send_json_success(array('team' => $team));
    }

    public static function render_admin_page(): void {
        if (!current_user_can('manage_options')) {
            return;
        }
        $today = wp_date('Y-m-d 00:00:00');
        $tomorrow = wp_date('Y-m-d 00:00:00', time() + DAY_IN_SECONDS);
        $yesterday = wp_date('Y-m-d 00:00:00', time() - DAY_IN_SECONDS);
        $seven_days = wp_date('Y-m-d 00:00:00', time() - 6 * DAY_IN_SECONDS);
        $previous_seven = wp_date('Y-m-d 00:00:00', time() - 13 * DAY_IN_SECONDS);
        $current_today = self::sum_between($today, $tomorrow);
        $previous_today = self::sum_between($yesterday, $today);
        $current_week = self::sum_between($seven_days, $tomorrow);
        $previous_week = self::sum_between($previous_seven, $seven_days);
        $status = self::newsroom_status();
        $status_label = $status['local_stopped'] ? 'Agente locale fermo' : ($status['agent_age'] <= self::ALERT_AFTER_MINUTES * MINUTE_IN_SECONDS ? 'Operativo' : 'In attesa di diagnosi');
        ?>
        <div class="wrap ca-insights-admin">
            <h1>Statistiche e continuità</h1>
            <p>Conteggi aggregati di prima parte: nessun cookie analitico, IP, user agent o identificatore personale viene conservato.</p>
            <div class="ca-insights-cards">
                <section><small>Oggi</small><strong><?php echo esc_html((string) $current_today); ?></strong><span><?php echo esc_html(self::trend($current_today, $previous_today)); ?> su ieri</span></section>
                <section><small>Ultimi 7 giorni</small><strong><?php echo esc_html((string) $current_week); ?></strong><span><?php echo esc_html(self::trend($current_week, $previous_week)); ?> sui 7 precedenti</span></section>
                <section><small>Newsroom H24</small><strong><?php echo esc_html($status_label); ?></strong><span><?php echo esc_html((string) $status['pending']); ?> job in attesa</span></section>
            </div>
            <section class="ca-insights-panel"><h2>Visite orarie · ultime 24 ore</h2><?php self::render_bars(self::hourly_series(24), 'H:i'); ?></section>
            <section class="ca-insights-panel"><h2>Visite giornaliere · ultimi 14 giorni</h2><?php self::render_bars(self::daily_series(14), 'd/m'); ?></section>
            <section class="ca-insights-panel"><h2>Visite settimanali · ultime 12 settimane</h2><?php self::render_bars(self::weekly_series(12), 'd/m'); ?></section>
            <section class="ca-insights-panel"><h2>Alert agente locale</h2>
                <p>L'email parte soltanto quando WordPress continua a raccogliere fonti, ci sono job in coda e l'app locale non contatta il sito da oltre <?php echo esc_html((string) self::ALERT_AFTER_MINUTES); ?> minuti. Problemi di hosting o raccolta fonti non generano questo alert.</p>
                <form method="post" action="options.php"><?php settings_fields('ca_insights_settings'); ?>
                    <label for="ca-insights-email"><strong>Email alert</strong></label>
                    <input id="ca-insights-email" type="email" class="regular-text" name="ca_insights_alert_email" value="<?php echo esc_attr((string) get_option('ca_insights_alert_email', get_option('admin_email'))); ?>">
                    <?php submit_button('Salva email'); ?>
                </form>
                <p><strong>Ultimo contatto:</strong> <?php echo esc_html($status['last_seen'] ?: 'mai'); ?> · <strong>Ultimo alert:</strong> <?php echo esc_html((string) get_option('ca_insights_last_alert_sent', 'nessuno')); ?></p>
            </section>
        </div>
        <style>
            .ca-insights-admin{max-width:1400px}.ca-insights-cards{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px;margin:20px 0}.ca-insights-cards section,.ca-insights-panel{background:#fff;border:1px solid #dcdcde;border-radius:12px;padding:20px}.ca-insights-cards strong{display:block;font-size:28px;margin:8px 0}.ca-insights-cards small,.ca-insights-cards span{color:#646970}.ca-insights-bars{align-items:end;display:flex;gap:6px;height:220px;overflow-x:auto;padding-top:30px}.ca-insights-bars>div{align-items:center;display:flex;flex:1 0 34px;flex-direction:column;height:100%;justify-content:end;min-width:34px}.ca-insights-bars span{background:#087443;border-radius:5px 5px 0 0;display:block;min-height:3px;width:70%}.ca-insights-bars b{font-size:11px;margin-top:4px}.ca-insights-bars small{color:#646970;font-size:10px;white-space:nowrap}@media(max-width:782px){.ca-insights-cards{grid-template-columns:1fr}}
        </style>
        <?php
    }

    private static function ensure_cookie_page(): void {
        $existing = get_page_by_path(self::COOKIE_PAGE_PATH, OBJECT, 'page');
        if ($existing instanceof WP_Post) {
            update_option('ca_cookie_policy_page_id', (int) $existing->ID, false);
            return;
        }
        $content = '<h2>Cookie e strumenti tecnici</h2>'
            . '<p>CalcioAffari.it utilizza i cookie tecnici strettamente necessari forniti da WordPress per sicurezza, autenticazione e gestione delle sessioni degli utenti registrati. Questi strumenti non richiedono consenso preventivo.</p>'
            . '<h2>Statistiche aggregate di prima parte</h2>'
            . '<p>Il sito misura le visualizzazioni in forma aggregata per ora e tipologia di pagina. Non vengono conservati indirizzi IP, user agent, identificatori univoci o cookie analitici. I dati servono esclusivamente a valutare il funzionamento e l’utilità del sito.</p>'
            . '<h2>Preferenze della squadra</h2>'
            . '<p>Per i visitatori non registrati la squadra preferita può essere salvata nel browser tramite memoria locale. Per gli utenti registrati la preferenza è associata al profilo. La preferenza può essere modificata o rimossa in qualsiasi momento.</p>'
            . '<h2>Servizi non essenziali e marketing</h2>'
            . '<p>Eventuali strumenti pubblicitari, di profilazione, social o analytics di terze parti saranno disattivati per impostazione predefinita e potranno essere attivati soltanto dopo una scelta libera e specifica dell’utente. L’iscrizione al sito non comporta automaticamente il consenso a newsletter o marketing.</p>'
            . '<h2>Gestione e contatti</h2>'
            . '<p>Per informazioni o richieste sui dati personali è disponibile la <a href="' . esc_url(home_url('/contatti/')) . '">pagina Contatti</a>. Questa informativa viene aggiornata quando cambiano gli strumenti utilizzati dal sito.</p>'
            . '<p><em>Ultimo aggiornamento: ' . esc_html(wp_date('d/m/Y')) . '.</em></p>';
        $page_id = wp_insert_post(array(
            'post_type' => 'page',
            'post_status' => 'publish',
            'post_title' => 'Cookie Policy',
            'post_name' => self::COOKIE_PAGE_PATH,
            'post_content' => $content,
        ), true);
        if (!is_wp_error($page_id)) {
            update_option('ca_cookie_policy_page_id', (int) $page_id, false);
        }
    }
}

register_activation_hook(__FILE__, array('CA_Insights', 'activate'));
register_deactivation_hook(__FILE__, array('CA_Insights', 'deactivate'));
CA_Insights::boot();
