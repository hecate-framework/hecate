---
description: Pourquoi hecate.schema décrit les types comme des données d’exécution, en quoi validation, coercition et build diffèrent, ce que l’ensemble de présence enregistre, et les bornes et limites à connaître.
hecate: "0.x"
lua: "5.5"
order: 5
source_revision: 116ae908aeaefad8e0404a64f574f53f59605f19
---

# Schémas et contrats

Cette page explique comment `hecate.schema` modélise les types et pourquoi. Elle est écrite pour hecate 0.x et Lua 5.5.
Pour des recettes, voir [Valider des valeurs avec des schémas](../how-to/validate-with-schemas.md). La spécification
complète est [schemas-and-contracts.md](https://github.com/hecate-framework/hecate/blob/main/docs/architecture/schemas-and-contracts.md)
dans le dépôt, et la référence de code est [`hecate.schema`](../reference/schema/index.md).

## Les schémas sont des données d’exécution

Un [schéma](../reference/glossary.md#types-and-validation) (*schema*) est une valeur Lua ordinaire et immuable. Ce
n’est pas un commentaire, une entrée de générateur de code ni un type qui n’existe qu’à la compilation. Lua n’a pas de
types statiques à lire, donc la déclaration elle-même est le type.

C’est ce qui rend hecate orienté contrat (*contract-first*). Une seule valeur pilote tous les usages d’un type :

- la validation d’un contenu décodé,
- la coercition des textes d’un chemin, d’une chaîne de requête ou des champs d’en-tête,
- les instances que reçoit une action,
- le document JSON Schema 2020-12 du contrat.

Le contrat ne peut pas s’écarter du code, parce qu’il n’y a pas de seconde description à tenir à jour. Chaque schéma se
compile une seule fois, à la déclaration, en fermetures. Une requête ne parcourt pas la description.

Le vocabulaire est celui de la littérature. Un type de base restreint par des prédicats est un type raffiné
(*refinement type*) (`integer` avec `minimum = 1`). Un enregistrement est un type produit (`object`). Une valeur qui est
exactement l’une de plusieurs variantes est un type somme (`union`, `tagged_union`). Les membres d’un `object` sont des
propriétés, le terme de JSON Schema. Le glossaire définit chaque terme.

## Validation, coercition et build

Trois opérations lisent une valeur par rapport à un schéma. Elles répondent à des questions différentes.

| Opération | Entrée | Réponse |
|---|---|---|
| `validate` | contenu JSON décodé | la valeur est-elle conforme ? Ne change rien |
| `coerce` | les textes d’un chemin, d’une requête ou des champs d’en-tête | la valeur typée, avec les valeurs par défaut fournies |
| `build` | contenu JSON décodé, ou textes avec `coerce = true` | une instance de la classe de chaque partie |

`validate` est pure. Elle renvoie toutes les [violations](../reference/glossary.md#types-and-validation)
(*violations*), chacune avec un chemin JSON Pointer, un code et un message, de sorte qu’un client voit toutes ses
erreurs d’un coup. Elle ne convertit jamais et ne fournit jamais de valeur. `integer` refuse `1.0` et un texte comme
`"42"`.

La coercition existe parce que les textes ne sont pas du JSON. Une valeur de requête est toujours une chaîne, et le
schéma connaît le type qu’elle devrait avoir. Les règles sont strictes : `integer` lit un signe moins facultatif et des
chiffres, `boolean` ne lit que `true` et `false`, et un texte n’est jamais converti en null. Le contenu JSON n’est pas
converti, parce que JSON porte déjà des types, et une chaîne là où un nombre est attendu est une erreur à signaler.

`build` valide d’abord, puis fabrique les instances. Une partie déclarée avec `schema.of(Class)` devient une instance de
cette classe, sans appeler son `init`, parce que la validation a déjà garanti que les attributs sont conformes. Avec
`coerce = true`, `build` convertit d’abord les textes puis construit, de sorte qu’une classe comme un filtre de liste
se construit à partir d’une chaîne de requête en un seul appel.

La réponse suit le chemin inverse. `represent` fait passer une instance par son schéma et renvoie des valeurs simples :
les attributs que le schéma déclare (un attribut non déclaré ne fuit jamais), les membres d’énumération sous la forme
de leurs noms, les parties imbriquées, les tableaux, les tables associatives et les unions converties récursivement. Le
noyau encode ensuite ce résultat simple avec `json.encode` : une instance devient des valeurs simples, puis du JSON, et
`hecate.json` ignore tout des classes. `represent` ne valide pas, puisqu’une réponse non conforme est un bogue du
serveur, et elle est bornée par la même garde de profondeur et le même budget de travail que les autres opérations, de
sorte qu’un cycle dans le graphe d’objets se termine par une erreur `depth_limit`. Un attribut qui a été envoyé comme
`null` est représenté comme `null`, de sorte que le décodage, le build, `represent` et l’encodage redonnent le même
contenu.

## L’ensemble de présence et PATCH

Un POST ou un PUT porte une ressource entière. Un attribut absent vaut `nil`, et la validation n’échoue que si
l’attribut est requis. Un PATCH porte une partie d’une ressource, de sorte que deux affirmations différentes se
ressemblent dans l’instance :

- un attribut absent signifie inchangé,
- un attribut qui est un `null` explicite signifie effacé.

Les deux valent `nil` dans l’instance. Hecate garde la différence dans un [ensemble de présence](../reference/glossary.md#types-and-validation)
(*presence set*), lu avec `schema.sent(instance, name)`. L’ensemble vit dans une table annexe à clés faibles, en dehors
de l’instance. L’instance ne contient donc que ses attributs : `pairs` et `json.encode` ne voient rien d’autre, et une
instance qui n’a pas été construite par `build` n’a simplement rien envoyé.

L’alternative aurait été de stocker `json.null` comme valeur d’un attribut effacé. Elle a été rejetée, parce que tout
lecteur de l’attribut aurait alors dû tester une valeur sentinelle.

Un PATCH n’assouplit que les propriétés requises de l’objet de premier niveau. Un objet imbriqué est remplacé en
bloc, pas fusionné, donc il reste strict. Les valeurs par défaut ne s’appliquent jamais à un PATCH, parce qu’une valeur
par défaut ferait d’un attribut inchangé un attribut modifié. Avec les autres méthodes, `sent` reste faux pour un
attribut rempli par une valeur par défaut, de sorte qu’une action peut savoir ce que le client a réellement envoyé.

## Pourquoi les classes possèdent les noms de schémas

Un contrat d’API a des composants nommés. Quelqu’un doit posséder les noms. Dans hecate, c’est la classe. Une classe
déclare une fonction de niveau classe `schema()`, et l’interface `schema.HasSchema` peut l’exiger. Un autre schéma ou une route nomme la
classe elle-même avec `schema.of(Class)`, jamais une chaîne.

Cela donne un seul endroit pour chaque nom et une seule fonction pour chaque type. La validation, la coercition, le
build et l’émission appellent tous la même fonction, et le résultat est mis en cache parce qu’il est immuable.
L’émission écrit chaque classe une seule fois dans `$defs` et y fait référence. Les types récursifs fonctionnent parce
que la résolution est paresseuse, et un cycle se referme avec un `$ref`.

Un schéma sans classe est mis en ligne et jamais nommé. `named` est le choix explicite pour un schéma en ligne
(*inline schema*) qui n’a pas de classe. Deux définitions différentes sous un même nom sont une erreur, pas une fusion silencieuse, de
sorte qu’un contrat ne change jamais de sens à cause de l’ordre des déclarations.

## Bornes de sûreté

Les schémas valident du contenu non fiable, donc chaque appel est borné.

- **Profondeur.** L’imbrication est limitée à 1000 niveaux, le même maximum que `json.decode` et `json.encode`. Le
  décodeur refuse un contenu plus profond avant que `schema` ne le voie. Une table construite à la main peut quand
  même être plus profonde, et une violation `depth_limit` arrête alors l’appel au chemin où elle a été atteinte, au
  lieu d’épuiser la pile.
- **Budget de travail.** Un appel dépense au plus 1 000 000 d’étapes, une par conteneur visité ou alternative essayée.
  Au-delà, l’appel se termine par une violation `complexity_limit`. Le budget est un dernier recours. Les autres
  gardes maintiennent les schémas ordinaires très en dessous.
- **Unions à échec rapide.** Une `union` décide chaque alternative à sa première violation, propriétés littérales
  d’abord, et mémorise sa réponse par table pendant un appel. Sans cela, une union récursive de conteneurs coûte un
  temps exponentiel en sa profondeur.
- **`tagged_union`.** Quand les variantes se distinguent par une propriété constante, préférez-la à une `union`. Elle
  lit l’étiquette une fois, valide une variante et rapporte les violations de cette variante. C’est la somme la moins
  coûteuse et aussi l’erreur la plus claire.

## Limites à connaître

Certaines différences entre Lua et JSON Schema ne peuvent pas être supprimées. Hecate les documente au lieu de les
cacher, et n’approxime jamais en silence.

- **Motifs Lua et ECMA-262.** `pattern` est un motif Lua, pas une expression régulière. L’émission traduit
  exactement un sous-ensemble ASCII défini et refuse le reste (`%b`, `%f`, octets non ASCII). Lua apparie des octets
  et ECMA-262 apparie des unités de code UTF-16, de sorte que `.` et les ensembles niés peuvent diverger sur une
  entrée non ASCII. Pour une entrée ASCII, les deux s’accordent. Les motifs Lua peuvent aussi revenir en arrière
  (*backtrack*), donc les motifs doivent être ancrés, et une chaîne de plus de 65536 octets sans `max_length` n’est
  jamais appariée (violation `pattern` avec `context.reason` valant `too_long_for_pattern`).
- **Octets et points de code.** `min_length` et `max_length` comptent des points de code, comme le fait JSON Schema, et
  une chaîne qui n’est pas de l’UTF-8 bien formé est une violation. `pattern` apparie des octets.
- **`1.0` et integer.** `integer` n’accepte que des entiers Lua. JSON Schema ne distingue pas `1` de `1.0`, donc les
  `integer`, `const` et `enum` émis acceptent aussi `1.0`. C’est le seul écart documenté entre validateur et contrat,
  verrouillé par un test.
- **Flottants binaires et `multiple_of`.** Les flottants binaires ne savent pas exprimer un pas décimal : le reste de
  `19.99` par `0.01` n’est pas nul. `multiple_of` ne prend donc que des diviseurs entiers. Pour des décimales,
  utilisez des entiers en unités mineures ou une chaîne avec un motif.
- **Constructions non prises en charge.** Une construction que JSON Schema ne peut pas exprimer exactement n’est pas
  autorisée.
- **Mots-clés hors du sous-ensemble émis.** L’émission couvre `type`, `enum`, `const`, les raffinements numériques, de
  chaîne, de tableau et d’objet, `properties`, `required`, `additionalProperties`, `items`, `anyOf`, `oneOf`, `default`,
  `format`, `$defs` et le `$ref` local. Ces mots-clés ne sont pas émis, comme limite délibérée : `allOf`, `not`, `if`,
  `then` et `else`, `contains`, `prefixItems`, `patternProperties`, `propertyNames`, `dependentSchemas`,
  `dependentRequired`, `unevaluatedProperties`, `unevaluatedItems`, `$id`, les ancres, `$dynamicRef`, le `$ref` distant
  et les mots-clés `content`. Ils sont hors du périmètre tant qu’aucun consommateur n’en a besoin. `oneOf` n’est émis
  que par `tagged_union` : une `union` est un `anyOf`.
- **Prévu, non implémenté.** `refine` (un prédicat personnalisé), les générateurs de valeurs d’exemple (`generate`,
  `generate_invalid`, portés par le paquet `test`) et la génération de fichiers `---@meta` pour LuaLS (portée par `doc`
  ou `cli`) n’existent pas encore.

## Lectures associées

- [Valider des valeurs avec des schémas](../how-to/validate-with-schemas.md), les recettes.
- [Encoder et décoder du JSON](../how-to/encode-and-decode-json.md), le codec qui partage la limite de profondeur.
- Le [glossaire](../reference/glossary.md).
