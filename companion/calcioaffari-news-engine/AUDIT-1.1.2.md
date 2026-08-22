# Audit CalcioAffari News Engine 1.1.2

## Verifica sul ciclo reale

Il controllo dei primi articoli prodotti dalla coda completa ha evidenziato due difetti residui: un’attribuzione basata sul dominio poteva diventare la frase tronca “Secondo ,” e un sommario poteva reinterpretare la richiesta economica del club cedente come un’offerta del club interessato.

## Correzioni

- il nome editoriale di una testata che coincide con il dominio, per esempio `Calciomercato.it`, viene preservato come attribuzione leggibile;
- eventuali frammenti orfani “Secondo ,” provenienti da feed personalizzati vengono eliminati prima della pubblicazione;
- un sommario che introduce un’offerta assente dal corpo viene respinto dal controllo deterministico;
- il prompt vieta esplicitamente di trasformare la richiesta economica del club cedente in un’offerta del club interessato;
- roundup, doppie cessioni, liste di obiettivi e articoli su “due nomi” vengono bloccati: ogni Affare pubblico deve riguardare una sola operazione e un solo calciatore principale;
- formule da riempitivo come “fumata bianca” e “per le prossime ore” non superano il validatore;
- restano obbligatori il plurale idiomatico “le visite mediche”, gli articoli italiani davanti ai club e la qualificazione del calciatore quando ruolo e squadra sono presenti nelle prove;
- sono invariati estratti-prova letterali, mappatura claim/fonti, audit indipendente e blocco delle operazioni presentate come concluse senza conferma primaria.
