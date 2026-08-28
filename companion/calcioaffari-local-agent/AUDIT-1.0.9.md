# Audit editoriale — CalcioAffari Local Newsroom 1.0.9

## Esito dell'audit sul sito reale

Il collegamento tra WordPress, agente locale e Qwen3 era operativo, ma la sorgente GDELT forniva il solo titolo duplicato come estratto. Il sistema generava quindi bozze prive di prove sostanziali, inclusi contenuti in cinese, articoli in inglese, tennis, NCAA, anticipazioni di partite e testi tra 17 e 78 parole. La modalità `review` ne ha impedito la pubblicazione automatica, ma non la creazione nella coda WordPress.

## Correzioni strutturali

- GDELT headline-only viene disattivato e non può più alimentare la coda.
- Vengono installati feed RSS professionali di BBC Sport, The Guardian, Sky Sports e Football Italia.
- Ogni elemento viene filtrato prima del salvataggio per lingua, alfabeto, pertinenza al calciomercato e quantità minima di evidenza.
- NCAA, transfer portal, tennis, altri sport, calendari, formazioni e semplici preview vengono esclusi deterministicamente.
- Le code legacy GDELT non ancora elaborate vengono messe in quarantena senza eliminare articoli o dati già creati.
- Il publisher rifiuta in modo definitivo le prove headline-only e i testi sotto le 80 parole.
- Titoli non tradotti o con alfabeti non supportati ricevono una sola seconda stesura e poi vengono bloccati.
- Un sottotitolo iniziale che duplica il titolo viene rimosso automaticamente.
- Un contenuto viene classificato come `ca_affare` soltanto se contiene il calciatore e almeno un club coinvolto.
- Il target 160-360 parole resta un obiettivo editoriale; non viene mai raggiunto con riempitivi o ripetizioni.

## Casi di regressione obbligatori

- titolo cinese o misto cinese/latino;
- Carlos Alcaraz e US Open;
- NCAA e transfer portal;
- titolo inglese non tradotto;
- preview, calendario o formazione;
- titolo duplicato come estratto;
- testo inferiore a 80 parole;
- sottotitolo uguale o contenuto nel titolo;
- “di Arsenal”, refuso “Arseanal” e attribuzioni a club non provate;
- installazione, aggiornamento e disinstallazione Windows.

## Compatibilità

Il plugin WordPress 0.8.9 richiede CalcioAffari Local Newsroom 1.0.9 o successivo. La pubblicazione resta in modalità revisione. La 0.8.9 completa il filtro stretto sui titoli dopo l'audit del primo ciclo reale delle fonti professionali, includendo corse di mercato e risoluzioni contrattuali esplicite.
