---
description: Définir les limites, les délais et les options TLS de hecate.http.Server, lire les valeurs par défaut, et configurer la confiance TLS de hecate.http.Client.
hecate: "0.x"
lua: "5.5"
order: 12
source_revision: 127cb3d2f023c24467492b8959dd7bc7bc0390d7
---

# Définir les limites, les délais et TLS du serveur HTTP

Ce guide montre comment resserrer ou relâcher les bornes de `http.Server`, et comment servir et appeler du HTTPS. Il
est écrit pour hecate 0.x et Lua 5.5, et suppose que vous savez [servir du HTTP](serve-http.md).

Chaque limite est une option du serveur, et chaque option a une valeur par défaut, si bien qu’un serveur n’est
jamais non borné par accident. Cette page est aussi la liste de toutes les limites. Pour les raisons des valeurs,
lisez [Le modèle HTTP](../explanation/http-model.md#why-these-defaults).

## Définir les limites {#set-limits}

Passez les options à la création du serveur. Les limites de l’analyseur vont dans la table `parser`.

<!-- example: packages/http/examples/hecate.http.Server.limits.lua -->
```lua
-- Limits, as options. A server that accepts 16 bytes of content refuses a
-- larger request with a 413 before the action runs, and the parser limits
-- go in the `parser` table.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local ran = false
local function action()
  ran = true
  return http.Response(200, { content = "ok" })
end

reactor.run(function()
  local server = http.Server(action, {
    port = 0,
    max_content = 16,
    head_timeout = 5,
    idle_timeout = 30,
    max_connections = 100,
    parser = { max_fields = 20 },
  })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local url = "http://127.0.0.1:" .. listener:local_address().port .. "/"
  local client <close> = http.Client()
  local small = client:post(url, "0123456789")
  print(small.status .. " " .. small:read_content())
  -- Prints: 200 ok
  ran = false
  local large = client:post(url, ("x"):rep(17))
  print(large.status .. " " .. large.fields:get("Content-Type") .. " " .. tostring(ran))
  -- Prints: 413 application/problem+json false
  server:shutdown()
  reactor.join(serving)
end)
```

Une option inconnue, ou une valeur hors plage, lève une `ArgumentError` à la création du serveur.
`http.Server.DEFAULTS` contient les valeurs que le serveur applique.

Une limite dépassée reçoit en réponse des [détails de problème](../reference/glossary.md#http) (*problem details*),
et la connexion se ferme, sauf là où le tableau dit autre chose. Plusieurs limites s’appliquent à la
[tête](../reference/glossary.md#http) (*head*) d’une requête : sa ligne de départ et ses champs.

| Limite | Option | Défaut | Quand elle est dépassée |
|---|---|---|---|
| Cible de la requête | `parser.max_target_size` | 8192 octets | 414 |
| Un nom ou une valeur de champ | `parser.max_field_size` | 8192 octets | 431 |
| Champs dans une tête | `parser.max_fields` | 100 | 431 |
| Octets bruts d’une tête | `parser.max_head_size` | 65536 octets | 431 |
| Contenu de la requête | `max_content` | 1048576 octets | 413 |
| Tête, de son premier octet à sa fin | `head_timeout` | 60 s | 408 |
| Attente de la requête suivante | `idle_timeout` | 75 s | fermée sans réponse |
| Entre deux lectures de contenu | `content_timeout` | 60 s | 408 |
| De la fin de la tête au dernier octet du contenu | `request_timeout` | 300 s | 408 |
| Purge du contenu non lu après la réponse | `drain_timeout` | 5 s | la connexion se ferme |
| Une écriture vers le client | `write_timeout` | 60 s | la connexion se ferme |
| Connexions servies en même temps | `max_connections` | aucune | l’excédent attend dans le backlog (il n’y a pas de 503 : une fois le backlog plein, les clients suivants dépassent leur délai) |
| Connexions en attente dans le noyau | `backlog` | 128 | le noyau refuse |

> [!WARNING] `max_connections` n’a pas de limite par défaut
> La limite de descripteurs du processus, `idle_timeout` et `head_timeout` bornent la ressource. Un serveur exposé à
> Internet devrait la fixer : environ 80 pour cent de la limite de descripteurs, par exemple 50000 avec
> `ulimit -n 65536`. Relevez aussi la limite de descripteurs (`ulimit -n`, ou `LimitNOFILE` dans systemd).

### Choisir les valeurs {#choose-the-values}

- `head_timeout` est une [échéance](../reference/glossary.md#concurrency) (*deadline*) sur toute la tête. Des octets
  qui continuent d’arriver ne la prolongent pas. C’est ce qui arrête un client qui envoie un octet par intervalle.
- `content_timeout` est un délai entre lectures, si bien qu’un téléversement lent mais régulier n’est pas coupé. Le
  temps total d’un corps est borné par `request_timeout`. Relevez-le pour des téléversements qui durent
  légitimement plus de cinq minutes.
- Derrière un proxy inverse, donnez au proxy un délai keep-alive amont plus court que `idle_timeout`.
- Le [pipelining](../reference/glossary.md#http) ne demande aucune option. Le serveur lit au plus 16 Kio à la fois,
  et seulement après avoir répondu à toutes les requêtes déjà analysées.

## Échéance pour une action {#deadline-for-an-action}

Le serveur n’a pas de délai par requête pour l’action. Bornez l’action de l’intérieur, avec `reactor.deadline` :

```lua
local function action(request)
  return reactor.deadline(5, function()
    return http.Response(200, { content = slow_lookup(request.path) })
  end)
end
```

Quand l’échéance expire, `reactor.deadline` lève `DeadlineExceededError`, et le serveur répond par un 500
générique. Attrapez l’erreur vous-même pour répondre 503 à la place.

## TLS {#tls}

Passez l’option `tls` pour servir du HTTPS. Elle prend les options de `net.tls.server_config`, ou une configuration
construite par cette fonction. La liste des protocoles ALPN vaut `http/1.1` par défaut. TLS a besoin du module natif
TLS de `hecate.net` (`lua tools/run.lua build-native net`).

L’exemple sert du HTTPS avec les clés jetables des tests de `net`, et l’appelle avec un client qui fait confiance à
leur autorité. Utilisez votre propre certificat et votre propre clé.

<!-- example: packages/http/examples/hecate.http.Server.tls.lua -->
```lua
-- Serve HTTPS with the throwaway keys of the net tests (use your own
-- certificate and key) and call it with a client that trusts their CA.
-- The paths are relative to the root of the repository.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function read(name)
  local file = assert(io.open("packages/net/tests/fixtures/" .. name, "rb"))
  local text = file:read("a")
  file:close()
  return text
end

local function action() return http.Response(200, { content = "secure" }) end

reactor.run(function()
  local server = http.Server(action, { port = 0, tls = { cert_pem = read("server.pem"), key_pem = read("server.key") } })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local client <close> = http.Client({ tls = { ca_pem = read("ca.pem"), system_roots = false } })
  print(client:get("https://127.0.0.1:" .. listener:local_address().port .. "/"):read_content())
  -- Prints: secure
  server:shutdown()
  reactor.join(serving)
end)
```

### Un certificat pour le travail en local {#a-certificate-for-local-work}

Pour fabriquer un certificat pour le travail en local, exécutez :

```sh
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 \
  -keyout server.key -out server.pem -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
```

Ensuite `curl --cacert server.pem https://localhost:8443/` lui fait confiance.

Un client qui ne connaît pas l’autorité refuse le certificat. `http.Client()` avec le seul magasin du système, par
exemple, lève une `net.TlsError` dont `context.reason` vaut `untrusted_issuer`. Il n’existe aucune option pour sauter
la vérification.

### Borner les poignées de main {#bound-the-handshakes}

Chaque connexion acceptée exécute sa poignée de main (*handshake*) dans son propre calcul, jamais dans la boucle
d’acceptation. Un client qui reste silencieux ne retient que sa propre place. Trois options bornent les poignées de
main, et elles demandent `tls` :

| Option | Défaut | Borne |
|---|---|---|
| `handshake_timeout` | 10 s | la durée d’une poignée de main (la connexion est abandonnée) |
| `max_handshakes` | 64 | les poignées de main en cours en même temps (l’excédent attend dans le backlog) |
| `max_handshake_bytes` | 65536 | les octets lus d’un client avant la fin de la poignée de main |

Une poignée de main échouée n’envoie rien au client. Le journaliseur (l’option `logger`, ou `log.default()`) reçoit
`http.Server: TLS handshake failed`, avec l’adresse du pair et la classe de la raison. Rien d’autre ne sort du
serveur. Pour les certificats clients et ALPN, voir [Client et serveur TLS](tls-client-and-server.md).

### Le client {#the-client}

`http.Client` fait confiance au magasin du système, et la vérification ne peut pas être désactivée (voir
[Confiance TLS et valeurs par défaut de sécurité](../explanation/tls-trust-and-security.md)). L’option `tls` du
client s’ajoute à cette confiance :

```lua
local client = http.Client({
  tls = { ca_pem = read("ca.pem"), system_roots = false, cert_pem = read("client.pem"), key_pem = read("client.key") },
})
```

- `ca_pem` ajoute une ancre de confiance, pour une autorité privée.
- `system_roots = false` ne fait confiance qu’à `ca_pem`.
- `cert_pem` et `key_pem` présentent un certificat client.

Le `connect_timeout` du client couvre aussi la poignée de main TLS.

## Voir aussi {#see-also}

- [Servir du HTTP](serve-http.md)
- [Utiliser le client HTTP](use-the-http-client.md)
- [Le modèle HTTP](../explanation/http-model.md)
