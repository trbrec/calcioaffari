# Audit CalcioAffari News Engine 1.0.9

## Obiettivo

Sbloccare i lanci di mercato sostenuti da prove brevi senza ridurre i controlli su pertinenza, singola operazione, nomi, cifre, ufficialità e grounding.

## Correzioni

- Il minimo assoluto diventa 45 parole; 160-360 resta il target editoriale.
- Il prompt adatta la lunghezza alla quantità reale di prove e vieta esplicitamente di aggiungere riempitivi.
- La 1.1.2 dell'app riceve dal plugin il minimo assoluto effettivo.
- Le quarantene prodotte dal precedente vincolo vengono rimesse in coda soltanto quando si collega l'app 1.1.2.
- Il pannello mostra separatamente gli ultimi dieci errori editoriali, senza farli sparire dietro i job pending aggiornati dal refresh.

## Vincoli invariati

- Nessun articolo sotto 45 parole.
- Nessun articolo senza estratti-prova verificabili.
- Audit indipendente obbligatorio e bloccante su fatti non sostenuti.
- Divieto di unire più operazioni o inventare club, cifre, date e ufficialità.
- Gli avvisi non materiali possono accompagnare la pubblicazione; ogni safety flag sconosciuto resta bloccante.
