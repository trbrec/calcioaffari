# Audit di rilascio — CalcioAffari Local Newsroom 1.3.2

## Perimetro Windows verificato

- Installazione per il solo utente corrente in `%LOCALAPPDATA%`, senza privilegi amministrativi.
- Due sole attività pianificate, entrambe con nomi fissi: agente all'accesso e watchdog ogni cinque minuti.
- Nessuna creazione di servizi Windows.
- Nessuna chiamata a `pnputil`, DevCon, BCDEdit o strumenti di gestione hardware.
- Nessuna installazione o modifica di driver video, firmware, strumenti RGB, profili AMD, frequenze o tensioni.
- Unico pacchetto esterno consentito: `Ollama.Ollama` tramite winget o installer ufficiale firmato da Ollama.
- Unico modello consentito: `qwen3:14b` sul servizio locale `127.0.0.1`.

## Correzione della proprietà delle dipendenze

- La presenza precedente di Ollama e Qwen3 viene distinta dall'installazione eseguita da CalcioAffari.
- La proprietà viene registrata in `dependencies.json` senza contenere credenziali.
- L'avvio autonomo di Ollama viene disabilitato soltanto quando Ollama è stato installato da CalcioAffari.
- La preparazione iniziale termina scaricando Qwen3 dalla GPU e arrestando i processi Ollama posseduti dall'app.
- La disinstallazione rimuove modello e Ollama soltanto quando erano stati installati dall'app.
- Installazioni Ollama/Qwen preesistenti restano intatte.

## Risorse e chiusura

- La coda WordPress viene controllata prima di avviare Ollama.
- Nessun job pronto significa nessun modello caricato.
- Pausa e chiusura della GUI fermano agente e watchdog e scaricano Qwen3.
- Eco e Bilanciato cedono la GPU a giochi e altri carichi 3D/Compute esterni prima di acquisire un lease.
- Ogni raffica è limitata e termina con scarico esplicito del modello.
- Nei profili Eco e Bilanciato il carico GPU esterno viene ricontrollato ogni due secondi anche durante la generazione.
- Se parte un gioco o un altro carico grafico, la richiesta HTTP a Ollama viene annullata, Qwen3 viene scaricato e il lease viene restituito come retryable.
- Ogni job dispone di un budget rigido di quattro inferenze: stesura, audit, una sola eventuale riscrittura e audit finale.
- L'audit usa un massimo di 480 token; un secondo tentativo di riscrittura non viene eseguito e il risultato non conforme va in quarantena.

## Regressioni obbligatorie

- Versioni e payload installer coerenti.
- Tutti gli script PowerShell analizzati su Windows e codificati UTF-8 con BOM.
- Assenza di comandi per driver, GPU e firmware verificata su ogni file eseguibile del pacchetto.
- Provenienza e firma dell'installer Ollama verificate.
- Tracking, rimozione selettiva e protezione delle installazioni preesistenti verificati.
- Installazione pulita, proprietà delle dipendenze preesistenti, disinstallazione reale dell'EXE e checksum dell'artefatto verificati in GitHub Actions Windows.
