# Audit di stabilità — CalcioAffari Local Newsroom 1.1.3

## Correzione principale

Il watchdog non rilancia più direttamente l'agente completo ogni cinque minuti. Esegue `heartbeat.ps1` tramite Windows Script Host senza console visibile. Lo script invia al sito un segnale indipendente, controlla che l'agente principale sia attivo e lo riavvia soltanto se manca.

Questo separa due stati diversi:

- PC/app disponibili, anche mentre Qwen elabora a lungo;
- workstation realmente spenta, scollegata o con applicazione rimossa.

L'alert email WordPress può quindi attribuire correttamente un arresto alla workstation senza falsi positivi causati da una generazione IA lunga. Installazione, riparazione e aggiornamento registrano entrambe le attività con il launcher invisibile.
