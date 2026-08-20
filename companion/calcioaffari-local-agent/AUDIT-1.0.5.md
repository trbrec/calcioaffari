# Audit di stabilità — CalcioAffari Local Newsroom 1.0.5

## Incidenti analizzati

- Un plugin WordPress inattivo faceva rispondere `admin-ajax.php` con il solo valore `0` e HTTP 400.
- Qwen3 generava articoli da 116–151 parole nonostante il minimo editoriale di 160; WordPress li respingeva al primo tentativo.
- CalcioAffari Core esponeva le proprie pagine soltanto come sottomenu del tipo contenuto Affari, rendendole difficili da individuare.
- Durante un aggiornamento, un processo 1.0.3 già in memoria poteva restare attivo fino al riavvio manuale di Windows o dell'agente.

## Correzioni

- L'app distingue l'endpoint WordPress assente dal generico HTTP 400 e indica esplicitamente quale plugin attivare.
- Il plugin comunica all'agente i limiti editoriali effettivi del sito.
- L'agente conta il solo corpo dell'articolo e corregge automaticamente fino a due volte una bozza fuori lunghezza, senza aggiungere fonti o fatti.
- Gli errori di formato generati dal modello vengono rimessi in coda fino al limite dei tentativi invece di essere scartati immediatamente.
- L'aggiornamento WordPress rimette in coda una sola volta i job respinti dal precedente difetto di lunghezza.
- Il pannello amministrativo principale `CalcioAffari` riunisce l'accesso al motore editoriale, ai contenuti e alla pagina di stato del Core.
- Un risultato IA non decodificabile libera immediatamente il job e applica i tentativi limitati, senza lasciarlo bloccato fino alla scadenza del lease.
- L'installer arresta il processo precedente, ricrea le attività pianificate e avvia automaticamente la versione appena installata.

## Gate obbligatori prima della consegna

1. lint PHP dell'intero plugin;
2. parsing Windows PowerShell 5.1 di tutti gli script;
3. test del trasporto form, degli errori HTTP e della credenziale DPAPI;
4. test del conteggio parole e dei due passaggi di correzione automatica;
5. verifica delle versioni e degli archivi;
6. compilazione, installazione silenziosa, aggiornamento sopra un agente precedente e disinstallazione reale dell'installer;
7. controllo live di entrambi i plugin attivi e dei menu WordPress;
8. prova end-to-end del collegamento con articolo creato in revisione, più prova deterministica del recupero locale di una bozza fuori lunghezza.

## Evidenze live acquisite il 20 agosto 2026

- Plugin WordPress aggiornato a `0.8.3`; Core e News Engine risultano entrambi attivi.
- Migrazione registrata nel log WordPress: 23 notizie respinte per lunghezza rimesse in coda.
- Coda protetta durante l'aggiornamento dell'app: 23 `pending`, 1 `processed`, 0 `leased`, 0 `rejected`.
- Prova di pubblicazione già completata: job 12, articolo WordPress 78, stato `pending` per revisione editoriale.
- L'agente 1.0.3 è rifiutato prima dell'assegnazione di nuovi job; la coda ripartirà soltanto con un'app compatibile 1.0.4 o successiva.

Gli articoli restano in **Revisione editoriale** finché un redattore non li approva. L'installer non dispone ancora di firma Authenticode commerciale; Windows SmartScreen può mostrare un avviso al primo avvio.
