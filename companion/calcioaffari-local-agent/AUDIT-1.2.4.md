# Audit di rilascio — CalcioAffari Local Newsroom 1.2.4

## Arresto reale e consumo risorse

- La GUI espone un comando **Pausa/Riprendi** reale.
- La pausa crea uno stato persistente, arresta e disabilita sia l'agente sia
  il watchdog, termina soltanto i processi PowerShell appartenenti a
  CalcioAffari e scarica `qwen3:14b` tramite `ollama stop`.
- Il watchdog controlla lo stato di pausa prima di contattare WordPress e non
  può riavviare l'agente mentre l'utente lo ha sospeso.
- La chiusura della finestra mette automaticamente in pausa l'elaborazione:
  nessun processo IA continua a pieno regime dopo la chiusura.
- **Riprendi** riabilita le attività e avvia l'agente senza perdere pairing,
  credenziale cifrata o coda WordPress.
- Un aggiornamento preserva una pausa già impostata.

## Profili ottimizzati

- Eco: polling 120 secondi, 4 thread, modello scaricato subito dopo il lavoro.
- Bilanciato: polling 45 secondi, massimo 6 thread, keep-alive 2 minuti.
- Prestazioni: polling 15 secondi, thread automatici, keep-alive 10 minuti.

## Protezioni mantenute

- Il circuito anti-loop della 1.2.3 resta attivo.
- Nessuna soglia editoriale, fonte, contenuto o modalità WordPress viene
  modificata dall'applicazione.
- La pausa non disinstalla Ollama né elimina il modello.
