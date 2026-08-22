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
- titoli e corpo devono usare articoli italiani naturali davanti ai club e, quando le prove lo permettono, qualificare il calciatore con ruolo e squadra anziché produrre calchi telegrafici dall’inglese;
- visite mediche, arrivo in città e allenamento non possono più essere promossi a trasferimento concluso: senza conferma primaria il server blocca formule ufficiali o definitive;
- la normalizzazione italiana converte il calco singolare “visita medica” nel plurale editoriale “visite mediche”;
- i titoli che iniziano con un club ricevono automaticamente l’articolo italiano corretto (per esempio “L’Aston Villa”, “Il Porto”, “La Juventus”) e “AC Milan” viene normalizzato in “Milan”;
- le attribuzioni vaghe “secondo le fonti” vengono bloccate, le cifre abbreviate come “€30m” vengono rese in italiano e le formule inglesi della scheda vengono tradotte;
- la lista pubblica deduplica la stessa testata anche quando il cluster contiene più URL di quella fonte, evitando di contarla due volte come fonte indipendente;
- restano invariati estratti-prova letterali, mappatura claim/fonti, blocco delle deduzioni, soglia di confidenza e quarantena delle notizie non dimostrate.
