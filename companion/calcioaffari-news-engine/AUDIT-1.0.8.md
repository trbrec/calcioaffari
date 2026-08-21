# Audit CalcioAffari News Engine 1.0.8

## Difetto osservato

Il controllo live mostrava job elaborati correttamente e approvati dal secondo revisore locale, ma quasi tutti i post restavano in revisione. `post_status()` trattava allo stesso modo safety flag materiali e tre avvisi deterministici aggiunti dal plugin: lunghezza fuori target, prove sintetiche e rimozione di riferimenti tecnici.

## Correzione

- Gli avvisi deterministici restano salvati e visibili nel metabox editoriale.
- In pubblicazione automatica questi tre avvisi non bloccano più un articolo che ha già superato validazione PHP, minimo assoluto di 80 parole, mappatura claim-prove e audit locale indipendente.
- Qualsiasi flag sconosciuto, prodotto dal modello o relativo a fatti non supportati continua a impedire la pubblicazione automatica.
- I test distinguono esplicitamente avvisi editoriali e flag bloccanti.

## Risultato atteso

La coda storica può produrre articoli online senza intervento manuale quando il contenuto è fondato ma breve, mentre incongruenze, storie multiple e affermazioni non provate restano in quarantena.
