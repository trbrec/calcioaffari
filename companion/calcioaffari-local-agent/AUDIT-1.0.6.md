# Audit di stabilità — CalcioAffari Local Newsroom 1.0.6

## Incidenti analizzati

- Il News Engine disattivato rendeva indisponibile l'endpoint WordPress pur lasciando attivo CalcioAffari Core.
- Qwen3 poteva restituire 78–142 parole anche dopo tre generazioni complete, sotto il minimo editoriale di 160.
- Un URL inserito dal modello causava uno scarto definitivo al primo tentativo.
- Durante un aggiornamento, il processo precedente poteva continuare a eseguire il codice già caricato in memoria.

## Correzioni

- L'app distingue esplicitamente il plugin inattivo dagli altri errori HTTP.
- La prima generazione mira a un intervallo più prudente rispetto al minimo tecnico.
- Le correzioni successive riscrivono esclusivamente `body_html` con uno schema ridotto, conservando metadati, claim e fonti già verificati.
- App e plugin eliminano in modo difensivo gli URL inline senza perdere il testo circostante.
- Gli errori URL restano comunque ritentabili e non provocano più uno scarto definitivo immediato.
- L'aggiornamento WordPress rimette automaticamente in coda i job respinti dai precedenti difetti di lunghezza e URL.
- L'installer arresta il processo precedente, ricrea le attività pianificate e avvia automaticamente la versione appena installata.

## Gate obbligatori prima della consegna

1. lint PHP dell'intero plugin;
2. parsing Windows PowerShell 5.1 di tutti gli script;
3. test del trasporto form, degli errori HTTP e della credenziale DPAPI;
4. test del conteggio parole, della revisione dedicata del corpo e della rimozione URL;
5. test della migrazione che recupera i job editoriali respinti;
6. verifica delle versioni e degli archivi;
7. compilazione, installazione silenziosa, aggiornamento sopra un agente precedente e disinstallazione reale dell'installer;
8. controllo live di Core, News Engine, menu WordPress, collegamento dell'agente e avanzamento della coda.

Gli articoli restano in **Revisione editoriale** finché un redattore non li approva. L'installer non dispone ancora di firma Authenticode commerciale; Windows SmartScreen può mostrare un avviso al primo avvio.
