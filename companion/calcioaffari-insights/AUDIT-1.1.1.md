# Audit CalcioAffari Insights 1.1.1

- La migrazione dei contenuti gestiti viene eseguita su `init`, dopo
  l'inizializzazione completa di WordPress, e non più su `plugins_loaded`.
- La correzione evita il fatal `Undefined constant WP_POST_REVISIONS` rilevato
  su WordPress 7.1 durante l'aggiornamento della Cookie Policy.
- Statistiche, monitoraggio H24, pagina Account e preferenze squadra restano
  invariati rispetto alla 1.1.0.
- La versione degli asset Account è allineata alla release 1.1.1.
- Se l'impostazione dell'alert è vuota, il monitor usa l'email amministrativa
  già configurata in WordPress; l'alert non resta silenziosamente disattivato.
