<?php get_header(); ?>
<?php while (have_posts()) : the_post(); ?>
<article class="ca-single-article">
    <header class="ca-single-article__head">
        <div class="ca-shell ca-reading-width">
            <div class="ca-single-deal__meta"><span><?php echo esc_html(get_the_date('d F Y')); ?></span><span><?php echo esc_html((string) ca_theme_read_time()); ?> minuti</span></div>
            <h1><?php the_title(); ?></h1>
            <?php if (has_excerpt()) : ?><p><?php echo esc_html(ca_theme_article_excerpt(get_the_excerpt())); ?></p><?php endif; ?>
        </div>
    </header>
    <?php if (has_post_thumbnail()) : ?>
        <div class="ca-shell ca-featured-image"><?php the_post_thumbnail('ca-hero'); ?></div>
    <?php endif; ?>
    <div class="ca-shell ca-reading-width ca-prose">
        <?php echo apply_filters('the_content', ca_theme_article_content(get_the_content())); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
        <?php ca_theme_render_ai_disclosure(); ?>
        <?php ca_theme_render_article_sources(); ?>
        <?php ca_theme_render_discovery_credit(); ?>
    </div>
</article>
<?php endwhile; ?>
<?php get_footer(); ?>
