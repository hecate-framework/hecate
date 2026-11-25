---
description: Le générateur de documentation des projets utilisateurs : la configuration du site, les pages générées à partir du schéma de configuration, les fichiers meta de LuaLS et les points d’extension du thème.
hecate: "0.x"
lua: "5.5"
order: 3
source_revision: 57ace85c67235547aa716c4fcac0d2c745f00057
---

<!-- Page de référence rédigée à la main (non générée) : à garder alignée sur packages/doc/README.md. -->

# Documentation d’un projet

`hecate.doc` construit le site de documentation d’un projet utilisateur avec le même thème que le site de hecate.
Cette page couvre ce qu’un projet peut configurer et ce qui est généré pour lui, pour hecate 0.x et Lua 5.5.

## Audiences

Le site que `doc.generate_project_documentation` écrit est la documentation de l’équipe du projet elle-même. Par défaut,
il sert les mainteneurs. Il y a deux audiences : `user` (construire, exécuter et exploiter une application sur l’API
publique) et `maintainer` (modifier le projet lui-même : architecture, décisions, internes, CI et livraison). Ce sont
deux sites distincts : un arbre de contenu chacun dans les sources, et un répertoire de sortie chacun.

```text
docs/
  site.lua                   une configuration de site pour le projet
  user/                      l’arbre du site utilisateur (facultatif)
    en/index.md              sa page d’accueil
    en/guide/getting-started.md
    public/                  ses propres fichiers statiques
  maintainer/                l’arbre du site des mainteneurs
    en/index.md              sa page d’accueil
    en/architecture.md
    public/
  dist/                      la sortie
    user/                    le site utilisateur
    maintainer/              le site des mainteneurs
```

Chaque arbre est organisé comme un site simple : un répertoire par locale, et `public/` à côté. Il est construit par le
constructeur simple dans `<output_dir>/<audience>/`, si bien que chaque site a ses propres pages, sa navigation, son
index de recherche, son plan de site, son `llms.txt`, ses fichiers de thème et son `404.html`, et aucune page de
l’autre arbre. L’adresse publique d’un site (ses liens canoniques, son plan de site et son `llms.txt`) est le
`base_path` de la configuration plus l’audience. Les liens à l’intérieur d’un site sont relatifs à la page et la sortie
est faite de fichiers statiques : elle s’ouvre depuis le système de fichiers et depuis n’importe quel hébergeur
statique, sans serveur. `<output_dir>/` lui-même ne contient qu’un fichier marqueur et une redirection vers le premier
site.

| Où | Nom | Signification |
|---|---|---|
| Option de `generate_project_documentation` | `audiences` | Les arbres à construire. Par défaut `{ "maintainer" }`. Demandez `{ "user", "maintainer" }` pour les deux. |
| `<guides_dir>/<audience>/` | arbre de contenu | Chaque arbre a besoin de sa propre page d’accueil : `index.md` dans la locale par défaut. |
| `<guides_dir>/site.lua` | configuration du site | Un seul fichier. Son titre, ses locales, son thème et ses autres clés s’appliquent à chaque site d’audience ; un titre ou un thème différent pour une audience n’est pas possible. |

Un arbre qui n’est pas listé dans `audiences` n’est pas construit, et ce n’est pas une erreur. Un arbre listé qui
n’existe pas est un problème, qui fait échouer la construction sous `fail_on_problems` et vous indique le fichier à
ajouter (`add docs/user/en/index.md`). Un arbre sans sa page d’accueil est un problème de cet arbre.

Il n’y a pas de clé `audience` dans le front matter : une page qui l’a encore fait échouer la construction avec une
`BuildError` qui nomme le fichier et la disposition. Les clés de configuration du site `audiences`, `default_audience`
et `audience_sites` n’existent plus non plus, et `site.lua` les refuse. Déplacez les pages dans l’arbre de leur audience
et supprimez les clés.

Les pages générées vont dans le bon arbre. La référence de configuration et la page des licences sont des pages de
l’arbre `maintainer` (`licences_page.audience` peut nommer un autre arbre listé). La référence de code liste les
symboles publics dans l’arbre `user` ; les pages des modules `*.internal` et des classes `private` ou `package` vont
dans l’arbre `maintainer`. Lorsqu’un seul arbre est construit, il contient toute la référence de code. Avec les deux
arbres, une page de référence ne renvoie qu’à des pages de son propre arbre, et la page d’un module ne liste que les
classes de son propre arbre. Un champ ou une méthode qui n’est pas public n’est jamais listé.

Un lien d’une page d’un site vers une page de l’autre site est un lien ordinaire que le constructeur ne peut pas
vérifier. Écrivez une URL absolue, `https://example.org/user/en/guide/`, ou un lien relatif. Le navigateur lit un lien
relatif depuis le fichier de la page, pas depuis son fichier source : la page `guide/a.md` du site des mainteneurs est
écrite dans `maintainer/en/guide/a/index.html`, si bien que la page utilisateur `guide/` est
`../../../../user/en/guide/index.html`. Le constructeur laisse tel quel un lien relatif qui remonte de deux niveaux ou
plus au-dessus du répertoire de la locale, et ne signale aucun problème. Un lien qui remonte seulement jusqu’à la racine
du contenu (`../x.md`) reste un problème, comme un lien cassé à l’intérieur de l’arbre.

Un exemple complet, un projet avec un site pour ses utilisateurs et un pour son équipe :

```lua
-- docs/site.lua
return {
  title = "Shop",
  locales = { { code = "en", label = "English" } },
}
```

```lua
-- Build both sites, strictly: a missing tree or a broken link fails.
doc.generate_project_documentation({
  application = application,
  audiences = { "user", "maintainer" },
  fail_on_problems = true,
})
```

Avec les fichiers `docs/user/en/index.md`, `docs/maintainer/en/index.md` et la référence de configuration générée dans
`docs/maintainer/en/configuration.md`, la construction écrit `docs/dist/user/en/index.html`,
`docs/dist/maintainer/en/index.html` et `docs/dist/maintainer/en/configuration/index.html`, et ne signale aucun problème.
Sans `audiences`, seul `docs/dist/maintainer/` est écrit. Le site de Hecate est un arbre construit par le constructeur
simple ; il passera plus tard dans `website/user/` et `website/maintainer/`.

Une option ou une clé de `site.lua` qui n’est pas sur sa liste est refusée : un ancien nom (`colors`, `theme`, `logo`)
avec le nom qui l’a remplacé, une faute de frappe (`audience`) avec la clé la plus proche.

## Pages générées

`doc.generate_project_documentation(options)` écrit les guides du projet et les pages générées ci-dessous sous le
répertoire de locale du répertoire des guides, puis lance la construction du site. Ce n’est pas le constructeur simple
`doc.build`, qui ne fait que transformer un arbre de contenu en site. Chaque option a une valeur par défaut tirée de la
disposition conventionnelle d’un projet, si bien que `doc.generate_project_documentation({ application = application })`
fonctionne depuis le répertoire du projet. Un nom qui se termine par `_dir` est un répertoire et un nom qui se termine
par `_path` est un fichier ; les chemins relatifs le sont par rapport à `project_dir`.

| Option | Défaut | Effet |
|---|---|---|
| `project_dir` | `.` | Le répertoire du projet. |
| `guides_dir` | `docs` | La racine des guides : un arbre de contenu par audience, `<guides_dir>/<audience>/<locale>/*.md` et `<guides_dir>/<audience>/public/`, et `site.lua`. Les pages générées sont écrites dans les arbres. |
| `audiences` | `{ "maintainer" }` | Les arbres à construire, chacun dans son propre site (voir « Audiences »). |
| `output_dir` | `docs/dist` | Où les sites sont écrits, un par arbre, dans `<output_dir>/<audience>/`. Il peut se trouver sous `guides_dir` (le défaut), mais ne peut être ni `guides_dir` ni `project_dir`, ni contenir l’un ou l’autre, ni chevaucher `sources_dir`. |
| `site_configuration_path` | `<guides_dir>/site.lua` | Le fichier qui renvoie la configuration du site ; un chemin que vous donnez est relatif à `project_dir`, le défaut est sous `guides_dir`. `site_configuration` passe la table à la place ; fournir les deux est une erreur. Un fichier manquant est une `BuildError` qui nomme les remèdes. |
| `application` | aucun | Ajoute `configuration.md`, une ligne par clé, à partir du JSON Schema de la configuration donnée à l’application (une page de l’arbre `maintainer`, écrite lors de sa construction). L’application est la seule source : un projet qui n’en a pas n’a pas de référence de configuration. Le schéma est la source unique des secrets : une clé marquée `writeOnly: true` ou `format: "password"` (`Configuration:schema()` le fait pour les secrets de `hecate.config`), ou qui contient une telle clé en dessous d’elle, n’imprime jamais sa valeur par défaut, son énumération ni sa constante. |
| `package_name` | aucun | Demande la référence de code `reference/<package_name>/`, à partir des sources annotées de `sources_dir` (`src` par défaut ; nécessite LuaLS). LuaLS exécute les greffons que déclarent les configurations qu’il atteint : le projet doit être de confiance (voir l’avertissement ci-dessous). |
| `licences_page` | désactivé | Ajoute la page des licences tierces : `true`, ou une table `{ rocks_tree_dir, root_rocks, audience, include_bundled }`. |

Les autres options sont `content_locale`, `file_system`, `clean_output_dir`, `fail_on_problems`, `last_updated`,
`language_server_path`, `language_server_config_path`, `theme_file_system` et `theme_files_dir` ; elles sont décrites
dans le README du paquet.

Les pages générées portent un avis (la première ligne après le front matter) et `generated: true` dans leur front
matter, et sont remplacées à chaque construction. Un guide ne peut pas en écraser une, et une page générée n’écrase
jamais un fichier qui n’est pas généré (une `BuildError` avant que quoi que ce soit soit écrit) ; un guide qui ne fait
que citer l’avis n’est pas généré et n’est jamais touché. Une page générée n’est jamais écrite à travers un lien
symbolique. Les pages générées qu’une construction ne produit plus sont supprimées. Une option fausse, ou absente de la
liste (un ancien nom, une faute de frappe), lève une `ArgumentError` qui la nomme (`context.argument`). Avec
`fail_on_problems`, une seule `BuildError` liste tous les problèmes de la construction, de la page des licences et de la
référence de code.

Un lien symbolique dans un arbre de `guides_dir` ou dans son `public/` n’est jamais suivi : il est ignoré avec un
problème, afin qu’un lien vers un fichier de clés ou vers un répertoire parent ne puisse ni publier ni boucler. Un arbre
de plus de 32 niveaux ou de plus de 100 000 entrées est tronqué avec un problème. Un titre dont l’identifiant est un de
ceux que le thème utilise (`content`, `sidebar`, `search`, ...) est un problème : écrivez
`## Content {#project-content}`. Le texte qui vient du schéma est échappé, car ce sont des données du projet et non du
Markdown.

Le générateur ne produit aucune référence de l’API HTTP. Le contrat OpenAPI est la documentation externe de l’API HTTP :
l’application le sert (`/openapi.json`) et `hecate contract export` l’écrit. Un visualiseur, tel que Swagger UI, est votre
propre câblage, par exemple un fichier Docker compose à côté de l’application. La référence de code ci-dessus est autre
chose : elle documente les modules, classes et fonctions Lua de `package_name`, à partir de leurs annotations LuaLS, et
aucune route.

> [!WARNING] Ne documentez que des sources de confiance
> La référence de code exécute LuaLS, et LuaLS exécute du code arbitraire. Un greffon déclaré par n’importe quelle
> configuration LuaLS qu’il atteint est exécuté avec un accès complet aux fichiers et aux commandes, sous l’utilisateur
> qui lance la construction. Les configurations sont les fichiers `.luarc.json` et `.luarc.jsonc` et le réglage
> `Lua.runtime.plugin` de `.vscode/settings.json` du répertoire documenté et du projet, et un `.luarc.json` à
> l’intérieur du répertoire des sources compte même lorsque `language_server_config_path` pointe ailleurs. Sans
> `language_server_config_path`, aucun `--configpath` n’est passé et LuaLS trouve sa configuration lui-même.
> `lua-language-server` est trouvé par `PATH`, sauf si `language_server_path` le nomme : `PATH` doit donc être de
> confiance lui aussi. La bibliothèque n’avertit pas ; c’est la commande `hecate doc build` qui avertit et vous laisse
> vous arrêter (feuille de route, élément `cli`). Ne demandez pas de référence de code pour un projet que vous ne
> contrôlez pas.

## Fichiers meta LuaLS

`doc.project.meta(schemas, namespace)` renvoie le texte d’un fichier `---@meta` : un schéma d’objet devient une
`---@class` avec un `---@field` par propriété, et une énumération devient un `---@alias`. La sortie est déterministe.

## Points d’extension du thème

La configuration du site a des options pour donner à un projet sa propre identité. Les trois premières nomment des
fichiers du répertoire `public/` de la racine du contenu, que la construction copie à la racine du site.

| Option | Effet |
|---|---|
| `logo_path` | Un chemin, ou `{ light, dark }`. Remplace le logo de hecate dans l’en-tête. L’image est affichée telle quelle. |
| `favicon_path` | Un chemin, ou `{ light, dark }`, d’un fichier `.svg`, `.png` ou `.ico`. Remplace la favicon de hecate ; l’attribut `type` du `<link rel="icon">` suit l’extension. Avec une paire, chaque fichier porte une requête média `prefers-color-scheme`. |
| `stylesheet_path` | Un fichier CSS (`.css`) chargé après la feuille de style du thème. Il redéfinit les propriétés personnalisées du thème : couleurs en clair et en sombre, coloration du code, les trois familles de polices, rayons, espacements et largeur de la barre latérale. Il peut déclarer son propre `@font-face` pour des fichiers de police de `public/`. |

L’option `sidebar_marker` (un booléen, `false` par défaut) dessine une barre d’accent à gauche de la page courante dans
la barre latérale. Sans elle, la page courante est signalée par une graisse plus forte et une légère teinte.

Un chemin doit être relatif, sans `..`, schéma ni requête. Un fichier absent de `public/` fait échouer la construction
avec une `BuildError`. Les marques de hecate ne sont jamais recolorées. Le remplacement des gabarits n’est pas proposé.
Chaque propriété, ce qu’elle affecte et comment livrer vos propres polices se trouvent dans
[Jetons de thème](../../en/reference/theme-tokens.md).

Exemple de `public/theme.css`, avec une variante sombre (l’ensemble sombre est écrit deux fois : pour la préférence du
système et pour le bouton de bascule) :

```css
:root { --moon: #7a1f3d; --sans: system-ui, sans-serif; }
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) { --moon: #f2b8c9; }
}
:root[data-theme="dark"] { --moon: #f2b8c9; }
```

## llms.txt

Définissez `generate_llms_txt = true` dans la configuration du site pour que la construction écrive `llms.txt` et
`llms-full.txt` à la racine du site, selon la convention de [llmstxt.org](https://llmstxt.org). C’est désactivé par
défaut : le site d’un projet ne publie rien pour les modèles de langage tant que vous ne le demandez pas. Sans la clé, un
fichier `public/llms.txt` qui est le vôtre est copié tel quel ; avec la clé, un fichier de `public/` portant l’un de ces
deux noms fait échouer la construction, car le fichier généré le remplacerait.

- `llms.txt` contient le titre du site, sa description, puis un lien vers chaque page publiée avec la `description` de
  son front matter, regroupés par section de premier niveau dans l’ordre de la navigation. Les liens sont absolus
  lorsque `site_origin` est défini.
- `llms-full.txt` contient le Markdown des mêmes pages l’une après l’autre, chacune après une ligne `Source:` avec son
  URL, dans le même ordre. Les liens entre pages sont conservés tels qu’écrits dans les sources.

Seules les pages de l’arbre du site apparaissent (l’autre audience a ses propres fichiers). Seule la locale par défaut
est écrite. La sortie est déterministe.
