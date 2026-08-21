# Audit runtime Windows — CalcioAffari Local Newsroom 1.0.10

## Anomalia osservata

Il watchdog registrato in Utilità di pianificazione avviava direttamente `powershell.exe` ogni cinque minuti. L'azione includeva `-WindowStyle Hidden`, ma Windows poteva creare la finestra console prima che PowerShell elaborasse l'opzione, provocando un lampeggio e il temporaneo passaggio in primo piano sopra le altre applicazioni.

## Correzione strutturale

- L'avvio automatico e il watchdog invocano ora `wscript.exe`, processo appartenente al sottosistema grafico di Windows e quindi privo di console.
- `hidden-launcher.vbs` avvia PowerShell con stile finestra `0`, oltre alle difese `-NonInteractive` e `-WindowStyle Hidden`.
- Il launcher accetta soltanto un file PowerShell esistente con estensione `.ps1` e usa esclusivamente Windows PowerShell installato nel percorso di sistema.
- L'aggiornamento dalla 1.0.9 arresta l'agente precedente, sostituisce entrambe le attività pianificate e riavvia automaticamente l'agente con il nuovo avvio invisibile.
- Anche i collegamenti del desktop, del menu Start, il pulsante di riparazione e l'apertura del pannello usano il launcher privo di console.
- Il mutex dell'agente resta invariato: i controlli ogni cinque minuti non possono creare una seconda istanza concorrente.

## Gate di regressione

- coerenza versione 1.0.10 in manifest, script e installer;
- presenza e inclusione di `hidden-launcher.vbs` nell'installer;
- assenza dell'avvio diretto di PowerShell nelle attività pianificate nuove;
- prova reale del launcher con esecuzione di uno script sentinella su Windows;
- verifica delle azioni registrate per avvio automatico e watchdog;
- upgrade da una vecchia attività PowerShell visibile alla nuova azione WScript invisibile;
- arresto del vecchio agente durante l'upgrade e riavvio della 1.0.10;
- installazione, registrazione applicazione, disinstallazione e rimozione dei file;
- test PHP/editoriali, PowerShell e packaging già presenti, senza riduzione della copertura.

## Compatibilità editoriale

Il plugin WordPress 0.8.9 continua a richiedere CalcioAffari Local Newsroom 1.0.9 o successivo; la 1.0.10 è pienamente compatibile. La pubblicazione resta in modalità **Revisione editoriale** e questa release non modifica filtri, testi, fonti, code o criteri di pubblicazione.
