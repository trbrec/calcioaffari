# Audit CalcioAffari News Engine 1.1.1

## Problema rilevato sul ciclo reale

Il prompt 1.1.0 chiedeva al modello di aggiungere il flag bloccante `prove insufficienti` quando una fonte era semplicemente breve. Lo stesso flag veniva poi correttamente interpretato dall'agente come motivo di quarantena. Il risultato era una contraddizione: brevi lanci completamente aderenti alle prove venivano respinti anche quando il testo poteva essere pubblicato senza riempitivi.

Il revisore locale poteva inoltre confondere le operazioni estranee presenti nell'estratto sorgente con il contenuto effettivo dell'articolo, oppure usare `grammar_ok` per una contestazione fattuale.

## Correzione

- la brevità della fonte non genera più da sola il flag `prove insufficienti`;
- il flag resta obbligatorio quando una informazione materiale non è sostenuta;
- l'audit valuta `single_story` sul testo prodotto, non sulle prove ignorate;
- `grammar_ok` è riservato alla correttezza linguistica, mentre il grounding resta verificato separatamente;
- il corpo non può ripetere lo stesso rifiuto, accordo, cifra o stato della trattativa in frasi diverse e deve attribuire la testata per nome invece di usare formule vaghe;
- restano invariati estratti-prova letterali, mappatura claim/fonti, blocco delle deduzioni, soglia di confidenza e quarantena delle notizie non dimostrate.
