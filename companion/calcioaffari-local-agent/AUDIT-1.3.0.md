# Audit di rilascio — CalcioAffari Local Newsroom 1.3.0

## Correzione architetturale

- Il controllo leggero della coda WordPress avviene prima di qualsiasi avvio di Ollama.
- Una coda vuota non carica Qwen3 e aumenta progressivamente l'intervallo di polling.
- Qwen3 viene scaricato esplicitamente alla fine di ogni raffica e quando la coda torna vuota.
- Errori terminali, arresto dell'agente, Pausa e chiusura della GUI scaricano il modello.

## Protezione delle risorse

- Eco: tre thread, un job per raffica, cooldown 300 secondi, polling adattivo 300–900 secondi.
- Bilanciato: quattro thread, due job per raffica, cooldown 120 secondi, polling adattivo 60–300 secondi.
- Prestazioni: sei thread, cinque job per raffica, cooldown 30 secondi, polling adattivo 15–60 secondi.
- Eco e Bilanciato rinviano l'acquisizione del job se Windows rileva un carico GPU esterno oltre la soglia; nessun lease viene acquisito durante il rinvio.
- Eco e Bilanciato usano priorità di processo `BelowNormal`.

## Invarianti verificate

- Modello, prompt, schema, temperatura, contesto e regole editoriali non cambiano.
- Pairing, token e contratto della coda WordPress non cambiano.
- Pausa reale, scarico del modello e protezione dai cicli terminali restano attivi.
- L'app non modifica driver, firmware, tensioni, frequenze o impostazioni AMD.
