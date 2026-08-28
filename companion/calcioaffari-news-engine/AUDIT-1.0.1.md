# Audit CalcioAffari News Engine 1.0.1

Data: 21 agosto 2026

## Difetto riprodotto

Il pannello 1.0.0 mostrava `0 nuovi elementi` mentre le fonti pubblicavano nuove operazioni di mercato. L'audit live ha confermato quattro cause:

1. il cron, la cache RSS e il controllo effettuato dall'agente usavano dieci minuti, non i cinque richiesti;
2. le quattro fonti installate erano feed calcistici generici, con una sola testata centrata sul mercato italiano;
3. il filtro richiedeva formule rigide nel titolo e ignorava le categorie editoriali `Mercato`, `Transfer Market` e `Latest Transfers`;
4. un solo carattere arabo, cirillico o asiatico presente negli embed del corpo RSS scartava anche un articolo inglese o italiano valido.

Esempi osservati durante l'audit:

- Football Italia pubblicava `Banda signs for Al Swehly...`, respinto per un nome arabo contenuto nell'embed Instagram;
- BBC e Sky pubblicavano trasferimenti confermati, spesso respinti perché il sommario RSS era inferiore alla precedente soglia di 180 caratteri;
- Calciomercato.it pubblicava più operazioni nella categoria `Mercato`, ma non era installato;
- TuttomercatoWeb aggiornava il proprio feed più volte nell'ora, ma non era installato.

## Correzioni

- intervallo live, cache RSS e claim dell'agente impostati a cinque minuti;
- Calciomercato.it e TuttomercatoWeb aggiunti come fonti nazionali ad alta frequenza;
- categorie di mercato ammesse come segnale editoriale, mantenendo i blocchi per tennis, newsletter, live blog, tracker, roundup e titoli multi-operazione;
- caratteri estranei rimossi dall'estratto senza invalidare il titolo e il contenuto latino;
- soglia minima dell'estratto resa compatibile con i feed reali, lasciando obbligatori il controllo indipendente e gli estratti-prova;
- deduplicazione aggiuntiva per URL della fonte;
- clustering storico ancorato alla data originale della notizia;
- data WordPress derivata dalla fonte, così il recupero non altera la cronologia;
- backfill automatico e incrementale dal 29/07/2026 tramite gli archivi WordPress verificabili di Calciomercato.it e Football Italia;
- creazione della coda storica soltanto al termine dell'acquisizione, per permettere il raggruppamento tra fonti prima dell'elaborazione IA.

## Sicurezze preservate

- modalità predefinita e installata: `review`;
- nessuna pubblicazione automatica durante il backfill;
- una sola operazione per articolo;
- revisione locale indipendente obbligatoria;
- mappatura completa delle affermazioni e citazioni letterali obbligatorie;
- contenuti legacy 1.0.0 restano in quarantena e non vengono riabilitati automaticamente.
