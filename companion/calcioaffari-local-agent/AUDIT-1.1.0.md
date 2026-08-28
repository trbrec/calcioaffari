# Audit di stabilità — CalcioAffari Local Newsroom 1.1.0

## Obiettivo

La 1.1.0 introduce un confine editoriale fail-closed: una notizia non viene inviata a WordPress se non supera sia i controlli deterministici sia una seconda revisione locale indipendente basata sulle stesse prove.

## Controlli bloccanti

- un solo fatto di mercato per articolo;
- titolo e corpo in italiano naturale, senza sottotitoli nei brevi di agenzia;
- nessuna attribuzione generica o frase corrotta;
- nessun safety flag relativo a prove insufficienti, fatti inventati o mappatura incompleta;
- revisione indipendente con esito positivo su lingua, grammatica, singola storia e grounding;
- una sola nuova stesura in caso di errore; al secondo fallimento il job viene messo in quarantena e nessun post viene creato.

## Stabilità Windows

L'agente e il watchdog continuano a partire tramite WScript in modalità invisibile. Non vengono aperte finestre PowerShell durante i controlli pianificati. Log, diagnostica esportabile, credenziale DPAPI e ripartenza automatica restano invariati.

## Compatibilità

Richiede CalcioAffari News Engine 1.0.0. Il funzionamento resta in modalità **Revisione editoriale**; l'autopubblicazione non viene abilitata dall'aggiornamento.
