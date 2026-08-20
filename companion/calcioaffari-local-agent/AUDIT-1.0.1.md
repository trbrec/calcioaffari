# Audit di stabilità — CalcioAffari Local Newsroom 1.0.1

## Ambito

L'audit copre installer Windows, configurazione grafica, agente in background, diagnostica, autenticazione con WordPress, coda editoriale e aggiornamento del plugin.

## Difetti bloccanti corretti

- **Prima configurazione interrotta:** l'assenza delle attività pianificate, normale prima del primo collegamento, non viene più trattata come un errore fatale di Windows.
- **Interfaccia bloccata:** i controlli di rete del pannello sono eseguiti in un processo diagnostico separato.
- **Installazione senza esito:** la GUI rileva l'uscita anomala del backend e mostra un errore terminale invece di restare in attesa.
- **Download opaco:** il progresso di `ollama pull` viene acquisito e mostrato come percentuale reale.
- **Annullamento incompleto:** l'applicazione termina l'intero albero dei processi, compreso il download figlio.
- **Errori HTTP incoerenti:** setup, agente, riparazione e diagnostica usano un solo client con timeout e classificazione condivisa.
- **Retry infiniti:** ogni lavoro WordPress ha un contatore e viene respinto dopo tre tentativi; gli errori deterministici terminano subito.
- **Raccolta dipendente da WP-Cron:** se l'ultima raccolta è scaduta, la richiesta dell'agente aggiorna automaticamente le fonti prima di cercare un lavoro.
- **Codice revocato o Anti-Bot:** i tentativi automatici vengono sospesi per evitare richieste ripetute e nuovi blocchi dell'IP.
- **Disinstallazione assente:** l'applicazione è registrata in Windows e rimuove attività, configurazione, log e credenziale.
- **Caratteri corrotti:** tutti gli script sono distribuiti in UTF-8 con BOM per Windows PowerShell 5.1.
- **Supporto senza segreti:** il pannello esporta log e configurazione diagnostica senza includere il codice di collegamento.

## Controlli di sicurezza

- Il motore Ollama è accettato soltanto su `localhost`.
- Il sito WordPress deve usare HTTPS.
- Il codice di collegamento è cifrato con DPAPI per l'utente Windows e non compare negli archivi diagnostici.
- L'installer Ollama scaricato direttamente viene eseguito soltanto se la firma Authenticode è valida e appartiene a Ollama.
- Il risultato IA viene validato lato WordPress prima della creazione dell'articolo.

## Gate di rilascio

La release viene pubblicata soltanto dopo:

1. lint PHP su tutti i file del plugin;
2. parsing di tutti gli script con Windows PowerShell;
3. test delle risposte HTTP valide, Anti-Bot, autenticazione, HTML inatteso e JSON incompleto;
4. test della cifratura DPAPI;
5. regressione specifica sulla prima configurazione senza attività pianificate;
6. test dei retry limitati;
7. verifica delle versioni e del ciclo di disinstallazione;
8. compilazione reale dell'installer con Inno Setup su Windows;
9. verifica degli archivi e generazione SHA-256.

## Limite noto di distribuzione

L'installer è verificato dalla pipeline e accompagnato dall'hash SHA-256, ma non dispone ancora di una firma Authenticode commerciale CalcioAffari. Windows SmartScreen può quindi mostrare un avviso al primo avvio. Questo non incide sul funzionamento, ma la firma con certificato aziendale resta necessaria per una distribuzione pubblica senza avvisi.
