<?php

if (!defined('ABSPATH')) {
    exit;
}

final class CA_Insights_Account {
    private const PAGE_PATH = 'account';
    private const CONSENT_VERSION = '2026-08-22';
    private const OAUTH_STATE_TTL = 10 * MINUTE_IN_SECONDS;

    public static function register(): void {
        add_shortcode('ca_account', array(__CLASS__, 'render'));
        add_action('template_redirect', array(__CLASS__, 'disable_account_cache'), 1);
        add_action('wp_enqueue_scripts', array(__CLASS__, 'enqueue_assets'));

        add_action('admin_post_nopriv_ca_account_register', array(__CLASS__, 'handle_register'));
        add_action('admin_post_nopriv_ca_account_login', array(__CLASS__, 'handle_login'));
        add_action('admin_post_nopriv_ca_account_reset', array(__CLASS__, 'handle_reset'));
        add_action('admin_post_ca_account_profile', array(__CLASS__, 'handle_profile'));
        add_action('admin_post_nopriv_ca_oauth_start', array(__CLASS__, 'handle_oauth_start'));
        add_action('admin_post_ca_oauth_start', array(__CLASS__, 'handle_oauth_start'));
        add_action('admin_post_nopriv_ca_oauth_callback', array(__CLASS__, 'handle_oauth_callback'));
        add_action('admin_post_ca_oauth_callback', array(__CLASS__, 'handle_oauth_callback'));
    }

    public static function ensure_page(): void {
        $existing = get_page_by_path(self::PAGE_PATH, OBJECT, 'page');
        if ($existing instanceof WP_Post) {
            update_option('ca_account_page_id', (int) $existing->ID, false);
            if (!has_shortcode((string) $existing->post_content, 'ca_account')) {
                wp_update_post(array('ID' => (int) $existing->ID, 'post_content' => '[ca_account]', 'post_status' => 'publish'));
            }
            return;
        }
        $page_id = wp_insert_post(array(
            'post_type' => 'page',
            'post_status' => 'publish',
            'post_title' => 'Account',
            'post_name' => self::PAGE_PATH,
            'post_content' => '[ca_account]',
        ), true);
        if (!is_wp_error($page_id)) {
            update_option('ca_account_page_id', (int) $page_id, false);
        }
    }

    public static function account_url(array $args = array()): string {
        $page_id = (int) get_option('ca_account_page_id', 0);
        $url = $page_id > 0 ? get_permalink($page_id) : home_url('/' . self::PAGE_PATH . '/');
        return $args ? add_query_arg($args, $url) : $url;
    }

    public static function disable_account_cache(): void {
        if (!is_page(self::PAGE_PATH)) {
            return;
        }
        if (!defined('DONOTCACHEPAGE')) {
            define('DONOTCACHEPAGE', true);
        }
        nocache_headers();
    }

    public static function enqueue_assets(): void {
        if (!is_page(self::PAGE_PATH)) {
            return;
        }
        wp_enqueue_style(
            'calcioaffari-account',
            plugins_url('assets/account.css', CA_INSIGHTS_FILE),
            array(),
            '1.1.1'
        );
    }

    private static function posted(string $key): string {
        return sanitize_text_field((string) wp_unslash($_POST[$key] ?? ''));
    }

    private static function redirect(string $notice, string $section = ''): void {
        $args = array('ca_notice' => sanitize_key($notice));
        if ($section !== '') {
            $args['ca_section'] = sanitize_key($section);
        }
        wp_safe_redirect(self::account_url($args));
        exit;
    }

    private static function username_for_email(string $email): string {
        $base = 'ca_' . substr(hash('sha256', strtolower($email)), 0, 18);
        $candidate = $base;
        $suffix = 1;
        while (username_exists($candidate)) {
            $candidate = $base . '_' . $suffix;
            $suffix++;
        }
        return $candidate;
    }

    private static function record_consents(int $user_id, bool $marketing): void {
        update_user_meta($user_id, 'ca_privacy_consent_at', current_time('mysql', true));
        update_user_meta($user_id, 'ca_privacy_consent_version', self::CONSENT_VERSION);
        update_user_meta($user_id, 'ca_marketing_consent', $marketing ? '1' : '0');
        update_user_meta($user_id, 'ca_marketing_consent_version', self::CONSENT_VERSION);
        if ($marketing) {
            update_user_meta($user_id, 'ca_marketing_consent_at', current_time('mysql', true));
        } else {
            delete_user_meta($user_id, 'ca_marketing_consent_at');
        }
    }

    private static function set_team(int $user_id, string $team): bool {
        $team = sanitize_key($team);
        if ($team !== '' && !array_key_exists($team, CA_Insights::allowed_teams())) {
            return false;
        }
        if ($team === '') {
            delete_user_meta($user_id, 'ca_preferred_team');
        } else {
            update_user_meta($user_id, 'ca_preferred_team', $team);
        }
        return true;
    }

    public static function handle_register(): void {
        if (is_user_logged_in()) {
            self::redirect('already_logged_in');
        }
        check_admin_referer('ca_account_register');
        if (self::posted('website') !== '') {
            self::redirect('registration_ok');
        }

        $email = sanitize_email(self::posted('email'));
        $password = (string) wp_unslash($_POST['password'] ?? '');
        $confirm = (string) wp_unslash($_POST['password_confirm'] ?? '');
        $terms = !empty($_POST['privacy_consent']);
        $marketing = !empty($_POST['marketing_consent']);
        $team = self::posted('team');
        if (!is_email($email) || strlen($password) < 12 || $password !== $confirm || !$terms || !$email) {
            self::redirect('registration_invalid', 'register');
        }
        if (email_exists($email)) {
            self::redirect('email_exists', 'login');
        }
        if ($team !== '' && !array_key_exists($team, CA_Insights::allowed_teams())) {
            self::redirect('team_invalid', 'register');
        }

        $user_id = wp_create_user(self::username_for_email($email), $password, $email);
        if (is_wp_error($user_id)) {
            self::redirect('registration_failed', 'register');
        }
        wp_update_user(array('ID' => (int) $user_id, 'display_name' => 'Tifoso CalcioAffari', 'role' => 'subscriber'));
        self::record_consents((int) $user_id, $marketing);
        self::set_team((int) $user_id, $team);
        wp_set_current_user((int) $user_id);
        wp_set_auth_cookie((int) $user_id, true, is_ssl());
        wp_new_user_notification((int) $user_id, null, 'user');
        self::redirect('registration_ok');
    }

    public static function handle_login(): void {
        if (is_user_logged_in()) {
            self::redirect('already_logged_in');
        }
        check_admin_referer('ca_account_login');
        $identifier = self::posted('identifier');
        $password = (string) wp_unslash($_POST['password'] ?? '');
        if ($identifier === '' || $password === '') {
            self::redirect('login_failed', 'login');
        }
        $user = wp_signon(array(
            'user_login' => $identifier,
            'user_password' => $password,
            'remember' => !empty($_POST['remember']),
        ), is_ssl());
        if (is_wp_error($user)) {
            self::redirect('login_failed', 'login');
        }
        self::redirect('login_ok');
    }

    public static function handle_reset(): void {
        check_admin_referer('ca_account_reset');
        $identifier = self::posted('identifier');
        if ($identifier !== '') {
            retrieve_password($identifier);
        }
        self::redirect('reset_sent', 'reset');
    }

    public static function handle_profile(): void {
        if (!is_user_logged_in()) {
            auth_redirect();
        }
        check_admin_referer('ca_account_profile');
        $user_id = get_current_user_id();
        if (!self::set_team($user_id, self::posted('team'))) {
            self::redirect('team_invalid');
        }
        self::record_consents($user_id, !empty($_POST['marketing_consent']));
        self::redirect('profile_saved');
    }

    public static function provider_config(string $provider): array {
        if ($provider === 'google') {
            return array(
                'client_id' => defined('CA_GOOGLE_OAUTH_CLIENT_ID') ? trim((string) CA_GOOGLE_OAUTH_CLIENT_ID) : '',
                'client_secret' => defined('CA_GOOGLE_OAUTH_CLIENT_SECRET') ? trim((string) CA_GOOGLE_OAUTH_CLIENT_SECRET) : '',
            );
        }
        if ($provider === 'facebook') {
            return array(
                'client_id' => defined('CA_FACEBOOK_APP_ID') ? trim((string) CA_FACEBOOK_APP_ID) : '',
                'client_secret' => defined('CA_FACEBOOK_APP_SECRET') ? trim((string) CA_FACEBOOK_APP_SECRET) : '',
            );
        }
        return array('client_id' => '', 'client_secret' => '');
    }

    public static function provider_ready(string $provider): bool {
        $config = self::provider_config($provider);
        return $config['client_id'] !== '' && $config['client_secret'] !== '';
    }

    public static function oauth_callback_url(string $provider): string {
        return add_query_arg(array('action' => 'ca_oauth_callback', 'provider' => $provider), admin_url('admin-post.php'));
    }

    public static function handle_oauth_start(): void {
        check_admin_referer('ca_oauth_start');
        $provider = sanitize_key((string) wp_unslash($_POST['provider'] ?? ''));
        if (!in_array($provider, array('google', 'facebook'), true) || !self::provider_ready($provider)) {
            self::redirect('oauth_unavailable');
        }
        if (empty($_POST['privacy_consent'])) {
            self::redirect('privacy_required', 'social');
        }

        $state = wp_generate_password(48, false, false);
        $nonce = wp_generate_password(32, false, false);
        set_transient('ca_oauth_state_' . hash('sha256', $state), array(
            'provider' => $provider,
            'nonce' => $nonce,
            'marketing' => !empty($_POST['marketing_consent']),
        ), self::OAUTH_STATE_TTL);

        $config = self::provider_config($provider);
        $redirect_uri = self::oauth_callback_url($provider);
        if ($provider === 'google') {
            $url = add_query_arg(array(
                'client_id' => $config['client_id'],
                'redirect_uri' => $redirect_uri,
                'response_type' => 'code',
                'scope' => 'openid email',
                'state' => $state,
                'nonce' => $nonce,
                'prompt' => 'select_account',
            ), 'https://accounts.google.com/o/oauth2/v2/auth');
        } else {
            $url = add_query_arg(array(
                'client_id' => $config['client_id'],
                'redirect_uri' => $redirect_uri,
                'response_type' => 'code',
                'scope' => 'email',
                'state' => $state,
            ), 'https://www.facebook.com/dialog/oauth');
        }
        wp_redirect(esc_url_raw($url), 302, 'CalcioAffari');
        exit;
    }

    private static function remote_json(string $url, array $args): array|WP_Error {
        $response = wp_remote_request($url, $args);
        if (is_wp_error($response)) {
            return $response;
        }
        $status = wp_remote_retrieve_response_code($response);
        $data = json_decode(wp_remote_retrieve_body($response), true);
        if ($status < 200 || $status >= 300 || !is_array($data)) {
            return new WP_Error('ca_oauth_remote_error', 'Il provider non ha restituito una risposta valida.');
        }
        return $data;
    }

    private static function oauth_identity(string $provider, string $code): array|WP_Error {
        $config = self::provider_config($provider);
        $redirect_uri = self::oauth_callback_url($provider);
        if ($provider === 'google') {
            $token = self::remote_json('https://oauth2.googleapis.com/token', array(
                'method' => 'POST',
                'timeout' => 20,
                'body' => array(
                    'code' => $code,
                    'client_id' => $config['client_id'],
                    'client_secret' => $config['client_secret'],
                    'redirect_uri' => $redirect_uri,
                    'grant_type' => 'authorization_code',
                ),
            ));
            if (is_wp_error($token) || empty($token['access_token'])) {
                return new WP_Error('ca_oauth_token_error', 'Accesso Google non completato.');
            }
            $identity = self::remote_json('https://openidconnect.googleapis.com/v1/userinfo', array(
                'method' => 'GET',
                'timeout' => 20,
                'headers' => array('Authorization' => 'Bearer ' . $token['access_token']),
            ));
            if (is_wp_error($identity) || empty($identity['sub']) || empty($identity['email']) || empty($identity['email_verified'])) {
                return new WP_Error('ca_oauth_identity_error', 'Google non ha fornito un indirizzo email verificato.');
            }
            return array('subject' => sanitize_text_field((string) $identity['sub']), 'email' => sanitize_email((string) $identity['email']));
        }

        $token = self::remote_json('https://graph.facebook.com/oauth/access_token', array(
            'method' => 'POST',
            'timeout' => 20,
            'body' => array(
                'code' => $code,
                'client_id' => $config['client_id'],
                'client_secret' => $config['client_secret'],
                'redirect_uri' => $redirect_uri,
            ),
        ));
        if (is_wp_error($token) || empty($token['access_token'])) {
            return new WP_Error('ca_oauth_token_error', 'Accesso Facebook non completato.');
        }
        $identity = self::remote_json('https://graph.facebook.com/me?fields=id,email', array(
            'method' => 'GET',
            'timeout' => 20,
            'headers' => array('Authorization' => 'Bearer ' . $token['access_token']),
        ));
        if (is_wp_error($identity) || empty($identity['id']) || empty($identity['email'])) {
            return new WP_Error('ca_oauth_identity_error', 'Facebook non ha fornito l’indirizzo email necessario.');
        }
        return array('subject' => sanitize_text_field((string) $identity['id']), 'email' => sanitize_email((string) $identity['email']));
    }

    private static function find_or_create_oauth_user(string $provider, array $identity, bool $marketing): int|WP_Error {
        $meta_key = $provider === 'google' ? 'ca_google_subject' : 'ca_facebook_subject';
        $matches = get_users(array('number' => 1, 'fields' => 'ids', 'meta_key' => $meta_key, 'meta_value' => $identity['subject']));
        if ($matches) {
            $user_id = (int) $matches[0];
            self::record_consents($user_id, $marketing);
            return $user_id;
        }
        $existing = get_user_by('email', $identity['email']);
        if ($existing instanceof WP_User) {
            update_user_meta((int) $existing->ID, $meta_key, $identity['subject']);
            self::record_consents((int) $existing->ID, $marketing);
            return (int) $existing->ID;
        }
        $user_id = wp_create_user(self::username_for_email($identity['email']), wp_generate_password(32, true, true), $identity['email']);
        if (is_wp_error($user_id)) {
            return $user_id;
        }
        wp_update_user(array('ID' => (int) $user_id, 'display_name' => 'Tifoso CalcioAffari', 'role' => 'subscriber'));
        update_user_meta((int) $user_id, $meta_key, $identity['subject']);
        self::record_consents((int) $user_id, $marketing);
        wp_new_user_notification((int) $user_id, null, 'user');
        return (int) $user_id;
    }

    public static function handle_oauth_callback(): void {
        $provider = sanitize_key((string) wp_unslash($_GET['provider'] ?? ''));
        $state = sanitize_text_field((string) wp_unslash($_GET['state'] ?? ''));
        $code = sanitize_text_field((string) wp_unslash($_GET['code'] ?? ''));
        if (!in_array($provider, array('google', 'facebook'), true) || $state === '' || $code === '') {
            self::redirect('oauth_failed');
        }
        $key = 'ca_oauth_state_' . hash('sha256', $state);
        $session = get_transient($key);
        delete_transient($key);
        if (!is_array($session) || !hash_equals((string) ($session['provider'] ?? ''), $provider)) {
            self::redirect('oauth_expired');
        }
        $identity = self::oauth_identity($provider, $code);
        if (is_wp_error($identity) || !is_email((string) ($identity['email'] ?? ''))) {
            self::redirect('oauth_failed');
        }
        $user_id = self::find_or_create_oauth_user($provider, $identity, !empty($session['marketing']));
        if (is_wp_error($user_id)) {
            self::redirect('oauth_failed');
        }
        wp_set_current_user((int) $user_id);
        wp_set_auth_cookie((int) $user_id, true, is_ssl());
        self::redirect('login_ok');
    }

    private static function notice(): string {
        $code = sanitize_key((string) wp_unslash($_GET['ca_notice'] ?? ''));
        $messages = array(
            'registration_ok' => 'Account creato: accesso effettuato.',
            'registration_invalid' => 'Controlla email, password di almeno 12 caratteri, conferma password e accettazione della Privacy Policy.',
            'registration_failed' => 'Registrazione non completata. Riprova.',
            'email_exists' => 'Questa email è già registrata: accedi o recupera la password.',
            'login_ok' => 'Accesso effettuato.',
            'login_failed' => 'Email o password non corrette.',
            'reset_sent' => 'Se l’account esiste, riceverai un’email per impostare una nuova password.',
            'profile_saved' => 'Preferenze aggiornate.',
            'team_invalid' => 'Squadra non valida.',
            'privacy_required' => 'Per creare l’account devi accettare Privacy Policy e condizioni del servizio.',
            'oauth_unavailable' => 'Questo metodo di accesso non è ancora configurato.',
            'oauth_expired' => 'La richiesta di accesso è scaduta. Riprova.',
            'oauth_failed' => 'Accesso social non completato. Puoi riprovare o usare email e password.',
            'already_logged_in' => 'Sei già autenticato.',
        );
        return $messages[$code] ?? '';
    }

    private static function team_options(string $selected): string {
        $html = '<option value="">Nessuna preferenza</option>';
        foreach (CA_Insights::allowed_teams() as $slug => $name) {
            $html .= '<option value="' . esc_attr($slug) . '"' . selected($selected, $slug, false) . '>' . esc_html($name) . '</option>';
        }
        return $html;
    }

    private static function privacy_label(): string {
        $privacy = get_privacy_policy_url() ?: home_url('/privacy-policy/');
        $cookie = home_url('/cookie-policy/');
        return 'Accetto la <a href="' . esc_url($privacy) . '" target="_blank" rel="noopener">Privacy Policy</a> e la <a href="' . esc_url($cookie) . '" target="_blank" rel="noopener">Cookie Policy</a> per creare e usare l’account.';
    }

    private static function social_form(string $provider, string $label): string {
        if (!self::provider_ready($provider)) {
            return '';
        }
        ob_start();
        ?>
        <form class="ca-social-login" method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
            <input type="hidden" name="action" value="ca_oauth_start">
            <input type="hidden" name="provider" value="<?php echo esc_attr($provider); ?>">
            <?php wp_nonce_field('ca_oauth_start'); ?>
            <label class="ca-account-check"><input type="checkbox" name="privacy_consent" value="1" required> <span><?php echo wp_kses_post(self::privacy_label()); ?></span></label>
            <label class="ca-account-check"><input type="checkbox" name="marketing_consent" value="1"> <span>Desidero ricevere via email notizie e aggiornamenti di CalcioAffari (facoltativo).</span></label>
            <button class="ca-account-social ca-account-social--<?php echo esc_attr($provider); ?>" type="submit">Continua con <?php echo esc_html($label); ?></button>
        </form>
        <?php
        return (string) ob_get_clean();
    }

    public static function render(): string {
        $notice = self::notice();
        ob_start();
        ?>
        <div class="ca-account">
            <?php if ($notice !== '') : ?><div class="ca-account-notice" role="status"><?php echo esc_html($notice); ?></div><?php endif; ?>
            <?php if (is_user_logged_in()) : $user = wp_get_current_user(); $team = sanitize_key((string) get_user_meta($user->ID, 'ca_preferred_team', true)); ?>
                <section class="ca-account-card ca-account-card--profile">
                    <span class="ca-account-eyebrow">Il tuo profilo</span>
                    <h2>Preferenze personali</h2>
                    <p>Account collegato a <strong><?php echo esc_html($user->user_email); ?></strong>. Conserviamo soltanto i dati necessari al servizio.</p>
                    <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                        <input type="hidden" name="action" value="ca_account_profile">
                        <?php wp_nonce_field('ca_account_profile'); ?>
                        <label>Squadra preferita<select name="team"><?php echo wp_kses(self::team_options($team), array('option' => array('value' => true, 'selected' => true))); ?></select></label>
                        <label class="ca-account-check"><input type="checkbox" name="marketing_consent" value="1" <?php checked(get_user_meta($user->ID, 'ca_marketing_consent', true), '1'); ?>> <span>Desidero ricevere via email notizie e aggiornamenti di CalcioAffari. Posso revocare il consenso in qualsiasi momento.</span></label>
                        <button type="submit">Salva preferenze</button>
                    </form>
                    <a class="ca-account-logout" href="<?php echo esc_url(wp_logout_url(self::account_url())); ?>">Esci dall’account</a>
                </section>
            <?php else : ?>
                <div class="ca-account-grid">
                    <section class="ca-account-card" id="accedi">
                        <span class="ca-account-eyebrow">Bentornato</span><h2>Accedi</h2>
                        <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                            <input type="hidden" name="action" value="ca_account_login"><?php wp_nonce_field('ca_account_login'); ?>
                            <label>Email<input type="email" name="identifier" autocomplete="email" required></label>
                            <label>Password<input type="password" name="password" autocomplete="current-password" required></label>
                            <label class="ca-account-check"><input type="checkbox" name="remember" value="1"> <span>Resta connesso</span></label>
                            <button type="submit">Accedi</button>
                        </form>
                    </section>
                    <section class="ca-account-card" id="registrati">
                        <span class="ca-account-eyebrow">Un solo dato essenziale</span><h2>Crea l’account</h2>
                        <p>Email, password e squadra preferita. Nessun profilo invasivo.</p>
                        <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>">
                            <input type="hidden" name="action" value="ca_account_register"><?php wp_nonce_field('ca_account_register'); ?>
                            <label class="ca-account-honeypot" aria-hidden="true">Sito web<input type="text" name="website" tabindex="-1" autocomplete="off"></label>
                            <label>Email<input type="email" name="email" autocomplete="email" required></label>
                            <label>Password <small>almeno 12 caratteri</small><input type="password" name="password" minlength="12" autocomplete="new-password" required></label>
                            <label>Conferma password<input type="password" name="password_confirm" minlength="12" autocomplete="new-password" required></label>
                            <label>Squadra preferita<select name="team"><?php echo wp_kses(self::team_options(''), array('option' => array('value' => true, 'selected' => true))); ?></select></label>
                            <label class="ca-account-check"><input type="checkbox" name="privacy_consent" value="1" required> <span><?php echo wp_kses_post(self::privacy_label()); ?></span></label>
                            <label class="ca-account-check"><input type="checkbox" name="marketing_consent" value="1"> <span>Desidero ricevere via email notizie e aggiornamenti di CalcioAffari (facoltativo).</span></label>
                            <button type="submit">Crea account</button>
                        </form>
                    </section>
                </div>
                <?php $google = self::social_form('google', 'Google'); $facebook = self::social_form('facebook', 'Facebook'); if ($google || $facebook) : ?>
                    <section class="ca-account-card ca-account-card--social" id="social"><span class="ca-account-eyebrow">Accesso rapido</span><h2>Usa un account esistente</h2><?php echo $google . $facebook; // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?></section>
                <?php endif; ?>
                <section class="ca-account-card ca-account-card--reset" id="recupera-password">
                    <h2>Password dimenticata?</h2><p>Inserisci l’email: riceverai il collegamento sicuro di WordPress.</p>
                    <form method="post" action="<?php echo esc_url(admin_url('admin-post.php')); ?>"><input type="hidden" name="action" value="ca_account_reset"><?php wp_nonce_field('ca_account_reset'); ?><label>Email<input type="email" name="identifier" autocomplete="email" required></label><button type="submit">Invia collegamento</button></form>
                </section>
            <?php endif; ?>
        </div>
        <?php
        return (string) ob_get_clean();
    }

    public static function render_admin_status(): void {
        ?>
        <section class="ca-insights-panel"><h2>Accesso utenti e social login</h2>
            <p><strong>Account email/password:</strong> operativo · <strong>Google:</strong> <?php echo self::provider_ready('google') ? 'configurato' : 'in attesa delle credenziali'; ?> · <strong>Facebook:</strong> <?php echo self::provider_ready('facebook') ? 'configurato' : 'in attesa delle credenziali'; ?></p>
            <p>URI callback Google: <code><?php echo esc_html(self::oauth_callback_url('google')); ?></code><br>URI callback Facebook: <code><?php echo esc_html(self::oauth_callback_url('facebook')); ?></code></p>
            <p>I segreti devono essere definiti in <code>wp-config.php</code> tramite <code>CA_GOOGLE_OAUTH_CLIENT_ID</code>, <code>CA_GOOGLE_OAUTH_CLIENT_SECRET</code>, <code>CA_FACEBOOK_APP_ID</code> e <code>CA_FACEBOOK_APP_SECRET</code>. Non vengono salvati nel tema o nel repository.</p>
        </section>
        <?php
    }
}
