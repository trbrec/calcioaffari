# Audit di rilascio — CalcioAffari Local Newsroom 1.2.1

## Trasporto SiteGround

SiteGround ha confermato nel ticket 5118970 che il firewall blocca le richieste
automatizzate originate da un processo PowerShell. La disattivazione della
regola avrebbe consentito tutte le richieste PowerShell al sito ed è stata
respinta.

La 1.2.1 usa `curl.exe`, incluso nelle versioni Windows supportate, come client
HTTP. La configurazione contenente header e corpo form già URL-encoded viene
inviata a cURL tramite standard input: pairing token e payload non compaiono
negli argomenti del processo, nei log o in file temporanei. La pre-codifica
impedisce al parser della configurazione di alterare il JSON annidato. Restano
invariati token applicativo, TLS, timeout, convalida JSON,
classificazione degli errori e controlli di compatibilità.

## Verifiche

- round-trip UTF-8 di form autenticato, JSON annidato e metadati HTTP;
- integrità del lease token e di un payload editoriale grande in PowerShell 7
  e Windows PowerShell 5.1;
- ciclo reale staging claim, elaborazione, audit e complete al primo tentativo;
- assenza del segreto dalla riga di comando di cURL;
- timeout e errori di rete restano retryable;
- risposte HTML/202/403 e endpoint mancanti restano bloccanti;
- profili Eco, Bilanciato e Prestazioni non cambiano il contratto editoriale;
- aggiornamento preserva configurazione, pairing cifrato e diagnostica.
