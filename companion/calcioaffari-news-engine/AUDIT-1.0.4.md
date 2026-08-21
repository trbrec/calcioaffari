# Audit CalcioAffari News Engine 1.0.4

## Problema osservato in produzione

Il backfill era stato acquisito dal 29/07/2026, ma la coda alternava gli ID tecnici dei job. Poiché gli archivi erano stati letti in ordine decrescente, gli ID più piccoli non corrispondevano alle notizie più vecchie: il recupero di luglio restava dietro centinaia di job di agosto.

Inoltre alcuni estratti RSS contenevano più operazioni. Il modello locale provava a riassumerle insieme e il revisore, correttamente, metteva il risultato in quarantena.

## Correzioni

- selezione alternata sulla data `published_at` della prova più recente/più vecchia;
- storia obbligatoriamente ancorata al titolo della prima fonte;
- nomi e operazioni estranee presenti nel digest devono essere ignorati anche nei metadati;
- quarantene senza post rimesse in coda una sola volta dopo la migrazione;
- capacità predefinita portata a 75 bozze al giorno, sempre in modalità revisione.

## Invarianti di sicurezza

- nessuna pubblicazione automatica viene abilitata;
- nessun contenuto esistente viene eliminato;
- i filtri di grounding, lingua, singola storia e prove restano bloccanti;
- la versione minima dell'app rimane 1.1.1.
