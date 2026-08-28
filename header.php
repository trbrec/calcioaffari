<?php
if (!defined('ABSPATH')) {
    exit;
}
?><!doctype html>
<html <?php language_attributes(); ?>>
<head>
    <meta charset="<?php bloginfo('charset'); ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="icon" type="image/png" sizes="48x48" href="<?php echo esc_url(get_template_directory_uri() . '/assets/images/brand/calcioaffari-favicon-48-transparent.png'); ?>">
    <link rel="icon" type="image/png" sizes="192x192" href="<?php echo esc_url(get_template_directory_uri() . '/assets/images/brand/calcioaffari-favicon-192-transparent.png'); ?>">
    <link rel="apple-touch-icon" href="<?php echo esc_url(get_template_directory_uri() . '/assets/images/brand/calcioaffari-favicon-192-transparent.png'); ?>">
    <meta name="theme-color" content="#0B2C47">
    <?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>
<?php wp_body_open(); ?>
<a class="ca-skip-link" href="#contenuto">Vai al contenuto</a>

<div class="ca-topbar">
    <div class="ca-shell ca-topbar__inner">
        <strong>CalcioAffari:</strong>
        <nav class="ca-topbar__topics" aria-label="Argomenti principali">
            <a href="<?php echo esc_url(ca_theme_archive_url('ca_affare')); ?>">Calciomercato</a>
            <a href="<?php echo esc_url(ca_theme_term_url('ca_campionato', 'serie-a')); ?>">Serie A</a>
            <a href="<?php echo esc_url(ca_theme_term_url('ca_campionato', 'champions-league')); ?>">Champions League</a>
            <a href="<?php echo esc_url(ca_theme_term_url('ca_campionato', 'premier-league')); ?>">Premier League</a>
            <a href="<?php echo esc_url(ca_theme_term_url('ca_campionato', 'mondiali')); ?>">Mondiali 2026</a>
            <a href="<?php echo esc_url(home_url('/fantamercato/')); ?>">Fantamercato</a>
        </nav>
    </div>
</div>

<header class="ca-header" id="site-header">
    <div class="ca-shell ca-header__inner">
        <a class="ca-brand" href="<?php echo esc_url(home_url('/')); ?>" aria-label="CalcioAffari — Home">
            <img class="ca-brand__symbol" src="<?php echo esc_url(get_template_directory_uri() . '/assets/images/brand/calcioaffari-business-symbol-v1.png'); ?>" alt="" width="512" height="512">
            <img class="ca-brand__wordmark" src="<?php echo esc_url(get_template_directory_uri() . '/assets/images/brand/finale/calcioaffari-wordmark-definitivo.svg'); ?>" alt="CalcioAffari — Il calciomercato in tempo reale" width="679" height="132">
        </a>

        <button class="ca-menu-toggle" type="button" aria-expanded="false" aria-controls="ca-primary-nav">
            <span></span><span></span><span></span>
            <b>Menu</b>
        </button>

        <nav class="ca-nav" id="ca-primary-nav" aria-label="Navigazione principale">
            <?php ca_theme_fallback_menu(); ?>
        </nav>

        <div class="ca-header-actions">
            <a class="ca-account-link" href="<?php echo esc_url(home_url('/account/')); ?>"><?php echo is_user_logged_in() ? 'Profilo' : 'Accedi'; ?></a>
            <button class="ca-search-toggle" type="button" aria-expanded="false" aria-controls="ca-search-panel" aria-label="Apri la ricerca">
                <svg aria-hidden="true" viewBox="0 0 24 24"><path d="m21 21-4.7-4.7m2.2-5.3a7.5 7.5 0 1 1-15 0 7.5 7.5 0 0 1 15 0Z"/></svg>
            </button>
        </div>
    </div>

    <div class="ca-search-panel" id="ca-search-panel" hidden>
        <div class="ca-shell">
            <?php get_search_form(); ?>
        </div>
    </div>
</header>

<div class="ca-ticker">
    <div class="ca-shell ca-ticker__inner">
        <strong class="ca-ticker__label"><i></i> ULTIM’ORA</strong>
        <div class="ca-ticker__items">
            <?php
            $ticker = new WP_Query(array(
                'post_type' => array('post', 'ca_affare'),
                'post_status' => 'publish',
                'posts_per_page' => 3,
                'meta_key' => 'ca_ultimora',
                'meta_value' => '1',
                'orderby' => 'date',
                'order' => 'DESC',
                'no_found_rows' => true,
            ));
            if (!$ticker->have_posts()) {
                $ticker = new WP_Query(array(
                    'post_type' => array('post', 'ca_affare'),
                    'post_status' => 'publish',
                    'posts_per_page' => 3,
                    'orderby' => 'date',
                    'order' => 'DESC',
                    'no_found_rows' => true,
                ));
            }
            if ($ticker->have_posts()) :
                while ($ticker->have_posts()) :
                    $ticker->the_post();
                    ?>
                    <a href="<?php the_permalink(); ?>"><?php the_title(); ?></a>
                    <?php
                endwhile;
            else :
                ?>
                <span>La redazione sta verificando i prossimi aggiornamenti.</span>
            <?php endif; wp_reset_postdata(); ?>
        </div>
        <a class="ca-ticker__all" href="<?php echo esc_url(ca_theme_archive_url('ca_affare')); ?>">Tutto il mercato <span>→</span></a>
    </div>
</div>

<main id="contenuto" class="ca-main">
