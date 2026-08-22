# Audit CalcioAffari News Engine 1.1.0

## Continuità H24

- Aggiunto endpoint autenticato `ca_news_heartbeat` per il segnale indipendente della workstation.
- Salvati soltanto ora UTC e versione applicazione; nessun dato personale aggiuntivo.
- Lo stato salute espone ultimo heartbeat e versione per diagnosi amministrativa.
- Il minimo editoriale dell'app resta 1.1.2: la 1.1.3 aggiunge stabilità operativa senza invalidare il controllo grounding già verificato.

Backfill, alternanza archivio/live, revisione editoriale e filtri di pertinenza restano invariati.
