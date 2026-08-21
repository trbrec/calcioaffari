<?php
if (!defined('ABSPATH')) {
    exit;
}

define('CA_THEME_VERSION', '0.8.0');

add_action('after_setup_theme', function () {
    load_theme_textdomain('calcioaffari', get_template_directory() . '/languages');
    add_theme_support('title-tag');
    add_theme_support('post-thumbnails');
    add_theme_support('responsive-embeds');
    add_theme_support('editor-styles');
    add_theme_support('align-wide');
    add_theme_support('html5', array('search-form', 'comment-form', 'comment-list', 'gallery', 'caption', 'style', 'script'));
    add_theme_support('custom-logo', array('height' => 140, 'width' => 520, 'flex-height' => true, 'flex-width' => true));
    register_nav_menus(array(
        'primary' => 'Navigazione principale',
        'footer' => 'Navigazione footer',
    ));
    add_image_size('ca-card', 760, 470, true);
    add_image_size('ca-hero', 1400, 850, true);
});

add_action('wp_enqueue_scripts', function () {
    wp_enqueue_style('calcioaffari-style', get_stylesheet_uri(), array(), CA_THEME_VERSION);
    wp_enqueue_style('calcioaffari-main', get_template_directory_uri() . '/assets/css/main.css', array('calcioaffari-style'), CA_THEME_VERSION);
    wp_enqueue_script('calcioaffari-site', get_template_directory_uri() . '/assets/js/site.js', array(), CA_THEME_VERSION, true);
    wp_localize_script('calcioaffari-site', 'CalcioAffariUI', array(
        'ajaxUrl' => admin_url('admin-ajax.php'),
        'teamNonce' => is_user_logged_in() ? wp_create_nonce('ca_team_preference') : '',
        'preferredTeam' => is_user_logged_in() ? sanitize_key((string) get_user_meta(get_current_user_id(), 'ca_preferred_team', true)) : '',
    ));
});

add_action('wp_head', function () {
    $description = 'Calciomercato, trasferimenti, trattative e notizie sul calcio italiano e internazionale, con fonti riconoscibili e aggiornamenti verificati.';
    if (is_singular()) {
        $candidate = trim(wp_strip_all_tags((string) get_the_excerpt()));
        if ($candidate !== '') {
            $description = wp_html_excerpt($candidate, 155, '…');
        }
    } elseif (is_archive()) {
        $candidate = trim(wp_strip_all_tags((string) get_the_archive_description()));
        if ($candidate !== '') {
            $description = wp_html_excerpt($candidate, 155, '…');
        }
    }
    $title = wp_get_document_title();
    $image = get_template_directory_uri() . '/assets/images/brand/calcioaffari-business-symbol-v1.png';
    echo '<meta name="description" content="' . esc_attr($description) . '">' . "\n";
    echo '<meta property="og:type" content="' . esc_attr(is_singular() ? 'article' : 'website') . '">' . "\n";
    echo '<meta property="og:title" content="' . esc_attr($title) . '">' . "\n";
    echo '<meta property="og:description" content="' . esc_attr($description) . '">' . "\n";
    echo '<meta property="og:url" content="' . esc_url(is_singular() ? get_permalink() : home_url(wp_unslash((string) ($_SERVER['REQUEST_URI'] ?? '/')))) . '">' . "\n";
    echo '<meta property="og:image" content="' . esc_url($image) . '">' . "\n";
    echo '<meta name="twitter:card" content="summary_large_image">' . "\n";
}, 2);

add_filter('excerpt_length', function () {
    return 24;
}, 999);

add_filter('excerpt_more', function () {
    return '…';
});

function ca_theme_term_url($taxonomy, $slug) {
    $term = get_term_by('slug', $slug, $taxonomy);
    if ($term && !is_wp_error($term)) {
        return get_term_link($term);
    }
    return home_url('/');
}

function ca_theme_archive_url($post_type) {
    $url = get_post_type_archive_link($post_type);
    return $url ?: home_url('/');
}

function ca_theme_fallback_menu() {
    $items = array(
        array('Home', home_url('/')),
        array('Calciomercato', ca_theme_archive_url('ca_affare')),
        array('Fantamercato', home_url('/fantamercato/')),
        array('Serie A', ca_theme_term_url('ca_campionato', 'serie-a')),
        array('Serie B', ca_theme_term_url('ca_campionato', 'serie-b')),
        array('Estero', ca_theme_term_url('ca_campionato', 'premier-league')),
        array('Mondiali', ca_theme_term_url('ca_campionato', 'mondiali')),
    );
    echo '<ul class="ca-menu">';
    foreach ($items as $item) {
        echo '<li><a href="' . esc_url($item[1]) . '">' . esc_html($item[0]) . '</a></li>';
    }
    echo '</ul>';
}

function ca_theme_read_time($post_id = null) {
    $post_id = $post_id ?: get_the_ID();
    $content = wp_strip_all_tags((string) get_post_field('post_content', $post_id));
    $words = str_word_count($content);
    return max(1, (int) ceil($words / 210));
}

function ca_theme_affare_status($post_id = null) {
    $post_id = $post_id ?: get_the_ID();
    return get_post_meta($post_id, 'ca_ufficiale', true) === '1' ? 'Ufficiale' : 'Aggiornamento';
}

function ca_theme_brand_mark() {
    return '<svg class="ca-brand__svg" aria-hidden="true" viewBox="0 0 64 64" role="img">'
        . '<path class="ca-brand__shield" d="M9 7h46v28c0 12.7-9.3 19.2-23 24C18.3 54.2 9 47.7 9 35V7Z"/>'
        . '<path class="ca-brand__slash" d="M39.5 8 25 56h8.5L48 8h-8.5Z"/>'
        . '<path class="ca-brand__c" d="M27.7 21.4a12 12 0 1 0 0 21.2v-7.1a5.7 5.7 0 1 1 0-7v-7.1Z"/>'
        . '</svg>';
}

function ca_theme_serie_a_teams() {
    return array(
        'inter' => 'Inter',
        'juventus' => 'Juventus',
        'milan' => 'Milan',
        'napoli' => 'Napoli',
        'roma' => 'Roma',
        'lazio' => 'Lazio',
        'atalanta' => 'Atalanta',
        'fiorentina' => 'Fiorentina',
        'bologna' => 'Bologna',
        'torino' => 'Torino',
        'genoa' => 'Genoa',
        'cagliari' => 'Cagliari',
        'como' => 'Como',
        'parma' => 'Parma',
        'udinese' => 'Udinese',
        'lecce' => 'Lecce',
        'sassuolo' => 'Sassuolo',
        'monza' => 'Monza',
        'frosinone' => 'Frosinone',
        'venezia' => 'Venezia',
    );
}

function ca_theme_competition_data($slug) {
    $items = array(
        'serie-a' => array('Lega Serie A', 'legaseriea.it', 'Il massimo campionato italiano: partite, protagonisti, classifiche e mercato delle venti squadre.'),
        'serie-b' => array('Lega B', 'legab.it', 'Notizie, risultati, promozione e mercato del campionato cadetto.'),
        'serie-c' => array('Lega Pro', 'lega-pro.com', 'Tutti i gironi della Serie C, risultati, club e movimenti di mercato.'),
        'serie-d' => array('LND', 'seried.lnd.it', 'Il principale campionato dilettantistico nazionale, raccontato su scala italiana.'),
        'premier-league' => array('Premier League', 'premierleague.com', 'Notizie, risultati e mercato del massimo campionato inglese.'),
        'la-liga' => array('LaLiga', 'laliga.com', 'Il calcio spagnolo tra Liga, grandi club, protagonisti e mercato.'),
        'bundesliga' => array('Bundesliga', 'bundesliga.com', 'Il massimo campionato tedesco: club, partite e trasferimenti.'),
        'ligue-1' => array('Ligue 1', 'ligue1.com', 'Il calcio francese, i suoi club e tutti gli aggiornamenti di mercato.'),
        'champions-league' => array('UEFA Champions League', 'uefa.com', 'La principale competizione europea per club, dalle qualificazioni alla finale.'),
        'europa-league' => array('UEFA Europa League', 'uefa.com', 'Notizie, risultati e protagonisti della seconda competizione UEFA per club.'),
        'nazionali' => array('Nazionali', 'uefa.com', 'Qualificazioni, tornei e amichevoli delle selezioni nazionali.'),
        'mondiali' => array('FIFA World Cup 26', 'upload.wikimedia.org/wikipedia/commons/6/60/2026_FIFA_World_Cup_logo.svg', 'La Coppa del Mondo FIFA: nazionali, risultati, protagonisti e notizie dal torneo.'),
        'sud-america' => array('CONMEBOL', 'conmebol.com', 'Club, nazionali e competizioni del calcio sudamericano.'),
        'mls' => array('MLS', 'mlssoccer.com', 'Il calcio nordamericano: Major League Soccer, club e mercato.'),
        'saudi-pro-league' => array('Saudi Pro League', 'spl.com.sa', 'Notizie, protagonisti e trasferimenti del massimo campionato saudita.'),
    );
    return isset($items[$slug]) ? $items[$slug] : array('CalcioAffari', 'fifa.com', 'Ultime notizie, risultati, protagonisti e mercato della competizione.');
}

function ca_theme_news_label($post_id = null) {
    $post_id = $post_id ?: get_the_ID();
    if (get_post_type($post_id) === 'ca_affare') {
        return 'Mercato';
    }
    $terms = get_the_terms($post_id, 'ca_campionato');
    if ($terms && !is_wp_error($terms)) {
        return $terms[0]->name;
    }
    $title = strtolower(get_the_title($post_id));
    if (strpos($title, 'calciomercato') !== false || strpos($title, 'ufficiale') !== false || strpos($title, 'prestito') !== false || strpos($title, 'rinnovo') !== false) {
        return 'Calciomercato';
    }
    if (strpos($title, 'premier league') !== false) {
        return 'Premier League';
    }
    if (strpos($title, 'serie a') !== false) {
        return 'Serie A';
    }
    return 'Calcio';
}

function ca_theme_news_badge($post_id = null) {
    $post_id = $post_id ?: get_the_ID();
    $logo_domain = trim((string) get_post_meta($post_id, 'ca_logo_domain', true));
    if ($logo_domain !== '') {
        return '<img src="' . esc_url(get_template_directory_uri() . '/assets/images/brand/calcioaffari-favicon-192-transparent.png') . '" alt="CalcioAffari" width="46" height="46" loading="lazy">';
    }
    $teams = get_the_terms($post_id, 'ca_squadra');
    if ($teams && !is_wp_error($teams)) {
        $slug = sanitize_title($teams[0]->slug);
        $file = get_template_directory() . '/assets/images/clubs/' . $slug . '.png';
        if (file_exists($file)) {
            return '<img src="' . esc_url(get_template_directory_uri() . '/assets/images/clubs/' . $slug . '.png') . '" alt="' . esc_attr($teams[0]->name) . '" width="46" height="46" loading="lazy">';
        }
    }

    $competitions = get_the_terms($post_id, 'ca_campionato');
    if ($competitions && !is_wp_error($competitions)) {
        return '<img src="' . esc_url(get_template_directory_uri() . '/assets/images/brand/calcioaffari-favicon-192-transparent.png') . '" alt="' . esc_attr($competitions[0]->name) . '" width="46" height="46" loading="lazy">';
    }

    $title = strtolower(get_the_title($post_id));
    foreach (ca_theme_serie_a_teams() as $slug => $name) {
        if (strpos($title, strtolower($name)) !== false) {
            return '<img src="' . esc_url(get_template_directory_uri() . '/assets/images/clubs/' . $slug . '.png') . '" alt="' . esc_attr($name) . '" width="46" height="46" loading="lazy">';
        }
    }

    $club_domains = array(
        'chelsea' => array('Chelsea', 'chelseafc.com'),
        'brentford' => array('Brentford', 'brentfordfc.com'),
        'southampton' => array('Southampton', 'southamptonfc.com'),
        'aston villa' => array('Aston Villa', 'avfc.co.uk'),
        'manchester united' => array('Manchester United', 'manutd.com'),
        'shrewsbury' => array('Shrewsbury Town', 'shrewsburytown.com'),
    );
    foreach ($club_domains as $keyword => $club) {
        if (strpos($title, $keyword) !== false) {
            return '<img src="' . esc_url(get_template_directory_uri() . '/assets/images/brand/calcioaffari-favicon-192-transparent.png') . '" alt="' . esc_attr($club[0]) . '" width="46" height="46" loading="lazy">';
        }
    }

    if (strpos($title, 'premier league') !== false) {
        return '<img src="' . esc_url(get_template_directory_uri() . '/assets/images/brand/calcioaffari-favicon-192-transparent.png') . '" alt="Premier League" width="46" height="46" loading="lazy">';
    }

    return '<img src="' . esc_url(get_template_directory_uri() . '/assets/images/brand/calcioaffari-favicon-192-transparent.png') . '" alt="CalcioAffari" width="46" height="46" loading="lazy">';
}

function ca_theme_article_content($content) {
    $source_url = (string) get_post_meta(get_the_ID(), 'ca_fonte_url', true);
    if ($source_url !== '') {
        $content = str_replace($source_url, '', (string) $content);
    }
    $content = preg_replace(
        '/(?:<p[^>]*>)?\s*(?:<strong>)?\s*(?:fonte|fonte originale|source)\s*:.*?(?:<\/p>|$)\s*$/isu',
        '',
        (string) $content
    );
    return trim((string) preg_replace('/(?:\s|&nbsp;|:|-)+$/u', '', (string) $content));
}

function ca_theme_article_excerpt($excerpt) {
    $source_url = (string) get_post_meta(get_the_ID(), 'ca_fonte_url', true);
    if ($source_url !== '') {
        $excerpt = str_replace($source_url, '', (string) $excerpt);
    }
    return trim((string) preg_replace('/(?:\s|&nbsp;|:|-)+$/u', '', (string) $excerpt));
}

function ca_theme_article_sources($post_id = null) {
    $post_id = $post_id ?: get_the_ID();
    $sources = get_post_meta($post_id, 'ca_fonti', true);
    if (is_string($sources)) {
        $decoded = json_decode($sources, true);
        $sources = is_array($decoded) ? $decoded : array();
    }
    if (!is_array($sources)) {
        $sources = array();
    }

    if (!$sources) {
        $name = (string) get_post_meta($post_id, 'ca_fonte_nome', true);
        $url = (string) get_post_meta($post_id, 'ca_fonte_url', true);
        if ($name || $url) {
            $sources[] = array('name' => $name, 'url' => $url);
        }
    }

    $clean = array();
    $seen = array();
    foreach ($sources as $source) {
        if (!is_array($source)) {
            continue;
        }
        $url = esc_url_raw((string) ($source['url'] ?? ''));
        if (!$url || strtolower((string) wp_parse_url($url, PHP_URL_SCHEME)) !== 'https') {
            continue;
        }
        $name = sanitize_text_field((string) ($source['name'] ?? wp_parse_url($url, PHP_URL_HOST)));
        $key = strtolower($name . '|' . $url);
        if (isset($seen[$key])) {
            continue;
        }
        $seen[$key] = true;
        $clean[] = array('name' => $name, 'url' => $url);
    }
    return $clean;
}

function ca_theme_render_article_sources($post_id = null) {
    $sources = ca_theme_article_sources($post_id);
    if (!$sources) {
        return;
    }
    echo '<aside class="ca-article-sources"><span>' . esc_html(_n('Fonte consultata', 'Fonti consultate', count($sources), 'calcioaffari')) . '</span><ul>';
    foreach ($sources as $source) {
        echo '<li><a href="' . esc_url($source['url']) . '" target="_blank" rel="nofollow noopener noreferrer">' . esc_html($source['name']) . ' <b>↗</b></a></li>';
    }
    echo '</ul></aside>';
}

function ca_theme_render_ai_disclosure($post_id = null) {
    $post_id = $post_id ?: get_the_ID();
    if (!get_post_meta($post_id, 'ca_ai_generated', true) || get_post_meta($post_id, 'ca_ai_human_reviewed', true)) {
        return;
    }
    echo '<aside class="ca-ai-disclosure" data-ai-generated="true"><strong>Trasparenza editoriale</strong><span>Contenuto elaborato con IA locale e pubblicato sulla base delle fonti indicate, senza revisione editoriale umana sostanziale.</span></aside>';
}

function ca_theme_render_discovery_credit($post_id = null) {
    $post_id = $post_id ?: get_the_ID();
    if (get_post_meta($post_id, 'ca_discovery_provider', true) !== 'GDELT') {
        return;
    }
    echo '<p class="ca-data-credit">Individuazione della copertura mondiale: <a href="https://www.gdeltproject.org/" target="_blank" rel="nofollow noopener noreferrer">GDELT Project</a>.</p>';
}

add_filter('body_class', function ($classes) {
    $classes[] = 'ca-site';
    return $classes;
});
