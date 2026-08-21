# Audit di stabilità — CalcioAffari Local Newsroom 1.0.7

Data: 21 agosto 2026

## Difetto riprodotto sul sito reale

L'agente 1.0.6 poteva scartare definitivamente un job quando Qwen3 non raggiungeva 160 parole dopo tre riscritture. L'audit live ha inoltre mostrato che le riscritture ripetute aumentavano testo generico e ripetitivo senza aggiungere informazioni verificabili.

## Correzione strutturale

- La lunghezza è ora un obiettivo editoriale e non può più rifiutare un job completato.
- L'agente esegue al massimo una correzione e conserva la versione più vicina alla fascia richiesta.
- Un contenuto ancora fuori target viene inviato a WordPress con un avviso esplicito.
- WordPress salva l'articolo in revisione; anche in modalità automatica l'avviso impedisce la pubblicazione senza controllo umano.
- I precedenti rifiuti dovuti alla lunghezza vengono rimessi automaticamente in coda dall'aggiornamento del plugin.

## Altri controlli derivati dall'audit live

- Rimozione deterministica dei marcatori interni come `(ID: 5)` da titolo, sommario e corpo.
- Prompt aggiornato per vietare domini, nomi delle testate e identificatori tecnici nel testo destinato al lettore.
- Filtro preventivo per gli usi palesemente fuori tema della parola “mercato” (televisione, radio, finanza e lavoro).
- Gli avvisi editoriali e il conteggio parole vengono conservati nei metadati del contenuto e mostrati nel riquadro di revisione.
- L'app 1.0.7 richiede il plugin 0.8.5; il plugin non assegna nuovi job agli agenti precedenti che contenevano ancora il blocco.

## Criteri di consegna

- lint PHP 8.1;
- parsing completo degli script PowerShell;
- test che un testo corto venga restituito dopo un solo tentativo e non generi `CA_MODEL_CONSTRAINT`;
- test dell'avviso non bloccante sulla lunghezza;
- test della rimozione dei marcatori interni;
- build e prova reale dell'installer Windows: installazione, aggiornamento con arresto del vecchio processo, riavvio e disinstallazione;
- archivio plugin e installer accompagnati da SHA-256.

