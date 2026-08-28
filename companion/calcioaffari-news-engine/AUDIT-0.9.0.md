# Audit editoriale — CalcioAffari News Engine 0.9.0

## Anomalia osservata

Dopo il reset integrale della pipeline, la prima raccolta pulita ha creato 13 job. Dodici titoli descrivevano trasferimenti, accordi, prestiti, visite mediche o uscite contrattuali. Il job #13, “Carra meets Iraola! Liverpool boss on playing style, transfers & Newcastle”, era invece un'intervista generica: la sola parola `transfers` aveva superato il filtro 0.8.9.

Il job non è stato assegnato all'app locale, trasformato in articolo o pubblicato.

## Correzione

- Le parole inglesi isolate `transfer` e `transfers` non sono più sufficienti per ammettere un titolo.
- Restano validi `transfer market`, `transfer rumour(s)` e tutti i segnali espliciti già coperti: firma, accordo, offerta, prestito, ingresso, uscita, corsa, visite mediche e risoluzione contrattuale.
- Restano validi i titoli che collegano esplicitamente `transfer` a verbi conclusivi come complete, confirm, announce, seal e agree.
- La migrazione 0.9.0 rivalida automaticamente tutti i job aperti e azzera eventuali lease prima dell'applicazione del nuovo filtro.

## Regressioni incluse

- Il falso positivo reale del job #13 è incluso nel gate CI e deve essere respinto.
- I dodici titoli pertinenti della raccolta pulita restano coperti dalle famiglie di segnali ammesse.
- I casi reali già verificati nelle release precedenti restano accettati: corse di mercato, risoluzioni contrattuali, accordi, prestiti e visite mediche.
- GDELT resta sospeso e la pubblicazione resta in modalità Revisione editoriale.
