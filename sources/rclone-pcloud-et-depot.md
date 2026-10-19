# Sources : rclone/pCloud (5.13) et API Forgejo (4.10)
Consultation : 2026-10-16. Toutes les pages ont été lues via WebFetch : les « citations » ci-dessous sont des RÉSUMÉS WebFetch (modèle rapide), sauf les extraits entre guillemets que l'outil a rapportés comme texte de la page. Niveau : officiel (éditeur) sauf mention.

## Fiche 5.13-a : pCloud, remote sans navigateur
- URL : https://rclone.org/pcloud/ (résumé WebFetch)
- Citation : « how to set it up on a machine without an internet-connected web browser available. » ; « you will need to set the hostname in 'Edit advanced config', otherwise you might get a token error. » ; hostname : « you will need to set it by hand if you are using remote config with rclone authorize. »
- Lecture [fait] : `rclone authorize` depuis une machine avec navigateur est la voie documentée ; le hostname est à régler à la main (config avancée). Le détail de la commande est dans la page « remote setup » de rclone (https://rclone.org/remote_setup/), NON consultée.

## Fiche 5.13-b : région EU/US
- URL : https://rclone.org/pcloud/ (résumé WebFetch)
- Citation : « api.pcloud.com » = « Original/US region » ; « eapi.pcloud.com » = « EU region ».

## Fiche 5.13-c : lecture seule
- URL : https://rclone.org/pcloud/ (résumé WebFetch)
- Constat : la page ne mentionne AUCUNE portée (scope) lecture seule ; seule option voisine : « Use client credentials OAuth flow ». [fait : absence dans la page] ; l'inexistence côté pCloud n'est pas établie (non vérifiée sur la doc pCloud).
- Protection côté rclone : non sourcée ici (pistes à vérifier, [hypothèse] : `rclone copy`/`check` seulement, jamais `sync`, option `--immutable`/`--backup-dir`).

## Fiche 5.13-d : hachages et rclone check
- URL : https://rclone.org/pcloud/ (résumé WebFetch). Citation : « pCloud supports MD5 and SHA1 hashes in the US region, and SHA1 and SHA256 hashes in the EU region. »
- URL : https://rclone.org/commands/rclone_check/ (résumé WebFetch). Citation : check « compares sizes and hashes (MD5 or SHA1) and logs a report of files that don't match » ; `--download` « will download the data from both remotes and check them against each other on the fly » (utile pour les remotes sans hachage commun) ; `--size-only` compare les tailles seules.
- Note [hypothèse] : en région EU, SHA1 est commun avec le local, donc `check` devrait comparer sans `--download`.

## Fiche 5.13-e : version stable et installation
- URL : https://downloads.rclone.org/version.txt (résumé WebFetch) : « rclone v1.75.2 » (au 2026-10-16).
- URL : https://rclone.org/install/ (résumé WebFetch) : script officiel `sudo -v ; curl https://rclone.org/install.sh | sudo bash` (vérifie la version installée avant de retélécharger) ; binaire précompilé `rclone-current-linux-amd64.zip` à copier dans /usr/bin/ ; « The distributed versions of rclone are often quite out of date » (paquets de distribution). Page : aucun .deb mentionné (le .deb existe sur downloads.rclone.org, NON vérifié).

## Fiche 4.10 : API Forgejo, création et PATCH de dépôt
- Limite : outil Bash indisponible, donc swagger de l'instance locale (http://localhost:3000/api/swagger) NON lu (WebFetch refuse localhost). Source utilisée : https://codeberg.org/swagger.v1.json, version rapportée « 16.0.0-dev-785-465b60ef+gitea-1.22.0 » (Forgejo 16 dev, PAS 15) : à recouper avec l'instance locale.
- CreateRepoOption (résumé WebFetch) : requis `name` ; propriétés : auto_init, default_branch, description, gitignores, issue_labels, license, name, object_format_name, private (« Whether the repository is private »), readme, template, trust_model. Opérations : `/user/repos` POST (createCurrentUserRepo) utilise CreateRepoOption ; chemin org vu : `/org/{org}/repos` POST (déprécié, résumé « Create a repository in an organization ») ; `/orgs/{org}/repos` non vu dans la portion lue.
- EditRepoOption (PATCH /repos/{owner}/{repo}) : contient `has_pull_requests` (« either true to allow pull requests, or false to prevent pull request »), `has_actions` (active/désactive l'unité actions), has_issues, has_packages, has_projects, has_releases, has_wiki, private, archived, etc. AUCUN champ d'interdiction des forks dans EditRepoOption ; `forks_disabled` n'existe que dans la définition GeneralRepoSettings (réglage global de l'instance, en lecture dans l'API).

## Recoupement local (fil principal, 2026-10-16T22:25+02:00)
Commande : `curl -s http://localhost:3000/swagger.v1.json` puis lecture JSON.
Sortie : version `14.0.3+gitea-1.22.0` ; `POST /user/repos` présent ; `POST /orgs/{org}/repos` présent ; EditRepoOption contient `has_actions`, `has_pull_requests`, `private`, et AUCUN champ fork.
→ [fait, instance locale] Aucune interdiction de fork par dépôt via l'API en 14.0.3 ; à re-vérifier après la montée en 15.0 (feuille 4.9). Dépôt privé = seuls les collaborateurs peuvent forker [hypothèse].
