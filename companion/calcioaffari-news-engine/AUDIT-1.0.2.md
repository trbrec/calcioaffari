# Audit CalcioAffari News Engine 1.0.2

Data: 21 agosto 2026

## Difetto osservato sul ciclo reale

La raccolta 1.0.1 ha acquisito correttamente 729 elementi dal 29/07 e creato la coda storica, ma Qwen ha messo in quarantena le prime bozze perché aggiungeva formule non presenti nelle prove, tra cui “sviluppi attesi”, “situazione in divenire” e deduzioni sull’effetto di una trattativa su un’altra.

## Correzione

- obiettivo di lunghezza proporzionato alle parole realmente disponibili nelle prove;
- ogni periodo deve essere riconducibile a una frase precisa della fonte;
- divieto esplicito di previsioni, chiusure generiche, conseguenze ipotetiche e contesto esterno;
- recupero automatico dei job senza articolo respinti dal prompt precedente;
- revisione indipendente, citazioni-prova e modalità `review` restano obbligatorie.
