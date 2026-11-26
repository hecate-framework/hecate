---
description: Lier des services dans un conteneur, choisir des durées de vie singleton, scoped ou transient, valider le graphe au démarrage, résoudre par injection par constructeur, fermer les services et les remplacer dans les tests avec hecate.container.
hecate: "0.x"
lua: "5.5"
order: 14
source_revision: 127cb3d2f023c24467492b8959dd7bc7bc0390d7
---

# Utiliser le conteneur

Ce guide montre comment construire les objets d’une application avec `hecate.container`. Il est écrit pour hecate 0.x
et Lua 5.5.

Un [conteneur](../reference/glossary.md#object-model-and-architecture) (*container*) est un objet qui résout et
construit des dépendances. Chaque objet qu’il construit est un
[service](../reference/glossary.md#object-model-and-architecture) (*service*). Vous listez les services et ce dont
chacun a besoin en un seul endroit, la
[racine de composition](../reference/glossary.md#object-model-and-architecture) (*composition root*). Le conteneur
vérifie le graphe entier avant que rien ne s’exécute, puis construit les services quand on les demande.

`hecate.container` ne dépend que de `hecate.core`. Il n’a besoin d’aucun module natif, et il ne suspend jamais.

## Lier, valider, résoudre {#bind-validate-resolve}

Un conteneur s’utilise en trois temps : lier les services, valider le graphe une fois, puis résoudre des services.

<!-- example: packages/container/examples/hecate.container.Container.lua -->
```lua
-- Bind services, validate the graph at boot, then resolve them: a singleton
-- is shared, a scoped service lives in one service scope (one per request), a
-- transient is built for each caller.
local core = require("hecate.core")
local container = require("hecate.container")

local Clock = core.class("Clock")
function Clock:now() return 1700000000 end
core.finalise(Clock)

local Session = core.class("Session")
function Session:init(clock) self.opened_at = clock:now() end
function Session:__close() self.closed = true end
core.finalise(Session)

local c = container.Container()
c:bind("clock", Clock, { lifetime = "singleton" })
c:bind("session", Session, { lifetime = "scoped", requires = { "clock" } })
c:validate()

local session
do
  local request <close> = c:open_scope()
  session = request:resolve("session")
  print(session == request:resolve("session"))
  -- Prints: true
  print(c:open_scope():resolve("session") == session)
  -- Prints: false
  print(c:resolve("clock") == request:resolve("clock"))
  -- Prints: true
end
-- Closing the scope closes its scoped services.
print(session.closed)
-- Prints: true

-- A mistake in the composition is found at boot, with every problem at once.
local broken = container.Container()
broken:bind("a", function() end, { lifetime = "transient", requires = { "b" } })
broken:bind("b", function() end, { lifetime = "transient", requires = { "a", "missing" } })
local ok, err = pcall(function() broken:validate() end)
---@cast err hecate.container.GraphError
print(ok, err.context.problems[1].context.path[1], #err.context.problems)
-- Prints: false	a	2
```

Un service ne demande jamais rien au conteneur : il reçoit ses dépendances dans son constructeur. Il n’y a pas de
conteneur global ni de moyen d’en atteindre un depuis un service. Seuls la racine de composition et le noyau appellent
`resolve`.

## Lier un service {#bind-a-service}

`bind(key, definition, options?)` enregistre un service. Il renvoie le conteneur, de sorte que les appels s’enchaînent.

- La **clé** est une chaîne non vide (un nom) ou une [interface](../reference/glossary.md#object-model-and-architecture)
  (*interface*) faite par `core.interface`. Une clé a une seule liaison : la lier deux fois lève
  `DuplicateBindingError`. `has(key)` dit si une clé est liée, sans rien construire.
- La **définition** est une classe finalisée, appelée comme `Class(dependency1, dependency2, ...)`. Ce peut aussi être
  une fonction (une fabrique), appelée avec les mêmes arguments.
- `requires` liste les clés des dépendances, dans l’ordre des arguments du constructeur. Les dépendances sont
  déclarées, jamais devinées à partir des noms de paramètres.
- `lifetime` vaut `"singleton"`, `"scoped"` ou `"transient"` (ou un membre de `container.Lifetime`). Elle est
  obligatoire : lier sans elle lève `ArgumentError`. Ce qu’un service partage est ainsi toujours écrit là où il est
  lié.

Une définition doit s’exécuter jusqu’au bout sans suspendre. Tant que l’une d’elles est suspendue, résoudre la même
clé depuis un autre calcul lève `ContainerError`.

Quand la clé est une interface, une définition de classe doit l’implémenter ; `validate` le signale sinon. Le produit
d’une fabrique est vérifié à sa première construction.

## Choisir une durée de vie {#choose-a-lifetime}

| Durée de vie | Une instance vit | Créée |
|---|---|---|
| `singleton` | aussi longtemps que le conteneur | à la première résolution, puis partagée |
| `scoped` | aussi longtemps qu’une portée de service | à la première résolution dans cette portée, puis partagée à l’intérieur |
| `transient` | pour l’appelant seul (fermée par sa portée si elle définit `__close`) | à chaque résolution, jamais mise en cache |

### Ouvrir une portée de service {#open-a-service-scope}

Une [portée de service](../reference/glossary.md#object-model-and-architecture) (*service scope*) est la région dans
laquelle un service `scoped` a une seule instance. `container:open_scope()` en fait une, et le noyau en ouvre une par
requête. Ce n’est pas une portée du réacteur.

Une portée de service est une valeur ordinaire. Tout calcul qui la reçoit voit les mêmes instances scoped : un service
scoped est donc partagé entre les `fork`, pas copié.

Fermez la portée quand la requête se termine : appelez `scope:close()`, ou tenez-la dans une variable `<close>` comme
le fait l’exemple.

### Résoudre depuis le conteneur ou depuis une portée {#resolve-from-the-container-or-from-a-scope}

- `scope:resolve(key)` construit n’importe quel service.
- `container:resolve(key)` construit les singletons, et les transients dont toutes les dépendances sont des singletons
  ou des transients.

`container:resolve` n’a pas de portée de service. Deux cas y lèvent `LifetimeError`, avant que rien ne soit construit :

- un service qui a besoin d’un service scoped ;
- un transient qui définit `__close` et qu’aucun singleton ne possède. Résolvez-le avec `scope:resolve`.

## Valider au démarrage {#validate-at-boot}

`container:validate()` vérifie chaque liaison sans rien construire. Elle signale :

- une **liaison manquante** : une clé requise qui n’est pas liée (`MissingBindingError`) ;
- un **cycle** : `a -> b -> c -> a`, le plus court étant une liaison qui s’exige elle-même (`CycleError`) ;
- une **violation de durée de vie** : un singleton qui dépend d’un service scoped, directement ou par des transients
  (`LifetimeError`). Il garderait en vie un objet lié à une requête pendant tout le processus ;
- une classe qui n’implémente pas la clé **interface** (`core.ConformanceError`).

Il n’y a pas de résolution paresseuse pour rompre un cycle : restructurez plutôt les services.

`validate` rassemble tous les problèmes et lève une seule `GraphError`. `err.context.problems` les liste dans l’ordre
des liaisons. Un graphe validé n’en lève aucun au moment d’une requête : ce qui peut encore échouer, c’est le code
d’un constructeur.

La validation fige aussi le conteneur. Ensuite, `bind` et `override` lèvent `core.StateError`. Avant qu’elle ait
réussi, `resolve` et `open_scope` lèvent `core.StateError`.

### Lire les avertissements {#read-the-warnings}

`validate` renvoie le conteneur et une liste d’**avertissements**, qui ne la font jamais échouer.

Un singleton qui dépend directement d’un transient reçoit un avertissement avec `code = "singleton_over_transient"`,
`key`, `dependency`, `path` et un `message`. Ce transient est construit une fois et vit aussi longtemps que le
processus.

Le conteneur n’a pas de journaliseur ; le noyau signale les avertissements.

## Fermer les services {#close-services}

Un service dont l’instance définit `__close` est fermé par son propriétaire, dans l’ordre inverse de la création :

- un service scoped, et un transient fermable, quand la portée de service qui les a résolus se ferme ;
- un singleton, et un transient fermable qu’il a reçu, quand le conteneur se ferme.

Un transient sans `__close` n’est jamais suivi.

Chaque fermeture est tentée. La première erreur est levée ensuite, et les autres sont dans `context.suppressed`.
Fermer est idempotent, et une portée ou un conteneur fermé refuse `resolve`.

### Libérer un transient plus tôt {#release-a-transient-early}

Une portée qui possède un transient le ferme : ne mettez donc pas vous-même de `<close>` dessus. Pour le fermer plus
tôt, appelez `scope:release(instance)`. Elle ferme l’instance une fois et cesse de la suivre ; une erreur de fermeture
se propage telle quelle.

Libérer une instance que la portée ne suit pas lève `ContainerError`, de même que la libérer une seconde fois.

Une portée de longue durée garde les transients fermables qu’elle a résolus jusqu’à sa fermeture ou jusqu’à ce que vous
les libériez.

### Instances partagées {#shared-instances}

Un propriétaire ferme une instance une seule fois, même si une fabrique l’a renvoyée plusieurs fois. L’instance d’un
singleton, renvoyée de nouveau par une fabrique de transient, reste celle du conteneur.

Quand la construction d’un singleton échoue, les transients fermables construits pour lui sont fermés aussitôt.

## Traiter les erreurs de construction {#handle-construction-errors}

Une erreur levée par un constructeur ou une fabrique devient une `ConstructionError` :

- sa `cause` est l’erreur d’origine ;
- `context.key` dit quel service a échoué ;
- `context.path` dit par quelle chaîne il a été atteint.

`CancellationError` et `DeadlineExceededError` passent sans changement.

Un constructeur qui renvoie `nil` lève aussi `ConstructionError`. Le produit d’une fabrique qui n’implémente pas sa
clé interface lève `core.ConformanceError`, avec le même `context.path`, après avoir été fermé s’il définit `__close`.

Une construction échouée ne met rien en cache : la résolution suivante réessaie.

## Remplacer un service dans un test {#replace-a-service-in-a-test}

`override(key, definition, options?)` remplace une liaison avant `validate`.

- Sans `options`, elle garde la durée de vie et les `requires` de la liaison remplacée.
- Avec `options`, `lifetime` est obligatoire, comme pour `bind`.

Une clé qui n’est pas liée lève `MissingBindingError` : une clé mal orthographiée ne peut donc pas créer un service par
accident.

`override_with_instance(key, value)` lie un objet existant comme singleton sans dépendances. C’est la façon habituelle
d’injecter un fake.

- La clé doit être liée.
- Pour une clé interface, la valeur doit l’implémenter. Un fake qui ne le fait pas lève `core.ConformanceError` à
  l’appel.
- Le conteneur ne ferme jamais cet objet, même s’il définit `__close` : vous l’avez construit, vous le fermez.

Le nouveau graphe est validé dans son ensemble. Un remplacement ne peut pas ajouter un cycle ou une dépendance captive
sans qu’on s’en aperçoive.

## Connaître les erreurs {#know-the-errors}

Toutes les erreurs du conteneur étendent `core.ConfigurationError` :

- `ContainerError` ;
- `DuplicateBindingError` ;
- `MissingBindingError` ;
- `CycleError` ;
- `LifetimeError` ;
- `GraphError` ;
- `ConstructionError`.

Un argument incorrect lève `core.ArgumentError`. Un usage dans le mauvais état lève `core.StateError` : un usage avant
`validate`, `bind` ou `override` après elle, et tout usage après `close`.

Dans les messages et le `context`, une interface est montrée par son nom.

## Voir aussi {#see-also}

- [Concurrence](../../../../user/en/how-to/concurrency/) : les services scoped comme moyen d’éviter l’état partagé.
- Référence : [`hecate.container`](../reference/container/index.md)
