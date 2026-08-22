<?php
if (!defined('ABSPATH')) {
    exit;
}
?>
</main>

<aside class="ca-ad-slot ca-ad-slot--footer" aria-label="Spazio pubblicitario">
    <span>Pubblicità</span>
    <strong>Spazio premium 970 × 250</strong>
</aside>

<footer class="ca-footer">
    <div class="ca-shell ca-footer__top">
        <div class="ca-footer__brand">
            <a class="ca-brand ca-brand--footer" href="<?php echo esc_url(home_url('/')); ?>">
                <img class="ca-footer__symbol" src="<?php echo esc_url(get_template_directory_uri() . '/assets/images/brand/calcioaffari-business-symbol-v1.png'); ?>" alt="CalcioAffari" width="150" height="150">
            </a>
            <p>Notizie, risultati, competizioni e mercato: tutto il calcio italiano e mondiale, con fonti riconoscibili.</p>
        </div>
        <div>
            <h2>Italia</h2>
            <ul>
                <li><a href="<?php echo esc_url(ca_theme_term_url('ca_campionato', 'serie-a')); ?>">Serie A</a></li>
                <li><a href="<?php echo esc_url(ca_theme_term_url('ca_campionato', 'serie-b')); ?>">Serie B</a></li>
                <li><a href="<?php echo esc_url(ca_theme_term_url('ca_campionato', 'serie-c')); ?>">Serie C</a></li>
                <li><a href="<?php echo esc_url(ca_theme_term_url('ca_campionato', 'serie-d')); ?>">Serie D</a></li>
            </ul>
        </div>
        <div>
            <h2>Calcio mondiale</h2>
            <ul>
                <li><a href="<?php echo esc_url(ca_theme_term_url('ca_campionato', 'champions-league')); ?>">Champions League</a></li>
                <li><a href="<?php echo esc_url(ca_theme_term_url('ca_campionato', 'premier-league')); ?>">Premier League</a></li>
                <li><a href="<?php echo esc_url(ca_theme_term_url('ca_campionato', 'la-liga')); ?>">La Liga</a></li>
                <li><a href="<?php echo esc_url(ca_theme_term_url('ca_campionato', 'mondiali')); ?>">Mondiali</a></li>
            </ul>
        </div>
        <div>
            <h2>CalcioAffari</h2>
            <ul>
                <li><a href="<?php echo esc_url(home_url('/chi-siamo/')); ?>">Chi siamo</a></li>
                <li><a href="<?php echo esc_url(home_url('/metodo-e-fonti/')); ?>">Metodo e fonti</a></li>
                <li><a href="<?php echo esc_url(home_url('/contatti/')); ?>">Contatti</a></li>
                <li><a href="<?php echo esc_url(home_url('/account/')); ?>">Account</a></li>
                <li><a href="<?php echo esc_url(get_privacy_policy_url() ?: home_url('/privacy-policy/')); ?>">Privacy</a></li>
                <li><a href="<?php echo esc_url(home_url('/cookie-policy/')); ?>">Cookie Policy</a></li>
            </ul>
        </div>
    </div>
    <div class="ca-shell ca-footer__bottom">
        <span>© <?php echo esc_html(wp_date('Y')); ?> CalcioAffari.it</span>
        <span>Indipendente dalle società e dalle leghe citate.</span>
    </div>
</footer>

<?php wp_footer(); ?>
</body>
</html>
