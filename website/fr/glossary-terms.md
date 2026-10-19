<!-- Terminology decisions of the French translation. Maintained by the translator-fr agent;
     not a site page (excluded in website/site.lua). Source: docs/glossary.md. -->

# Décisions terminologiques (français)

Règle : l’identifiant de code reste en anglais, en police de code. En prose, le terme français
est donné suivi du terme anglais entre parenthèses et en italique à la première occurrence d’une
page (avec un lien vers le glossaire), puis le terme français seul.

| Terme anglais | Terme français | Remarque |
|---|---|---|
| coroutine | coroutine | |
| reactor | réacteur | « reactor » dans `hecate.reactor`, `reactor.run` (identifiants) |
| future | future (féminin) | |
| fork | `fork` ; « démarrer une coroutine avec `fork` » | verbe de l’API, gardé tel quel |
| spawn | `spawn` ; « lancer / démarrer un processus » | jamais pour une coroutine |
| join | `join` | |
| select | `select` | |
| deadline | échéance | `reactor.deadline`, `handshake_deadline` en code |
| timeout | délai | durée relative |
| stream | flux | |
| back-pressure | contre-pression | |
| half-close | fermeture partielle | |
| primary | primaire | |
| worker | worker | emprunt usuel, gardé en anglais |
| message pipe | tube de messages | « pipe » seul : tube ; « named pipe » : tube nommé |
| listening strategy | stratégie d’écoute | |
| cancellation | annulation | |
| scope | portée | `reactor.scope` en code |
| channel | canal | |
| semaphore, monitor | sémaphore, moniteur | |
| handshake | poignée de main | TLS ; `handshake_deadline` en code |
| callback | rappel | |
| buffer, buffered | tampon, tamponné | |
| poisoned writer | écrivain empoisonné | |
| reader, writer | lecteur, écrivain | classes `BufferedReader`, `BufferedWriter` en code |
| listener | écouteur | |
| peer | pair | classe `Peer` en code |
| trust store, trust anchor | magasin de confiance, ancre de confiance | |
| tuple | n-uplet | |
| identity map | table d’identités | |
| repository | dépôt | |
| refinement type | type raffiné | |
| unit of work | unité de travail | |
| data mapper | data mapper | |
| container | conteneur | |
| filter | filtre | |
| composition root | racine de composition | |
| value object | objet-valeur | |
