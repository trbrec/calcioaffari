# CalcioAffari

Codice proprietario di [calcioaffari.it](https://calcioaffari.it): tema WordPress e motore editoriale locale per il calciomercato mondiale.

## Componenti

- Tema `CalcioAffari` 0.7.0 nella radice del repository.
- Plugin `companion/calcioaffari-news-engine`: raccolta RSS/Atom, deduplicazione, corroborazione, coda editoriale, REST autenticata e pubblicazione governata.
- Applicazione Windows `companion/calcioaffari-local-agent` 1.0.9: configurazione completamente grafica, pannello di stato, autoripristino e agente Ollama sulla workstation, senza API IA a consumo.
- Plugin WordPress `companion/calcioaffari-news-engine` 0.8.7: fonti professionali, filtro preventivo, coda, validazione delle prove e pubblicazione in revisione editoriale.

## Flusso editoriale

1. WordPress interroga GDELT per la copertura mondiale e legge gli eventuali feed autorizzati aggiunti dal pannello.
2. Le notizie vengono filtrate, confrontate e raggruppate per evento.
3. Solo i gruppi che soddisfano le regole entrano nella coda dell'agente.
4. Il modello locale produce JSON strutturato con fonti per ogni affermazione.
5. WordPress applica limiti, controlli anti-copia e regole sull'ufficialità.
6. L'articolo viene salvato come bozza, in revisione oppure pubblicato in automatico secondo la configurazione.

Il sistema non copia immagini delle testate, non considera “ufficiale” un'indiscrezione e conserva i collegamenti alle fonti consultate.
