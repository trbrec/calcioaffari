# Audit CalcioAffari Insights 1.1.0

## Risultato

- Le visite sono registrate esclusivamente come contatori aggregati per ora e area del sito.
- Non vengono conservati IP, user agent, cookie analitici o identificatori del visitatore; conservazione 13 mesi.
- Il backend mostra 24 ore, 14 giorni, 12 settimane, trend e aree consultate.
- L'alert locale usa un heartbeat workstation indipendente dall'elaborazione Qwen: scatta soltanto con coda presente, ingest server recente e PC assente da oltre 12 minuti.
- La scelta squadra è salvata nel profilo per gli utenti autenticati e può essere rimossa.
- Registrazione, login e recupero password usano WordPress; l'email è l'unico dato anagrafico richiesto.
- Privacy e marketing hanno consensi separati; il marketing è facoltativo e non preselezionato.
- Google e Facebook sono inattivi finché le credenziali non vengono definite in `wp-config.php`; i token OAuth non sono conservati.
- La Cookie Policy gestita descrive esattamente gli strumenti effettivi e viene aggiornata con la release.

La configurazione dei provider social richiede la registrazione esterna degli URI callback mostrati nel backend. Nessun segreto è incluso nel pacchetto.
