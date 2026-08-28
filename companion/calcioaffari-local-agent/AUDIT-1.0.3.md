# Audit di stabilità — CalcioAffari Local Newsroom 1.0.3

## Incidente analizzato

Il collegamento tra workstation, Ollama e WordPress era operativo, ma 24 risultati consecutivi sono stati respinti dal plugin con HTTP 400. La diagnostica WordPress ha confermato una sola causa comune: **“Sommario assente o fuori lunghezza.”**

## Correzioni

- Lo schema inviato a Qwen3 impone ora un titolo tra 20 e 145 caratteri e un sommario tra 80 e 280 caratteri.
- Il prompt editoriale ripete esplicitamente il vincolo sul sommario.
- WordPress normalizza in modo deterministico un sommario troppo breve o troppo lungo usando esclusivamente il corpo già validato dell'articolo.
- La coda WordPress dispone dell'azione **Riprova tutte le respinte**, protetta da permessi amministrativi e nonce.
- Il client Windows decodifica codice e messaggio degli errori JSON restituiti da WordPress; i log non mostrano più soltanto “HTTP 400”.
- La rimozione dei codici di collegamento dai log e dagli archivi diagnostici resta attiva.

## Verifiche di rilascio

1. lint PHP completo;
2. test di normalizzazione dei sommari corti e lunghi;
3. controllo dei vincoli nello schema Qwen3;
4. test del dettaglio degli errori HTTP WordPress;
5. parsing degli script su Windows PowerShell 5.1;
6. test del trasporto form e della credenziale DPAPI;
7. compilazione reale, installazione silenziosa e disinstallazione dell'installer Windows;
8. verifica degli archivi e degli hash SHA-256.

## Sicurezza e pubblicazione

La normalizzazione non aggiunge informazioni esterne e non aggira i controlli su fonti, affermazioni, URL, plagio, lunghezza del corpo o modalità di pubblicazione. Gli articoli restano in **Revisione editoriale** finché un redattore non li approva.

L'installer non dispone ancora di firma Authenticode commerciale; Windows SmartScreen può mostrare un avviso al primo avvio.
