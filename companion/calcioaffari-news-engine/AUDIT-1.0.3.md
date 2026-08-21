# Audit CalcioAffari News Engine 1.0.3

## Obiettivo

Correggere i difetti osservati nel controllo live del 21 agosto 2026 senza abilitare la pubblicazione automatica.

## Correzioni verificate

- ogni risultato del motore viene creato esclusivamente come `ca_affare`; un evento `other` viene messo in quarantena e non può più comparire tra gli Articoli ordinari;
- i vecchi contenuti IA non pubblicati finiti nella sezione sbagliata vengono spostati in bozza e marcati come quarantena, senza cancellazioni;
- titoli che combinano due operazioni mediante una congiunzione vengono esclusi prima della coda;
- le formule generiche già vietate dal prompt vengono controllate anche in PHP;
- la coda alterna notizie recenti e recupero storico, con precedenza alle fonti italiane, così il backfill non blocca il flusso live;
- il pannello e l'endpoint salute mostrano la versione effettiva dell'app che ha contattato WordPress.

## Sicurezza editoriale

La modalità resta `review`. Nessun articolo viene pubblicato automaticamente e nessun contenuto già pubblicato viene modificato dalla migrazione.
