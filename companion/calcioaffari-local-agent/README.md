# CalcioAffari Local Agent

Agente Windows per elaborare in locale la coda del plugin **CalcioAffari News Engine**. I testi delle fonti arrivano via HTTPS, il modello gira soltanto su `localhost` e il risultato torna a WordPress con una password applicazione revocabile.

## Requisiti

- Windows 10/11 con PowerShell 5.1 o superiore.
- Ollama aggiornato e avviato.
- Modello locale consigliato: `qwen3:14b`.
- Plugin WordPress attivo e un utente dedicato con ruolo Editor (o superiore).
- Password applicazione WordPress dedicata all'agente.

## Installazione

1. Installa Ollama e verifica che usi la GPU.
2. Scarica il modello: `ollama pull qwen3:14b`.
3. In WordPress crea una password applicazione chiamata `CalcioAffari Local Agent` per l'utente editoriale dedicato.
4. Apri PowerShell nella cartella dell'agente ed esegui:

   `powershell -ExecutionPolicy Bypass -File .\install.ps1 -SiteUrl https://calcioaffari.it -WordPressUser NOME_UTENTE`

5. Incolla la password applicazione soltanto nella richiesta protetta di PowerShell. Non usare la password principale WordPress.

L'installer cifra la credenziale con DPAPI per l'utente Windows corrente, copia l'agente in `%LOCALAPPDATA%\CalcioAffari` e lo avvia a ogni accesso. Il log è in `%LOCALAPPDATA%\CalcioAffari\agent.log`.

## Comportamento

- Quando il PC è spento nessun contenuto viene perso: la coda resta su WordPress.
- Il sito non apre connessioni verso il PC; è l'agente a interrogare il sito.
- Il motore non scarica immagini né ripubblica fotografie delle testate.
- La modalità iniziale del plugin è **Revisione editoriale**. Passare ad automatica solo dopo il collaudo delle prime notizie.
