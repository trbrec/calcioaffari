(function () {
    'use strict';

    var menuButton = document.querySelector('.ca-menu-toggle');
    var nav = document.querySelector('.ca-nav');
    if (menuButton && nav) {
        menuButton.addEventListener('click', function () {
            var isOpen = menuButton.getAttribute('aria-expanded') === 'true';
            menuButton.setAttribute('aria-expanded', String(!isOpen));
            nav.classList.toggle('is-open', !isOpen);
            document.body.classList.toggle('ca-menu-open', !isOpen);
        });
    }

    var searchButton = document.querySelector('.ca-search-toggle');
    var searchPanel = document.querySelector('.ca-search-panel');
    if (searchButton && searchPanel) {
        searchButton.addEventListener('click', function () {
            var isOpen = searchButton.getAttribute('aria-expanded') === 'true';
            searchButton.setAttribute('aria-expanded', String(!isOpen));
            searchPanel.hidden = isOpen;
            if (!isOpen) {
                var input = searchPanel.querySelector('input[type="search"]');
                if (input) input.focus();
            }
        });
    }

    var teamSelect = document.querySelector('[data-team-select]');
    var teamOpen = document.querySelector('[data-team-open]');
    if (teamSelect && teamOpen) {
        var savedTeam = '';
        try { savedTeam = window.localStorage.getItem('ca_preferred_team') || ''; } catch (error) { savedTeam = ''; }
        if (window.CalcioAffariUI && CalcioAffariUI.preferredTeam) savedTeam = CalcioAffariUI.preferredTeam;
        if (savedTeam && teamSelect.querySelector('option[value="' + savedTeam + '"]')) teamSelect.value = savedTeam;

        var refreshTeamButton = function () {
            teamOpen.disabled = !teamSelect.value;
        };
        refreshTeamButton();

        teamSelect.addEventListener('change', function () {
            refreshTeamButton();
            if (!teamSelect.value) return;
            try { window.localStorage.setItem('ca_preferred_team', teamSelect.value); } catch (error) { /* Storage can be disabled. */ }
            if (window.CalcioAffariUI && CalcioAffariUI.teamNonce) {
                var body = new URLSearchParams({
                    action: 'ca_save_team_preference',
                    nonce: CalcioAffariUI.teamNonce,
                    team: teamSelect.value
                });
                window.fetch(CalcioAffariUI.ajaxUrl, {
                    method: 'POST',
                    credentials: 'same-origin',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' },
                    body: body.toString()
                }).catch(function () { /* The local preference remains available. */ });
            }
        });

        teamOpen.addEventListener('click', function () {
            var option = teamSelect.options[teamSelect.selectedIndex];
            var url = option ? option.getAttribute('data-url') : '';
            if (url) window.location.assign(url);
        });
    }

    document.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape') return;
        if (menuButton && nav) {
            menuButton.setAttribute('aria-expanded', 'false');
            nav.classList.remove('is-open');
            document.body.classList.remove('ca-menu-open');
        }
        if (searchButton && searchPanel) {
            searchButton.setAttribute('aria-expanded', 'false');
            searchPanel.hidden = true;
        }
    });
}());
