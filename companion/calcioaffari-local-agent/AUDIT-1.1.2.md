# Audit di stabilità — CalcioAffari Local Newsroom 1.1.2

## Esito

La 1.1.2 coordina la lunghezza del lancio con le prove ricevute dal plugin 1.0.9.

- Minimo assoluto configurato dal server: 45 parole, limitato localmente nell'intervallo sicuro 30-80.
- Target 160-360 invariato come obiettivo editoriale.
- Il preflight e le due riscritture guidate usano lo stesso minimo comunicato dal server.
- Il modello viene istruito a fermarsi quando esaurisce i fatti dimostrabili.
- L'audit indipendente resta obbligatorio: fatti inventati, storie multiple, lingua o grammatica non valide continuano a mettere il job in quarantena.
- Launcher invisibile, watchdog, cifratura del codice, upgrade e disinstallazione restano invariati rispetto alla 1.1.1.

## Regressioni coperte

- Un lancio verificato di 45-79 parole non viene espanso artificialmente.
- Un testo sotto il minimo assoluto viene ancora riscritto o quarantinato.
- Le segnalazioni materiali e gli estratti-prova non verificabili restano bloccanti.
