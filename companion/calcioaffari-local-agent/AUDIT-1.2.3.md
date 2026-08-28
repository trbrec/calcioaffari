# Audit di rilascio — CalcioAffari Local Newsroom 1.2.3

## Correzioni bloccanti

- Il pairing funziona sia dalla cartella sorgente sia dall'installer, che usa
  i nomi versionati `agent-1.2.3.ps1` e `version-1.2.3.json`.
- Un risultato respinto da WordPress viene restituito tramite l'endpoint
  `fail` come errore terminale. Il lease non viene più lasciato scadere e lo
  stesso articolo non viene rigenerato in ciclo.
- Se WordPress rifiuta sia il risultato sia la chiusura terminale, l'agente
  interrompe l'elaborazione con `CA_TERMINAL_FAIL_NOT_ACKNOWLEDGED` invece di
  continuare a consumare CPU.
- Gli archivi diagnostici includono `heartbeat.log` e tutti i manifesti
  `version-*.json`, evitando riferimenti rigidi a una vecchia release.

## Compatibilità e dati

- Aggiornamento per utente Windows, senza privilegi amministrativi obbligatori.
- Pairing e token DPAPI esistenti sono preservati dall'upgrade.
- Nessuna modifica automatica a soglie, modalità editoriale o contenuti.
- Compatibile con News Engine 1.2.8 e con il contratto minimo app 1.1.2.

## Gate di rilascio

La release non deve essere distribuita prima che siano verdi i test per:

1. layout versionato dell'installer e pairing;
2. rifiuto HTTP 400 seguito da chiusura terminale;
3. mancata conferma della chiusura seguita da arresto anti-loop;
4. diagnostica comprensiva di heartbeat;
5. coda server che non riammette job `rejected` senza migrazione esplicita.
