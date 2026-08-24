# Audit di rilascio — CalcioAffari Local Newsroom 1.2.0

## Ambito

La release 1.2.0 consolida i profili Eco, Bilanciato e Prestazioni senza
modificare il contratto editoriale. I profili cambiano soltanto cadenza,
keep-alive, limite dei thread e priorità del processo; modello, prompt, schema,
seed, controlli di grounding e singolo worker restano identici.

## Affidabilità verificata

- avvio, watchdog, diagnostica, riparazione e disinstallazione non aprono
  finestre PowerShell;
- una lease scaduta torna in coda e un risultato tardivo viene respinto;
- rete assente e Ollama fermo producono retry limitati e recuperabili;
- versioni dell'agente precedenti alla minima sono bloccate prima del claim;
- installazione pulita, aggiornamento, conservazione della configurazione e
  disinstallazione sono qualificati in un percorso Windows isolato;
- i profili producono lo stesso output editoriale sul benchmark reale
  `qwen3:14b`.

La pubblicazione automatica non viene abilitata: l'app opera con il sito in
modalità `review`.
