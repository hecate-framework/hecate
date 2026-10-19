---
description: Ouvrir des connexions TLS avec le magasin de confiance du système ou une autorité privée, servir en TLS avec l’acceptation en deux temps, négocier ALPN, exiger des certificats clients et lire les erreurs TLS.
hecate: "0.x"
lua: "5.5"
order: 2
source_revision: f1f3b5e
---

# Client et serveur TLS

Ce guide montre comment utiliser TLS avec `hecate.net` : un client qui vérifie un serveur, un
serveur qui accepte des clients, et les erreurs que vous pouvez rencontrer. Il est écrit pour
hecate 0.x et Lua 5.5. Il suppose que vous savez
[vous connecter et servir en TCP](connect-and-serve-over-tcp.md).

TLS est fourni par [rustls](https://github.com/rustls/rustls) dans un module natif. Compilez-le
une fois avec `lua tools/run.lua build-native`. Sans lui, `net.tls.available()` renvoie `false`
et la raison, et chaque appel TLS lève `TlsError` avec `context.reason` valant
`"native_missing"`.

::: warning La vérification ne peut pas être désactivée
Aucune option ne désactive la vérification des certificats, et aucune ne sera ajoutée. Une option
mal orthographiée ou dangereuse comme `verify = false` lève `ArgumentError`. Voir
[Confiance TLS et valeurs par défaut de sécurité](../explanation/tls-trust-and-security.md) pour
les raisons.
:::

## Se connecter à un serveur public

Sans option, `net.connect_tls` vérifie le certificat du serveur avec le magasin de confiance du
système d’exploitation. Un serveur public fonctionne tel quel.

```lua
local stream <close> = net.connect_tls("example.org", 443, { alpn = { "http/1.1" } })
```

L’hôte est aussi le nom du serveur : il est envoyé comme SNI (Server Name Indication, RFC 6066),
et le certificat doit lui correspondre (RFC 6125). Passez `server_name` quand vous vous
connectez à une adresse mais que le certificat nomme un hôte.

## Faire confiance à une autorité de certification privée

Utilisez `ca_pem` pour ajouter les ancres de confiance de votre propre autorité à celles du
système. Ajoutez `system_roots = false` pour ne faire confiance qu’à `ca_pem`. Vous obtenez un
ensemble de confiance fermé, qui est aussi celui qu’emploient les tests de hecate.

<!-- example: packages/net/examples/hecate.net.connect_tls.lua -->
```lua
-- A TLS client against a local server whose certificate comes from the test CA of this package.
-- With no option, `connect_tls` verifies the server against the operating system's trust store;
-- here `ca_pem` names the private CA and `system_roots = false` trusts nothing else. Verification
-- cannot be disabled. Needs the native TLS module (`lua tools/run.lua build-native`).
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local function fixture(name)
  local file = assert(io.open(here .. "/../tests/fixtures/" .. name, "rb"))
  local pem = file:read("a")
  file:close()
  return pem
end

reactor.run(function()
  local config = net.tls.server_config({ cert_pem = fixture("server.pem"), key_pem = fixture("server.key") })
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local peer <close> = net.tls.accept(listener:accept(), config)
    local reader, writer = peer:reader(), peer:writer()
    writer:write("secure " .. reader:read_line() .. "\n")
    writer:flush()
    peer:read() -- until the client's close_notify: the end of the conversation
  end)
  local client <close> = net.connect_tls("localhost", listener:local_address().port, {
    family = "inet", ca_pem = fixture("ca.pem"), system_roots = false,
  })
  local reader, writer = client:reader(), client:writer()
  writer:write("hello\n")
  writer:flush()
  print(reader:read_line())
  client:shutdown() -- close_notify: a clean end, not a truncation
end)
-- Prints: secure hello
```

`system_roots = false` exige `ca_pem`. Le client termine la conversation avec `shutdown()`, qui
envoie `close_notify`. Voir [Fermer un flux TLS](#close-a-tls-stream).

Pour vous connecter plusieurs fois avec les mêmes options, construisez la configuration une fois
avec `net.tls.client_config(options)` et passez-la comme `tls_config`. Elle exclut les autres
options TLS. Sans elle, `connect_tls` construit une configuration à chaque appel. Le chargement
du magasin du système est la partie coûteuse : mettez-la en cache quand vous vous connectez
souvent.

## Servir en TLS

Un serveur construit d’abord une configuration à partir de sa chaîne de certificats et de sa
clé :

```lua
local config = net.tls.server_config({ cert_pem = chain, key_pem = key })
```

Puis il accepte les connexions en deux temps, volontairement :

```lua
local peer = net.tls.accept(listener:accept(), config)
```

`listener:accept()` renvoie le flux TCP. `tls.accept` exécute la poignée de main (*handshake*) de
cette seule connexion et prend possession du flux : si la poignée de main échoue, le flux est
fermé.

::: tip Démarrer la poignée de main dans une coroutine
N’exécutez jamais la poignée de main dans la boucle d’acceptation elle-même. Un client qui se
connecte puis ne dit rien bloquerait tous les autres. Démarrez une coroutine par connexion avec
`fork` et exécutez-y `tls.accept`. La poignée de main est de toute façon bornée par
`handshake_deadline`, qui vaut 10 secondes par défaut. Passez `{ handshake_deadline = 5 }` comme
troisième argument pour la changer. À l’expiration, le flux est fermé et
`DeadlineExceededError` est levée.
:::

L’exemple ci-dessous négocie un protocole applicatif avec ALPN (Application-Layer Protocol
Negotiation, RFC 7301). Le serveur propose `echo` ; le client le demande ; chaque côté lit le
résultat avec `stream:alpn()`.

<!-- example: packages/net/examples/hecate.net.tls.accept.lua -->
```lua
-- The server side of TLS, in the two-step form that is the idiom: accept the TCP connection,
-- then run the handshake of that one connection. A server forks the handshake per connection
-- (inside `reactor.deadline`) so that one silent client cannot stall the accept loop; this
-- example handles a single connection inline. Needs the native TLS module
-- (`lua tools/run.lua build-native`).
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local function fixture(name)
  local file = assert(io.open(here .. "/../tests/fixtures/" .. name, "rb"))
  local pem = file:read("a")
  file:close()
  return pem
end

reactor.run(function()
  local config = net.tls.server_config({
    cert_pem = fixture("server.pem"), key_pem = fixture("server.key"), alpn = { "echo" },
  })
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local peer <close> = net.tls.accept(listener:accept(), config)
    local line = peer:reader():read_line()
    peer:write(("%s over %s\n"):format(line, peer:alpn()))
    peer:read() -- until the client's close_notify: the end of the conversation
  end)
  local client <close> = net.connect_tls("localhost", listener:local_address().port, {
    family = "inet", ca_pem = fixture("ca.pem"), system_roots = false, alpn = { "echo" },
  })
  client:write("hello\n")
  print(client:reader():read_line())
  client:shutdown() -- close_notify: a clean end, not a truncation
end)
-- Prints: hello over echo
```

Un serveur peut lire le nom demandé par un client avec `stream:requested_server_name()`. Il ne
choisit pas de certificat d’après ce nom : il y a une seule chaîne de certificats par
configuration.

## Exiger des certificats clients

Le TLS mutuel demande au client de prouver son identité. Côté serveur, passez `client_ca_pem` :
l’autorité qui a signé les certificats clients. Les clients ont alors besoin de `cert_pem` et de
`key_pem`.

L’exemple démarre la poignée de main de chaque connexion dans sa propre coroutine, la borne avec
`handshake_deadline` et exige un certificat client.

<!-- example: packages/net/examples/hecate.net.tls.server_config.lua -->
```lua
-- A TLS server that requires client certificates (mutual TLS). `client_ca_pem` names the
-- authority that signed the client certificates. The accept loop forks the handshake of each
-- connection and bounds it with `handshake_deadline`, so that one silent client cannot stall it.
-- Needs the native TLS module (`lua tools/run.lua build-native`).
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local function fixture(name)
  local file = assert(io.open(here .. "/../tests/fixtures/" .. name, "rb"))
  local pem = file:read("a")
  file:close()
  return pem
end

reactor.run(function()
  local config = net.tls.server_config({
    cert_pem = fixture("server.pem"), key_pem = fixture("server.key"), client_ca_pem = fixture("ca.pem"),
  })
  local listener <close> = net.listen("127.0.0.1", 0)
  local acceptor = reactor.fork(function()
    while true do
      local connection = listener:accept()
      reactor.fork(function()
        -- The handshake owns `connection`: it is closed if the handshake fails.
        local ok, peer = pcall(net.tls.accept, connection, config, { handshake_deadline = 5 })
        if not ok then return end
        local reader, writer = peer:reader(), peer:writer()
        writer:write("welcome " .. reader:read_line() .. "\n")
        writer:flush()
        peer:read() -- until the client's close_notify
        peer:close()
      end)
    end
  end)
  local client <close> = net.connect_tls("localhost", listener:local_address().port, {
    family = "inet", ca_pem = fixture("ca.pem"), system_roots = false,
    cert_pem = fixture("client.pem"), key_pem = fixture("client.key"),
  })
  local reader, writer = client:reader(), client:writer()
  writer:write("alice\n")
  writer:flush()
  print(reader:read_line())
  client:shutdown()
  acceptor:cancel()
end)
-- Prints: welcome alice
```

::: note
Le serveur ne vérifie pas la révocation des certificats clients : il ne configure aucune liste de
révocation.
:::

## Fermer un flux TLS {#close-a-tls-stream}

TLS se termine proprement par une alerte `close_notify` (RFC 8446, section 6.1). `close()` ne
suspend jamais, il ne peut donc pas en envoyer une. Appelez d’abord `shutdown()`, puis laissez
`<close>` s’exécuter :

```lua
stream:shutdown() -- sends close_notify; suspends
```

Du côté qui reçoit, `read` renvoie `nil` après le `close_notify` du pair. Quand le transport se
termine sans lui, `read` lève `TlsError` avec la raison `truncated`, parce que les données
peuvent être incomplètes.

## Lire une erreur TLS

Une poignée de main ou une vérification qui échoue lève `TlsError`. `context.reason` nomme le
type d’échec quand il est reconnu :

| Raison | Signification |
|---|---|
| `untrusted_issuer` | La chaîne de certificats ne se termine pas par une autorité de confiance. |
| `name_mismatch` | Le certificat n’est pas valide pour le nom du serveur. |
| `expired`, `not_yet_valid` | Le certificat est hors de sa période de validité. |
| `revoked` | L’autorité a révoqué le certificat. |
| `alpn_mismatch` | Les deux côtés ne partagent aucun protocole applicatif. |
| `truncated` | Le transport s’est terminé sans `close_notify` : les données peuvent être incomplètes. |
| `transport_ended` | Le transport s’est terminé pendant la poignée de main. |
| `stalled` | La session TLS n’a plus progressé. |
| `native_missing` | Le module TLS natif n’est pas compilé. |

<!-- example: packages/net/examples/hecate.net.TlsError.lua -->
```lua
-- A failed verification raises a `TlsError` whose `context.reason` names the kind of failure.
-- Here the client trusts only another authority than the one that signed the server's
-- certificate. Needs the native TLS module (`lua tools/run.lua build-native`).
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."
local function fixture(name)
  local file = assert(io.open(here .. "/../tests/fixtures/" .. name, "rb"))
  local pem = file:read("a")
  file:close()
  return pem
end

reactor.run(function()
  local config = net.tls.server_config({ cert_pem = fixture("server.pem"), key_pem = fixture("server.key") })
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local ok = pcall(net.tls.accept, listener:accept(), config) -- the client abandons the handshake
    assert(not ok)
  end)
  local ok, err = pcall(net.connect_tls, "localhost", listener:local_address().port, {
    family = "inet", ca_pem = fixture("other_ca.pem"), system_roots = false,
  })
  assert(not ok and core.is_instance_of(err, net.TlsError))
  ---@cast err any -- an error value, not the stream that `pcall` is typed to return
  print(err.context.reason)
end)
-- Prints: untrusted_issuer
```

Sur macOS et Windows, le vérificateur du système d’exploitation rapporte de nombreux échecs sous
forme de texte seulement. Alors `context.reason` est absent et le message porte la cause. Testez
la raison avec une valeur de repli, et non comme une liste exhaustive.

## Connaître les différences entre plateformes

- Sur macOS et Windows, le vérificateur du système peut contrôler la révocation par le réseau
  pendant la poignée de main. Cet appel bloque le réacteur jusqu’à son terme. Utilisez
  `system_roots = false` quand c’est inacceptable.
- macOS refuse un certificat de serveur valide plus de 398 jours, même si son autorité a été
  ajoutée avec `ca_pem`. Utilisez des certificats plus courts, ou `system_roots = false`.
- Un magasin système vide ou incomplet est une erreur : la poignée de main lève `TlsError`, qui
  explique la cause et le remède. Installez les certificats du système (les images Docker de
  hecate le font) ou passez `ca_pem`.

## Voir aussi

- [Confiance TLS et valeurs par défaut de sécurité](../explanation/tls-trust-and-security.md)
- [Échéances et annulation sur les flux](deadlines-and-cancellation.md)
- Référence : [`net.connect_tls`](../reference/net/tls.md#connect_tls),
  [`tls.accept`](../reference/net/tls.md#accept),
  [`tls.server_config`](../reference/net/tls.md#server_config),
  [`TlsStream`](../reference/net/TlsStream.md), [`TlsError`](../reference/net/TlsError.md)
