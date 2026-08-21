# Audit completo CalcioAffari · 21 agosto 2026

## Esito esecutivo

Il sito risponde e WordPress non segnala errori critici, ma il prodotto non è ancora pronto per crescita organica finché non vengono chiusi quattro punti: continuità editoriale verificabile, pubblicazione/revisione degli Affari, indicizzazione dei contenuti di calciomercato e identità utente con consenso marketing separato.

## Correzioni già implementate

- News Engine 1.0.5: quattro claim su cinque partono dalla notizia più vecchia e uno resta sul live.
- Backfill acquisito dal 29/07/2026: 729 URL pertinenti su 1.112 controllati.
- Feed italiano Gazzetta Calciomercato aggiunto alle fonti live.
- Limite editoriale impostato a 75 elementi al giorno; modalità invariata su Revisione.
- Insights 1.0.1: statistiche aggregate orarie, giornaliere e settimanali senza cookie analitici, IP o user agent conservati.
- Alert email limitato al caso richiesto: coda presente, raccolta server recente e agente locale assente da oltre 12 minuti.
- Tema 0.8.1: selettore squadra compatto, preferenza locale/profilo, metadati SEO/social, favicon locali, Cookie Policy nel footer.
- Ticker esteso agli Affari e contenuti/tassonomie editoriali aggiunti alle sitemap core.
- Cookie Policy pubblicata; iscrizione e marketing restano consensi distinti.

## Stato live verificato

- WordPress 7.1; News Engine 1.0.4 attivo al momento della verifica.
- App locale 1.1.1 con contatto regolare.
- Sette fonti italiane/internazionali attive dopo l'aggiunta della Gazzetta.
- Una raccolta manuale ha letto 180 elementi, acquisito 8 nuovi URL pertinenti e registrato zero errori.
- Coda rilevata: 625 pronti per IA, 1 in elaborazione, 19 in revisione, 58 respinti.
- Il front-end live usa ancora il tema 0.7.0: griglia squadra invasiva e assenza di meta description/Open Graph.
- La sitemap live include soltanto post, pagine, categorie e autori; non include ancora Affari, squadre e campionati.
- La ricerca pubblica non mostra risultati indicizzati per `site:calcioaffari.it`.

## Rischi e priorità

### P0 · Continuità notizie

- Installare News Engine 1.0.5 e verificare la comparsa di almeno un Affare datato 29/07/2026.
- Non abbassare i filtri per raggiungere un numero artificiale: la soglia di 50/giorno va misurata su URL pertinenti disponibili e articoli validati, non su contenuti inventati o duplicati.
- Esporre nel backend copertura per giorno: acquisiti, validi, respinti, mancanti e ultimo job per data.
- Conservare il live ogni quinto claim e drenare il backlog con gli altri quattro.

### P0 · Indicizzazione e distribuzione

- Installare il tema 0.8.1 e rigenerare i permalink.
- Verificare che la sitemap contenga `ca_affare`, `ca_squadra` e `ca_campionato`.
- Collegare Search Console, inviare la sitemap e controllare copertura/canonical dopo il popolamento.
- Pubblicare soltanto dopo revisione; finché gli Affari restano “In attesa” non possono apparire ai visitatori né essere indicizzati.

### P1 · Misurazione e alert

- Attivare Insights 1.0.1 e verificare stato “Operativo”, email destinataria e primo incremento visita da sessione anonima.
- Mantenere i conteggi first-party aggregati per evitare un banner di consenso analitico finché non vengono introdotti strumenti di terze parti.
- Aggiungere una vista per pagina/sorgente e tasso di conversione iscrizione solo dopo aver definito gli eventi necessari.

### P1 · Account e preferenze

- Prima fase: registrazione/login nativi WordPress con email, password, recupero password e preferenza squadra salvata nel profilo.
- Newsletter/marketing: checkbox separata, facoltativa, non preselezionata, con timestamp e versione dell'informativa.
- Google e Facebook: usare OAuth/OIDC con redirect HTTPS e provider configurati; servono client ID/secret reali e URL di callback registrati. Non inserire chiavi nel tema o nel repository.
- Ridurre i dati al minimo: email, preferenza squadra, stato del consenso; nessun profilo social superfluo.

### P1 · Privacy e sicurezza

- Completare la Privacy Policy attualmente in bozza e indicarla come pagina Privacy di WordPress.
- Aggiornare Cookie Policy quando verranno attivati login social, newsletter, advertising o analytics terzi.
- Disattivare/rimuovere plugin e temi inutilizzati dopo verifica; non attivare ottimizzazione/cache o security plugin senza testare AJAX, REST e cron della newsroom.
- Abilitare OPcache lato hosting.
- Limitare l'enumerazione pubblica degli autori se non serve e verificare ruoli/capacità degli account redazionali.

### P2 · UX e qualità editoriale

- Il selettore squadra diventa un menu compatto espandibile, adatto al mobile.
- Correggere i link tassonomia che oggi ricadono sulla home quando il termine non esiste.
- Rimuovere la pagina campione e completare categorie/tag degli articoli storici.
- Aggiungere immagini con licenza verificata o asset proprietari; evitare loghi remoti caricati da domini terzi.

## Criteri di accettazione finali

1. Notizia valida del 29/07/2026 visibile in Affari in revisione.
2. Copertura giornaliera misurabile fino al 21/08/2026 e live aggiornato entro cinque minuti quando esistono nuove fonti pertinenti.
3. Alert inviato soltanto simulando l'arresto dell'app locale con server/ingest attivi.
4. Dashboard statistiche operativa su tre granularità e senza identificatori personali.
5. Selettore squadra mobile compatto e persistenza per ospite/utente.
6. Sitemap comprensiva degli Affari e metadati SEO/social presenti.
7. Cookie Policy pubblica; Privacy Policy pubblicata e selezionata.
8. Registrazione/login email funzionanti; social login attivato soltanto con credenziali provider e consenso marketing separato.
