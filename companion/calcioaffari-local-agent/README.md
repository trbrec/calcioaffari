# CalcioAffari Local Newsroom 0.8.2

Applicazione Windows che collega il motore editoriale di `calcioaffari.it` all'IA locale della workstation. Le fonti arrivano dal sito tramite HTTPS, Qwen3 lavora esclusivamente sul PC e restituisce a WordPress un articolo strutturato con fonti e livello di affidabilità.

## Installazione con doppio clic

1. Avvia `CalcioAffari-Local-Newsroom-Setup-v0.8.2.exe`.
2. Nella finestra grafica seleziona **Prepara motore IA** e segui lo stato visualizzato.
3. Inserisci una sola volta il nome utente WordPress dedicato e la relativa **password applicazione**, quindi seleziona **Collega il sito**.

Non viene mostrata alcuna console PowerShell: installazione, download, collegamento e riparazione sono gestiti dall'interfaccia grafica.

Il file ZIP è disponibile come copia di sicurezza: in quel caso estrailo completamente e avvia `Installa-CalcioAffari.cmd`.

L'installazione:

- installa Ollama se non è già presente;
- scarica `qwen3:14b` (circa 9,3 GB, soltanto la prima volta);
- verifica il collegamento autenticato con il plugin WordPress;
- cifra la password applicazione con Windows DPAPI;
- installa l'agente in `%LOCALAPPDATA%\CalcioAffari`;
- crea l'avvio automatico e un controllo di ripartenza ogni cinque minuti;
- aggiunge `CalcioAffari Local Newsroom` al desktop e al menu Start.

Non usare mai la password principale di WordPress. La password applicazione è separata e revocabile.

## Uso quotidiano

Non devi aprire l'applicazione per farla lavorare: l'agente funziona in background. Il collegamento sul desktop apre soltanto il pannello di stato, dal quale puoi:

- controllare agente, Ollama, modello e WordPress;
- vedere coda, modalità editoriale, fonti attive e ultimo contatto;
- riavviare o riparare automaticamente il servizio;
- aprire il pannello WordPress o il log diagnostico.

Quando il PC è spento, le notizie rimangono nella coda di WordPress. Alla riaccensione l'agente riprende automaticamente. Qwen3 viene liberato dalla memoria dopo dieci minuti di inattività.

## Manutenzione

La manutenzione ordinaria è automatica:

- tentativo di riavvio di Ollama se non risponde;
- watchdog dell'agente ogni cinque minuti;
- nuovi tentativi sui lavori temporaneamente falliti;
- rotazione automatica del log oltre 5 MB;
- nessuna perdita della coda quando il PC o Internet non sono disponibili.

Ollama per Windows gestisce i propri aggiornamenti. Il modello resta bloccato sulla versione configurata per evitare cambiamenti editoriali imprevisti. Eventuali future versioni di CalcioAffari Local Newsroom verranno preparate senza richiedere interventi tecnici sul sistema.

## Requisiti

- Windows 10 22H2 o Windows 11;
- almeno 15 GB liberi su disco;
- plugin **CalcioAffari News Engine** attivo;
- utente WordPress dedicato con ruolo Editor o superiore;
- driver AMD Radeon aggiornati per la Radeon 7900 XTX.

La modalità iniziale del sito deve restare **Revisione editoriale**. L'autopubblicazione va abilitata soltanto dopo il controllo dei primi articoli prodotti.

## Disinstallazione

Fai doppio clic su `Disinstalla-CalcioAffari.cmd`. L'applicazione, le attività automatiche, i log e la credenziale vengono rimossi. Ollama e Qwen3 vengono conservati per evitare un nuovo download da 9,3 GB.
