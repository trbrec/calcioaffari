# CalcioAffari Local Newsroom 1.1.0

Applicazione Windows che collega il motore editoriale di `calcioaffari.it` all'IA locale della workstation. Le fonti arrivano dal sito tramite HTTPS, Qwen3 lavora esclusivamente sul PC e restituisce a WordPress un articolo strutturato con fonti e livello di affidabilità.

Ogni stesura viene controllata una seconda volta dal modello locale in modalità revisore. Se grounding, singola storia, lingua o grammatica non superano il controllo, viene eseguita una sola nuova stesura; al secondo errore la notizia è messa in quarantena senza creare un post.

## Installazione con doppio clic

1. Avvia `CalcioAffari-Local-Newsroom-Setup-v1.1.0.exe`.
2. Nella finestra grafica seleziona **Prepara motore IA** e segui lo stato visualizzato.
3. In WordPress apri **CalcioAffari**, genera il codice di collegamento e incollalo nell’applicazione, quindi seleziona **Collega il sito**.

Non viene mostrata alcuna console PowerShell: installazione, download, collegamento e riparazione sono gestiti dall'interfaccia grafica.

Il pulsante **Esporta log** è sempre disponibile nella configurazione, anche quando il collegamento fallisce. L'archivio rimuove automaticamente il codice segreto prima del salvataggio.

Il file ZIP è disponibile come copia di sicurezza: in quel caso estrailo completamente e avvia `Installa-CalcioAffari.cmd`.

L'installazione:

- installa Ollama se non è già presente;
- scarica `qwen3:14b` (circa 9,3 GB, soltanto la prima volta) mostrando la percentuale reale;
- verifica il collegamento autenticato con il plugin WordPress;
- cifra il codice di collegamento dedicato con Windows DPAPI;
- installa l'agente in `%LOCALAPPDATA%\CalcioAffari`;
- crea l'avvio automatico e un controllo di ripartenza ogni cinque minuti, entrambi completamente invisibili e senza finestre PowerShell;
- aggiunge `CalcioAffari Local Newsroom` al desktop e al menu Start.

L’applicazione non richiede né conserva la password WordPress. Il codice è limitato alle funzioni di CalcioAffari e può essere revocato generandone uno nuovo.

## Uso quotidiano

Non devi aprire l'applicazione per farla lavorare: l'agente funziona in background. Il collegamento sul desktop apre soltanto il pannello di stato, dal quale puoi:

- controllare agente, Ollama, modello e WordPress;
- vedere coda, modalità editoriale, fonti attive e ultimo contatto;
- riavviare o riparare automaticamente il servizio;
- aprire il pannello WordPress o esportare un archivio diagnostico privo del codice segreto.

Quando il PC è spento, le notizie rimangono nella coda di WordPress. Alla riaccensione l'agente riprende automaticamente. Qwen3 viene liberato dalla memoria dopo dieci minuti di inattività.

## Manutenzione

La manutenzione ordinaria è automatica:

- tentativo di riavvio di Ollama se non risponde;
- watchdog dell'agente ogni cinque minuti;
- nessuna espansione automatica per inseguire la lunghezza: sotto 80 parole viene tentata una sola nuova stesura sostanziale, poi la notizia viene bloccata; tra 80 parole e il target editoriale resta in revisione con un avviso;
- massimo tre tentativi soltanto sui guasti temporanei di rete o del motore locale;
- arresto immediato dei tentativi quando il codice è revocato o SiteGround blocca l'IP, così il firewall non viene martellato;
- rotazione automatica del log oltre 5 MB;
- nessuna perdita della coda quando il PC o Internet non sono disponibili.

Ollama per Windows gestisce i propri aggiornamenti. Il modello resta bloccato sulla versione configurata per evitare cambiamenti editoriali imprevisti. Eventuali future versioni di CalcioAffari Local Newsroom verranno preparate senza richiedere interventi tecnici sul sistema.

## Requisiti

- Windows 10 22H2 o Windows 11;
- almeno 15 GB liberi su disco;
- plugin **CalcioAffari News Engine 1.0.0** attivo;
- codice di collegamento generato dal plugin;
- driver AMD Radeon aggiornati per la Radeon 7900 XTX.

La modalità iniziale del sito deve restare **Revisione editoriale**. L'autopubblicazione va abilitata soltanto dopo il controllo dei primi articoli prodotti.

## Disinstallazione

Usa **Impostazioni Windows > App installate > CalcioAffari Local Newsroom > Disinstalla**, oppure `Disinstalla-CalcioAffari.cmd`. L'applicazione, le attività automatiche, i log e la credenziale vengono rimossi. Ollama e Qwen3 vengono conservati per evitare un nuovo download da 9,3 GB.
