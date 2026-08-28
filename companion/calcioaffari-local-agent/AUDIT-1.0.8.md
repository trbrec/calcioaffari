# Audit editoriale — CalcioAffari Local Newsroom 1.0.8

Data: 21 agosto 2026

## Difetto riprodotto sul sito reale

L'audit della 1.0.7 sul sito ha individuato un articolo che collegava impropriamente Bruno Guimarães alla rosa dell'Arsenal, conteneva il refuso “Arseanal”, esponeva i domini delle fonti e ripeteva più volte lo stesso concetto. Il problema era aggravato dalla riscrittura automatica usata per inseguire il numero di parole: partendo da prove molto sintetiche, il modello aggiungeva contesto non supportato.

## Correzioni strutturali

- Eliminata qualsiasi riscrittura finalizzata ad allungare il testo.
- Le prove costituite quasi soltanto da titoli richiedono un brief di 80-140 parole con avviso di prove insufficienti.
- Il prompt vieta esplicitamente di dedurre appartenenze ai club, rapporti tra fatti o trattative non scritte nelle prove.
- Ogni fatto deve comparire nei claim e le fonti mostrate da WordPress includono l'unione delle fonti effettivamente usate nei claim.
- Claim malformati non distruggono l'intero job: vengono esclusi e producono un controllo umano obbligatorio.
- Domini, nomi tecnici delle fonti e ID interni vengono rimossi deterministicamente dal testo destinato al lettore.
- Aggiunto un controllo conservativo per i refusi e le preposizioni dei club osservati nell'audit reale.
- I vecchi job respinti non vengono riaperti automaticamente: potrebbero provenire da raggruppamenti precedenti e restano isolati dalla nuova pipeline.
- Il plugin 0.8.6 accetta soltanto l'agente 1.0.8 o successivo.

## Criteri di consegna

- lint PHP 8.1 e parsing completo degli script PowerShell;
- test di rimozione di domini, ID e attribuzioni tecniche;
- test che una bozza breve compia una sola chiamata al modello e non venga espansa artificialmente;
- test della gestione non distruttiva dei claim parzialmente malformati;
- test che le prove sintetiche impongano revisione umana;
- build, installazione, aggiornamento, riavvio e disinstallazione su Windows;
- verifica su campioni reali prodotti dal sito in modalità Revisione editoriale;
- archivio plugin e installer accompagnati da SHA-256.
