# Fiche 4.1 — CI Forgejo : runner, setup-opentofu, secrets (consultée 2026-10-16)

Réserve : WebFetch = modèle résumeur ; guillemets rapportés par l'outil.

## Compatibilité runner 13.2.0 / Forgejo 14.0.3
- [non trouvé] Aucune déclaration officielle de compatibilité. Pages ouvertes sans énoncé : https://code.forgejo.org/forgejo/runner/releases (notes v13.2.0 et v13.0.0 : « Minimum or compatible Forgejo server version: Not stated »), https://forgejo.org/docs/latest/admin/actions/, .../admin/runner-installation/, .../admin/actions/configuration/, https://forgejo.org/docs/latest/admin/release-schedule/. Seul indice : « As long as they can connect to a Forgejo instance using the same protocol, they will be given tasks to run. » (admin/runner-installation).
- [fait] Runner v13.2.0 « released this 2026-09-18 21:27:02 +00:00 » (Stable) ; assets `forgejo-runner-13.2.0-linux-amd64` (+ .asc, .sha256, .xz) et linux-arm64 ; hachages non affichés par la page. v13.0.0 (2026-08-03) : « Forgejo v13 contains breaking changes in order to improve security and predictability of Forgejo Actions. »
- [fait] Forgejo 14.0 : sortie 15 janvier 2026, fin de vie 30 avril 2026 (release-schedule, colonnes lues par l'outil). ALERTE : 14.0.x serait hors support à la date du 2026-10-16 ; la page ne liste pas le dernier patch. 14.0.3 : seulement source secondaire (Fedora, 2026-03-09 ; PR git.bros.ninja) ; notes officielles non obtenues.

## Installation binaire (officiel) — https://forgejo.org/docs/latest/admin/actions/installation/binary/
- « Forgejo Runner requires that Git is installed, and has been tested with a minimum version of Git 2.24.3. »
- Téléchargement : « https://code.forgejo.org/forgejo/runner/releases/download/v » ; clé : « gpg --keyserver hkps://keys.openpgp.org --recv EB114F5E6C0DC2BCDD183550A4B61A2DC5923710 » ; « gpg --verify forgejo-runner.asc forgejo-runner » ; « chmod +x forgejo-runner » ; « cp forgejo-runner /usr/local/bin/forgejo-runner » ; « forgejo-runner -v ».
- Utilisateur : « useradd --create-home runner » ; « usermod -aG docker runner » (Docker) ; « sudo loginctl enable-linger runner » (Podman). Démarrage : « forgejo-runner daemon -c runner-config.yml » ; unité systemd forgejo-runner.service. Config : `forgejo-runner generate-config` (via résumé de recherche).
## Installation Docker (officiel) — .../admin/actions/installation/docker/
- Image « data.forgejo.org/forgejo/runner:13 » (sortie version « v13.0.0 », utilisateur uid 1000) ; `docker run --rm data.forgejo.org/forgejo/runner:13 forgejo-runner generate-config > data/runner-config.yml` ; compose avec `docker:dind` `privileged: 'true'`, `DOCKER_HOST: tcp://docker-in-docker:2375`, `user: 1001:1001`, commande `forgejo-runner daemon --config runner-config.yml`. Pas de docker.sock sur cette page.
## Enregistrement — https://forgejo.org/docs/latest/admin/actions/registration/
- Interface : « /admin/actions/runners », « /org/{org}/settings/actions/runners », « /user/settings/actions/runners », « /{owner}/{repository}/settings/actions/runners » ; bouton « Create new runner » → UUID et token à copier dans le fichier de config (`server: connections: forgejo: url, uuid, token`).
- Hors ligne : « forgejo forgejo-cli actions register --name runner-name --scope myorganization --secret <40 hex> ».
- « forgejo-runner register » est marqué « (deprecated) » dans cette page. `create-runner-file` : NON documenté sur ces pages (cité seulement par un résumé de recherche comme « forgejo-runner create-runner-file --secret ») ; syntaxe à lire par `forgejo-runner create-runner-file --help`. Étiquettes : syntaxe « <label-name>:<label-type>://<default-image> » (admin/actions/configuration).

## setup-opentofu sur Forgejo
- [fait] https://github.com/opentofu/setup-opentofu (éditeur) : `- uses: opentofu/setup-opentofu@v2` ; entrées `tofu_version` (défaut latest), `tofu_wrapper` (défaut true), `github_token` : « Defaults to the value of the `GITHUB_TOKEN` environment variable unless running on Forgejo or Gitea. » ; dernier tag v2 non affiché.
- [fait] https://forgejo.org/docs/latest/user/actions/reference/ : `uses:` relatif résolu via `DEFAULT_ACTIONS_URL` (défaut `https://data.forgejo.org`) « This can cause your workflow to break if the actions you want to use are not available on the specified instance. » ⇒ URL complète : `uses: https://github.com/opentofu/setup-opentofu@v2` [hypothèse : forme d'URL complète non testée]. Pas de jeton requis par l'action sur Forgejo (cf. github_token ci-dessus).
## Secrets de dépôt — https://forgejo.org/docs/latest/user/actions/basic-concepts/
- « A repository, a user or an organization can hold secrets, a set of key/value pairs. » Chemins : « /{owner}/{repo}/settings/actions/secrets », « /org/{org}/settings/actions/secrets », « /user/settings/actions/secrets » ; « Once the secret is added, its value cannot be changed or displayed. » Usage : `${{ secrets.NOM }}` ; vide pour pull_request d'un fork (user/actions/reference).

## Verdict
PARTIEL. Établi : binaire/Docker, enregistrement UI + CLI, secrets, setup-opentofu. Non trouvé : compatibilité 13.2.0 ↔ 14.0.3 (aucun énoncé officiel) ; syntaxe de create-runner-file ; test réel de setup-opentofu sur Forgejo.
