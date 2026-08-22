<?php
get_header();

$official_count_query = new WP_Query(array(
    'post_type' => 'ca_affare',
    'post_status' => 'publish',
    'posts_per_page' => 1,
    'meta_key' => 'ca_ufficiale',
    'meta_value' => '1',
    'fields' => 'ids',
    'no_found_rows' => false,
));
$official_count = (int) $official_count_query->found_posts;

$negotiation_count_query = new WP_Query(array(
    'post_type' => 'ca_affare',
    'post_status' => 'publish',
    'posts_per_page' => 1,
    'tax_query' => array(array(
        'taxonomy' => 'ca_stato_affare',
        'field' => 'slug',
        'terms' => 'trattativa',
    )),
    'fields' => 'ids',
    'no_found_rows' => false,
));
$negotiation_count = (int) $negotiation_count_query->found_posts;

$market_category = get_category_by_slug('calciomercato');
$is_market_content = static function ($post) {
    $text = strtolower(wp_strip_all_tags($post->post_title . ' ' . $post->post_excerpt));
    foreach (array('calciomercato', 'trattativ', 'trasferiment', 'ufficiale', 'firma ', 'rinnovo', 'prestito', 'cessione', 'acquisto', 'passa al', 'arriva ') as $keyword) {
        if (strpos($text, $keyword) !== false) {
            return true;
        }
    }
    return get_post_type($post) === 'ca_affare';
};

$is_match_content = static function ($post) {
    $text = strtolower(wp_strip_all_tags($post->post_title . ' ' . $post->post_excerpt));
    foreach (array('risultato', 'diretta', 'live:', 'finale', 'gol ', 'vittoria', 'sconfitta', 'pareggio', 'highlights', 'partita in corso') as $keyword) {
        if (strpos($text, $keyword) !== false) {
            return true;
        }
    }
    return false;
};

$recent_candidates = get_posts(array(
    'post_type' => array('post', 'ca_affare'),
    'post_status' => 'publish',
    'posts_per_page' => 60,
    'orderby' => 'date',
    'order' => 'DESC',
    'suppress_filters' => false,
));

$market_ids = array();
$match_ids = array();
$general_ids = array();
foreach ($recent_candidates as $candidate) {
    if ($is_market_content($candidate)) {
        $market_ids[] = (int) $candidate->ID;
    } elseif ($is_match_content($candidate)) {
        $match_ids[] = (int) $candidate->ID;
    } elseif ($candidate->post_type === 'post') {
        $general_ids[] = (int) $candidate->ID;
    }
}

$news_query = static function ($ids, $limit) {
    return new WP_Query(array(
        'post_type' => array('post', 'ca_affare'),
        'post_status' => 'publish',
        'posts_per_page' => $limit,
        'post__in' => $ids ?: array(0),
        'orderby' => 'post__in',
        'ignore_sticky_posts' => true,
    ));
};

$market_news = $news_query(array_slice($market_ids, 0, 8), 8);
$market_feed = $news_query(array_slice($market_ids, 0, 4), 4);
$match_news = $news_query(array_slice($match_ids, 0, 6), 6);
$general_news = $news_query(array_slice($general_ids, 0, 6), 6);

$render_news = static function ($query, $empty_message) {
    if (!$query->have_posts()) {
        echo '<div class="ca-latest__empty">' . esc_html($empty_message) . '</div>';
        return;
    }
    while ($query->have_posts()) {
        $query->the_post();
        ?>
        <article class="ca-latest-item">
            <span class="ca-latest-item__badge"><?php echo ca_theme_news_badge(); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?></span>
            <div class="ca-latest-item__body">
                <div class="ca-latest-item__meta">
                    <span><?php echo esc_html(ca_theme_news_label()); ?></span>
                    <time datetime="<?php echo esc_attr(get_the_date(DATE_W3C)); ?>"><?php echo esc_html(get_the_date('d/m · H:i')); ?></time>
                </div>
                <h3><a href="<?php the_permalink(); ?>"><?php the_title(); ?></a></h3>
            </div>
            <a class="ca-latest-item__open" href="<?php the_permalink(); ?>" aria-label="<?php echo esc_attr('Apri: ' . get_the_title()); ?>">→</a>
        </article>
        <?php
    }
    wp_reset_postdata();
};
?>

<h1 class="screen-reader-text">CalcioAffari: calciomercato e calcio in tempo reale</h1>
<section class="ca-team-choice">
    <div class="ca-shell">
        <div class="ca-team-choice__copy">
            <div>
                <span class="ca-eyebrow">Tutte le squadre</span>
                <h2>La tua squadra</h2>
                <p>Scegli il club preferito: lo ricorderemo su questo dispositivo e, quando accedi, anche nel tuo profilo.</p>
            </div>
        </div>
        <div class="ca-team-choice__control">
            <label for="ca-team-select">Squadra preferita</label>
            <select id="ca-team-select" data-team-select>
                <option value="">Seleziona una squadra</option>
                <?php foreach (ca_theme_serie_a_teams() as $slug => $name) : ?>
                    <option value="<?php echo esc_attr($slug); ?>" data-url="<?php echo esc_url(ca_theme_term_url('ca_squadra', $slug)); ?>"><?php echo esc_html($name); ?></option>
                <?php endforeach; ?>
            </select>
            <button type="button" class="ca-team-choice__open" data-team-open disabled>Apri le notizie</button>
        </div>
    </div>
</section>

<aside class="ca-shell ca-ad-slot ca-ad-slot--leaderboard" aria-label="Spazio pubblicitario">
    <span>Pubblicità</span>
    <strong>Leaderboard 970 × 90</strong>
</aside>

<section class="ca-news-dashboard">
    <div class="ca-shell ca-news-dashboard__layout">
        <section class="ca-latest ca-latest--lead">
            <header class="ca-latest__head">
                <div>
                    <span class="ca-eyebrow ca-eyebrow--light">Trasferimenti, ufficialità e trattative</span>
                    <h2>Ultime di mercato</h2>
                </div>
                <a href="<?php echo esc_url(ca_theme_archive_url('ca_affare')); ?>">Tutto il calciomercato <span>→</span></a>
            </header>
            <div class="ca-latest__list">
                <?php $render_news($market_news, 'Gli aggiornamenti di mercato verificati compariranno qui.'); ?>
            </div>
        </section>

        <aside class="ca-market-live">
            <header class="ca-market-live__head">
                <div class="ca-market-live__identity">
                    <span class="ca-market-live__signal"><i></i></span>
                    <div>
                        <small>Sessione estiva 2026/27</small>
                        <h2>Osservatorio mercato</h2>
                        <p>Aggiornato al <?php echo esc_html(wp_date('d/m/Y · H:i')); ?></p>
                    </div>
                </div>
                <a href="<?php echo esc_url(ca_theme_archive_url('ca_affare')); ?>">Database trasferimenti <span>→</span></a>
            </header>

            <div class="ca-market-live__body">
                <div class="ca-market-feed">
                    <strong class="ca-market-feed__title">Attività più recente</strong>
                    <?php if ($market_feed->have_posts()) : ?>
                        <?php while ($market_feed->have_posts()) : $market_feed->the_post(); ?>
                            <a href="<?php the_permalink(); ?>">
                                <time><?php echo esc_html(get_the_date('H:i')); ?></time>
                                <span class="ca-market-feed__badge"><?php echo ca_theme_news_badge(); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?></span>
                                <strong><?php the_title(); ?></strong>
                                <b>→</b>
                            </a>
                        <?php endwhile; wp_reset_postdata(); ?>
                    <?php else : ?>
                        <p class="ca-market-feed__empty">Il flusso si attiverà con le prime operazioni verificate.</p>
                    <?php endif; ?>
                </div>

                <div class="ca-market-live__metrics">
                    <div class="is-pending"><strong>—</strong><span>Movimenti ufficiali Italia</span></div>
                    <div class="is-pending"><strong>—</strong><span>Movimenti ufficiali Europa</span></div>
                    <div class="is-pending"><strong>€ —</strong><span>Milioni spesi in Italia</span></div>
                    <div class="is-pending"><strong>€ —</strong><span>Milioni spesi in Europa</span></div>
                    <div><strong><?php echo esc_html((string) $market_news->found_posts); ?></strong><span>Aggiornamenti pubblicati</span></div>
                </div>
            </div>
            <p class="ca-market-live__disclaimer">I contatori riportano esclusivamente movimenti verificati e registrati nel database CalcioAffari: nessun dato viene inventato.</p>
        </aside>

        <div class="ca-news-dashboard__columns">
            <section class="ca-latest">
                <header class="ca-latest__head">
                    <div>
                        <span class="ca-eyebrow ca-eyebrow--light">Risultati e partite in diretta</span>
                        <h2>Ultime dai campi</h2>
                    </div>
                    <a href="<?php echo esc_url(get_permalink(get_option('page_for_posts')) ?: home_url('/')); ?>">Vedi tutte <span>→</span></a>
                </header>
                <div class="ca-latest__list">
                    <?php $render_news($match_news, 'La sezione mostrerà risultati, partite in corso e aggiornamenti live verificati.'); ?>
                </div>
            </section>

            <section class="ca-latest">
                <header class="ca-latest__head">
                    <div>
                        <span class="ca-eyebrow ca-eyebrow--light">Calcio italiano e internazionale</span>
                        <h2>Ultime dal calcio</h2>
                    </div>
                    <a href="<?php echo esc_url(get_permalink(get_option('page_for_posts')) ?: home_url('/')); ?>">Vedi tutte <span>→</span></a>
                </header>
                <div class="ca-latest__list">
                    <?php $render_news($general_news, 'Le notizie generali verificate compariranno qui.'); ?>
                </div>
            </section>
        </div>

        <aside class="ca-ad-slot ca-ad-slot--infeed" aria-label="Spazio pubblicitario">
            <span>Pubblicità</span>
            <strong>Formato responsive in-feed</strong>
        </aside>
    </div>
</section>

<section class="ca-world">
    <div class="ca-shell">
        <div class="ca-section-title">
            <div>
                <span class="ca-eyebrow">Copertura globale</span>
                <h2>Tutto il calcio mondiale</h2>
            </div>
            <p>Dai campionati italiani alle coppe europee, dalle nazionali ai principali mercati internazionali.</p>
        </div>
        <div class="ca-world__grid">
            <?php
            $world_competitions = array(
                array('Serie A', 'Italia', 'serie-a', 'legaseriea.it'),
                array('Premier League', 'Inghilterra', 'premier-league', 'premierleague.com'),
                array('La Liga', 'Spagna', 'la-liga', 'laliga.com'),
                array('Bundesliga', 'Germania', 'bundesliga', 'bundesliga.com'),
                array('Ligue 1', 'Francia', 'ligue-1', 'ligue1.com'),
                array('Champions League', 'Europa', 'champions-league', 'uefa.com'),
                array('Europa League', 'Europa', 'europa-league', 'uefa.com'),
                array('Nazionali', 'Mondo', 'nazionali', 'uefa.com'),
                array('Mondiali', 'Mondo', 'mondiali', 'upload.wikimedia.org/wikipedia/commons/6/60/2026_FIFA_World_Cup_logo.svg'),
                array('Sud America', 'CONMEBOL', 'sud-america', 'conmebol.com'),
                array('MLS', 'Stati Uniti', 'mls', 'mlssoccer.com'),
                array('Saudi Pro League', 'Arabia Saudita', 'saudi-pro-league', 'spl.com.sa'),
            );
            foreach ($world_competitions as $competition) :
                ?>
                <a class="ca-world-card" href="<?php echo esc_url(ca_theme_term_url('ca_campionato', $competition[2])); ?>">
                    <span class="ca-world-card__logo">
                        <?php $competition_logo = get_template_directory_uri() . '/assets/images/brand/calcioaffari-favicon-192-transparent.png'; ?>
                        <img src="<?php echo esc_url($competition_logo); ?>" alt="<?php echo esc_attr('Logo ' . $competition[0]); ?>" width="48" height="48" loading="lazy">
                    </span>
                    <div><strong><?php echo esc_html($competition[0]); ?></strong><small><?php echo esc_html($competition[1]); ?></small></div>
                    <b>→</b>
                </a>
            <?php endforeach; ?>
        </div>
    </div>
</section>

<?php if ($official_count > 0) : ?>
    <div class="ca-shell ca-home-content">
        <?php echo do_shortcode('[calcioaffari_ufficiali numero="6"]'); ?>
    </div>
<?php endif; ?>

<?php get_footer(); ?>
