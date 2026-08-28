<?php
get_header();
while (have_posts()) :
    the_post();
    $post_id = get_the_ID();
    $official = get_post_meta($post_id, 'ca_ufficiale', true) === '1';
    $fields = array(
        'ca_giocatore' => 'Giocatore',
        'ca_club_partenza' => 'Club di partenza',
        'ca_club_arrivo' => 'Club di arrivo',
        'ca_formula' => 'Formula',
        'ca_costo' => 'Valore',
        'ca_scadenza_contratto' => 'Scadenza',
        'ca_data_ufficialita' => 'Data ufficialità',
    );
    $article_sources = ca_theme_article_sources($post_id);
    ?>
    <article class="ca-single-deal">
        <header class="ca-single-deal__head">
            <div class="ca-shell ca-single-deal__head-grid">
                <div>
                    <div class="ca-single-deal__meta">
                        <span class="ca-status <?php echo $official ? 'is-official' : ''; ?>"><i></i><?php echo $official ? 'Ufficiale' : 'Aggiornamento'; ?></span>
                        <span><?php echo esc_html(get_the_date('d F Y')); ?></span>
                    </div>
                    <h1><?php the_title(); ?></h1>
                    <?php if (has_excerpt()) : ?><p><?php echo esc_html(get_the_excerpt()); ?></p><?php endif; ?>
                </div>
                <div class="ca-single-deal__stamp">
                    <span>CA</span>
                    <strong><?php echo $official ? 'Verificato' : 'In aggiornamento'; ?></strong>
                    <small><?php echo $official ? 'Fonte primaria collegata' : 'Stato dichiarato nella scheda'; ?></small>
                </div>
            </div>
        </header>

        <div class="ca-shell ca-single-layout">
            <div class="ca-single-content">
                <?php the_content(); ?>
                <?php ca_theme_render_ai_disclosure($post_id); ?>
                <?php ca_theme_render_discovery_credit($post_id); ?>
            </div>
            <aside class="ca-deal-sheet">
                <div class="ca-deal-sheet__head"><span>Scheda operazione</span><b><?php echo esc_html(ca_theme_affare_status()); ?></b></div>
                <dl>
                    <?php foreach ($fields as $meta_key => $label) :
                        $value = get_post_meta($post_id, $meta_key, true);
                        if (!$value) continue;
                        ?>
                        <div><dt><?php echo esc_html($label); ?></dt><dd><?php echo esc_html($value); ?></dd></div>
                    <?php endforeach; ?>
                </dl>
                <?php if ($article_sources) : ?>
                    <div class="ca-source-box">
                        <span><?php echo esc_html(_n('Fonte consultata', 'Fonti consultate', count($article_sources), 'calcioaffari')); ?></span>
                        <?php foreach ($article_sources as $article_source) : ?>
                            <a href="<?php echo esc_url($article_source['url']); ?>" rel="nofollow noopener noreferrer" target="_blank"><?php echo esc_html($article_source['name']); ?> ↗</a>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>
            </aside>
        </div>
    </article>
    <?php
endwhile;
get_footer();
