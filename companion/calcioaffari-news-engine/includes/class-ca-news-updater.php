<?php

if (!defined('ABSPATH')) {
    exit;
}

final class CA_News_Updater {
    private const API = 'https://api.github.com/repos/trbrec/calcioaffari/releases/latest';
    private const ASSET_PATTERN = '/^calcioaffari-news-engine-v(?P<version>[0-9]+(?:\.[0-9]+){1,3})\.zip$/';

    public static function register(): void {
        add_filter('update_plugins_github.com', array(__CLASS__, 'update'), 10, 4);
    }

    public static function update($update, array $plugin_data, string $plugin_file, array $locales) {
        unset($plugin_data, $locales);
        if ($plugin_file !== plugin_basename(CA_NEWS_FILE)) {
            return $update;
        }
        $release = self::release();
        if (!$release || empty($release['version']) || version_compare(CA_NEWS_VERSION, $release['version'], '>=')) {
            return false;
        }
        return array(
            'slug' => dirname(plugin_basename(CA_NEWS_FILE)),
            'version' => $release['version'],
            'url' => 'https://github.com/trbrec/calcioaffari',
            'package' => $release['package'],
            'tested' => get_bloginfo('version'),
            'requires_php' => '8.1',
        );
    }

    private static function release(): ?array {
        $cached = get_site_transient('ca_news_latest_release');
        if (is_array($cached)) {
            return $cached;
        }
        $response = wp_remote_get(self::API, array(
            'timeout' => 10,
            'headers' => array('Accept' => 'application/vnd.github+json', 'User-Agent' => 'CalcioAffari-WordPress/' . CA_NEWS_VERSION),
        ));
        if (is_wp_error($response) || wp_remote_retrieve_response_code($response) !== 200) {
            return null;
        }
        $data = json_decode(wp_remote_retrieve_body($response), true);
        foreach ((array) ($data['assets'] ?? array()) as $asset) {
            if (preg_match(self::ASSET_PATTERN, (string) ($asset['name'] ?? ''), $matches)) {
                $release = array(
                    'version' => $matches['version'],
                    'package' => esc_url_raw((string) $asset['browser_download_url']),
                );
                set_site_transient('ca_news_latest_release', $release, 6 * HOUR_IN_SECONDS);
                return $release;
            }
        }
        return null;
    }
}
