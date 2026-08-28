# Audit editoriale — CalcioAffari News Engine 1.0.0

## Esito

La versione 1.0.0 chiude i difetti osservati nel primo ciclo reale: articoli multi-notizia, attribuzioni generiche, cifre corrotte e affermazioni dichiarate come supportate senza una prova testuale verificabile.

## Barriere introdotte

- rifiuto preventivo di live blog, tracker, raccolte di indiscrezioni, doppi colpi e altri feed aggregati;
- app minima 1.1.0 e revisione editoriale indipendente obbligatoria;
- ogni claim deve essere una frase rintracciabile nell'articolo;
- ogni fonte dichiarata deve avere un estratto letterale presente nel titolo o nell'estratto RSS della stessa fonte;
- `source_ids` deve coincidere esattamente con l'unione delle fonti usate nei claim;
- safety flag bloccanti, sottotitoli nei brevi e attribuzioni generiche causano quarantena, non la creazione di un post;
- nomi delle testate preservati per un'attribuzione trasparente; URL, domini e ID tecnici restano esclusi dal testo.

## Migrazione

Le bozze legacy ancora in attesa e prive del nuovo audit vengono spostate in **Bozza**, marcate come quarantena e collegate al job respinto. La procedura è reversibile e non modifica automaticamente eventuali articoli già pubblicati. Tutta la coda aperta viene rivalidata con il nuovo filtro.

## Modalità operativa

L'aggiornamento non abilita la pubblicazione automatica. La modalità resta **Revisione editoriale** finché un campione reale non supera l'audit umano.
