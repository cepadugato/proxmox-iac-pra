# Fiches sources 3.5 (OpenTofu) et 4.6 (Forgejo 15.0) — consultées le 2026-10-16

Réserve générale : WebFetch ne rend qu'un résumé/extraits produits par un petit modèle, pas la page brute. Les citations ci-dessous sont celles rendues par l'outil (parfois en segments). Niveau : officiel (éditeur) sauf mention. Les pages opentofu.org/docs sont la version « courante » : le numéro 1.13.x n'est pas affiché dans les extraits rendus [hypothèse : correspond à 1.13].

## 3.5 OpenTofu

### F1 tofu destroy = alias de apply -destroy
- URL : https://opentofu.org/docs/cli/commands/destroy/
- Citation : « a convenient way to destroy all remote objects managed by a particular OpenTofu configuration. » ; « This command is just a convenience alias for the following command: » (`tofu apply -destroy`) ; « accepts most of the options that `tofu apply` accepts, although it does not accept a plan file argument and forces the selection of the "destroy" planning mode. »
- Note : la page ne mentionne pas -target.

### F2 plan -destroy
- URL : https://opentofu.org/docs/cli/commands/plan/ ; apply : https://opentofu.org/docs/cli/commands/apply/
- Citation plan : « creates a plan whose goal is to destroy all remote objects that currently exist, leaving an empty OpenTofu state. » ; apply : « These include `-destroy`, which creates a plan to destroy all remote objects »

### F3 -target : avertissement officiel
- URL : https://opentofu.org/docs/cli/commands/plan/ (section Resource Targeting)
- Citation : « Even though `-target` and `-exclude` both accept individual resource instance addresses, » (suite paraphrasée par l'outil : raisons « legacy ») ; « Instead, these options should be used only with whole-resource addresses. » ; « This targeting capability is provided for exceptional circumstances » (récupération d'erreurs, contournement de limites). Paraphrase de l'outil : usage routinier déconseillé (dérive non détectée) ; texte exact de ce dernier passage non rendu.
- Syntaxe d'adresse : https://opentofu.org/docs/cli/state/resource-addressing/ : « tofu apply -target='aws_instance.example["foo"]' » ; existe aussi `-target-file`.

### F4 -detailed-exitcode
- URL : https://opentofu.org/docs/cli/commands/plan/
- Citation : « 0 = Succeeded with empty diff (no changes) » ; « 1 = Error » ; « 2 = Succeeded with non-empty diff (changes present) »

### F5 prevent_destroy
- URL : https://opentofu.org/docs/language/resources/behavior/
- Citation : « This meta-argument, when set to `true`, will cause OpenTofu to reject with an error any plan that would destroy the infrastructure object associated with the resource, as long as the argument remains present in the configuration. » ; « ...will prevent the use of the `tofu destroy` command once such objects are created » ; « this setting cannot prevent the remote object from being destroyed when the `resource` block is removed from configuration entirely: in that case, the `prevent_destroy` setting is removed along with it, and so OpenTofu would allow the destroy operation to succeed. » ; « if you set `destroy = false`, OpenTofu will change the `destroy` actions to a variant of `forget` action, and `prevent_destroy` will not have any effect. »
- (la page https://opentofu.org/docs/language/meta-arguments/lifecycle/ ne détaille pas prevent_destroy, elle renvoie à la page ci-dessus.)

### Conséquence (déduction, [estimation])
Détruire UNE ressource : `tofu plan -destroy -target=<type.nom>` puis apply (adresse de ressource entière), ou retirer son bloc (avec `destroy = false` pour seulement l'oublier de l'état). prevent_destroy protège les CT importés tant que le bloc existe ; il n'empêche pas la destruction si le bloc est supprimé (F5). Avec prevent_destroy, `tofu destroy` global échoue (F5).

## 4.6 Forgejo 15.0

### F6 Portées (scopes) des jetons
- URL : https://forgejo.org/docs/v15.0/user/token-scope/
- Citation : « (no scope): Not supported. A scope is required even for public repositories. » Catégories, chacune en read:/write: : activitypub, admin, issue, misc, notification, organization, package, repository, user. `read:repository` : « Grants read access to repository operations, such as getting repository files, releases, and collaborators. » ; `write:admin` : « Grants read/write/delete access for admin operations, such as running cron jobs or updating user accounts. » ; admin : « `/admin/*` API routes: Site-wide administrative operations (hidden for non-admin accounts). »
- Conséquence [estimation] : lecture d'un dépôt = `read:repository` ; la page ne parle ni de runner ni d'Actions.

### F7 Enregistrement d'un runner
- URL : https://forgejo.org/docs/v15.0/admin/actions/registration/
- Citation : création via UI « /admin/actions/runners » (ou niveau org/user/dépôt), « a unique identifier (UUID) and a confidential secret (Token) will be displayed for the new runner. » ; CLI : « forgejo forgejo-cli actions register --name runner-name --scope myorganization --secret <secret> », qui « requires system administrator access to the Forgejo instance. » ; l'API HTTP est citée comme 3e méthode sans détail. Aucune portée de jeton n'est indiquée sur la page. Portée API exacte pour l'enregistrement par API : non trouvée (l'admin UI/CLI n'exige pas de jeton d'accès).
- Page parente : https://forgejo.org/docs/v15.0/admin/actions/runner-installation/ (renvoie à la page registration).

### F8 Mise à niveau 14 -> 15
- URL : https://forgejo.org/2026-04-release-v15-0/ ; notes : https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/release-notes-published/15.0.0.md (lu jusqu'au caractère 100000 sur 165704) ; guide : https://forgejo.org/docs/v15.0/admin/upgrade/
- Citations : « it is strongly recommended to make a full backup as explained in the upgrade guide. » ; « Carefully read the breaking changes section of the release notes. » ; « The actual upgrade process is as simple as replacing the binary or container image. » ; guide : « To be safe, make sure to perform a full backup before upgrading. » ; « `forgejo dump` to collect everything into one zip file » (cas simple, instance non occupée, + dump de base séparé pour PostgreSQL/MySQL) ; « The reliable way to perform a backup is with a synchronized point-in-time snapshot of all the storage used by Forgejo. »
- Ruptures 15.0 (notes) : « Make cookie names brand independent. » / « All users need to re-login, if you haven't manually set a cookie name in the settings. » ; rootless : config par défaut passée de `/etc/gitea/app.ini` à `/var/lib/gitea/custom/conf/app.ini` (variable `GITEA_APP_INI` pour surcharger) ; jetons : « remove admin-level permissions from repo-specific & public-only access tokens » (PR 11468), génération de modèle / suppression de dépôt : « Either `write:user` or `write:organization` is required » (PR 11736) ; jetons public-only : 404 au lieu de 403 (PR 11437) ; suppression de l'option `repository.pull-request.ADD_CO_COMMITTER_TRAILERS` (PR 11096).
- Non trouvé : étapes spécifiques 14 -> 15 (la page d'annonce n'en donne pas ; elle dit de relire les notes v12/v13/v14 si on part de v11). Fin des notes (65704 car.) non lue.
