# Chiffrement d'état OpenTofu : faits pour 4.3

Consulté le 2026-10-17 (WebFetch). Niveau : officiel (éditeur, opentofu.org/docs).
Réserve : WebFetch renvoie un extrait passé par un petit modèle. Les citations ci-dessous sont celles de ce retour, pas une copie intégrale de la page. La version de la doc (v1.13) n'est pas affichée dans les extraits : [hypothèse] qu'elle correspond.

Sources :
- E = https://opentofu.org/docs/language/state/encryption/
- I = https://opentofu.org/docs/cli/commands/init/
- L = https://opentofu.org/docs/language/settings/backends/local/

## 1. Syntaxe (E)
- [fait] Les blocs `key_provider`, `method`, `state`, `plan`, `fallback` sont documentés dans E (bloc englobant `terraform { encryption { ... } }` : non cité dans l'extrait, [hypothèse] d'après la doc connue, à confirmer en relisant E).
- pbkdf2 : `key_provider "pbkdf2" "foo" {` avec le commentaire « Specify a long / complex passphrase (min. 16 characters) ».
  - passphrase : « Enter a long and complex passphrase. Required if `chain` is not specified. » Minimum 16 caractères.
  - key_length : « Number of bytes to generate as a key. » min 1, défaut 32.
  - iterations : « Number of iterations. » min 200.000, défaut 600.000.
  - salt_length : « Length of the salt for the key derivation. » min 1, défaut 32.
  - hash_function : « Specify either `sha256` or `sha512` to use as a hash function. `sha1` is not supported. » défaut sha512.
  - chain : « Receive the passphrase from another key provider. »
- aes_gcm : `method "aes_gcm" "yourname" { keys = key_provider.your_key_provider_type.your_key_provider_name }` ; « The AES-GCM method needs 16, 24, or 32-byte keys. »
- state/plan : `state { method = method.some_method_type.some_method_name }`, idem `plan { ... }`.
- enforced : `state { enforced = true }` ; sert à « prevent unencrypted data from being written in the absence of an environment variable ».
- fallback : `fallback { method = method.some_method.old_method_name }` ; « If OpenTofu fails to read your state or plan file with the new method, it will automatically try the fallback method. » « When OpenTofu saves your state or plan file, it will always use the new method and not the fallback. »

## 2. Fournir la phrase sans fichier ni clair (E)
- [fait] `var.` est utilisable : l'exemple de E déclare `variable "passphrase" { default = "changeme!" sensitive = true }` puis `passphrase = var.passphrase`.
- [fait] « Variables and locals can be used in configuration, but may not contain any references to data in the state » et « All values must be able to be resolved during `tofu init` before the state is available. »
- [fait] TF_ENCRYPTION existe : « or using the `TF_ENCRYPTION` environment variable. » Contenu = HCL du bloc (key_provider/method/state... sans le wrapper `terraform { encryption {} }` dans l'exemple). Exemple shell : `TF_ENCRYPTION=$(cat <<EOF ... key_provider "some_key_provider" "some_name" { ... } ... EOF)`. Fusion : « overriding any code-based settings with the environment ones. »
- Non trouvé dans E : phrase explicite sur `sensitive`/TF_VAR_xxx pour la passphrase (seul l'exemple avec `sensitive = true` existe). Que TF_VAR_passphrase alimente `var.passphrase` est le mécanisme général des variables d'entrée, non vérifié ici sur la page dédiée.
- Non trouvé : si TF_ENCRYPTION doit être posée à chaque commande. Déduction [hypothèse] : oui, la config est lue à chaque exécution.

## 3. Migration (E)
- Clair -> chiffré (« pre-existing project ») : « When you first configure encryption on an existing project, your state and plan files are unencrypted. » OpenTofu refuse de les lire sans l'étape suivante. Étapes : 1 ajouter `method "unencrypted" "migrate" {}` ; 2 key provider ; 3 méthode de chiffrement ; 4 lier la méthode dans `state` ; 5 ajouter `fallback { method = method.unencrypted.migrate }` ; 6 « Run "tofu apply". » ; 7 « Remove the "fallback" block above and consider adding the "enforced" option » ; 8 répéter pour `plan{}`.
- Retour arrière (« rolling back encryption ») : 1 laisser la méthode d'origine ; 2 ajouter la méthode `unencrypted` ; 3 désactiver/retirer `enforced` ; 4 déplacer la méthode d'origine dans `fallback` ; 5 référencer `unencrypted` comme méthode principale ; 6 `tofu apply` ; 7 « Remove the "state" block once the migration is complete. » ; 8 idem pour `plan{}`. Avertissement : « Do not remove or modify the original encryption method until you have finished the migration. »
- E conseille : « make a temporary backup of your unencrypted state file. » et « make sure you have backups of your keys. »

## 4. Longueur minimale
- [fait] 16 caractères (tableau d'options pbkdf2 de E et commentaire de l'exemple).

## 5. Backend local + migration (I, L)
- L : path = « (Optional) The path to the `tfstate` file. This defaults to "terraform.tfstate" relative to the root module by default. »
- I : « Either `-reconfigure` or `-migrate-state` must be supplied to update the backend configuration. » ; « The `-migrate-state` option will attempt to copy existing state to the new backend » (prompts possibles) ; « The `-force-copy` option suppresses these prompts and answers "yes" to the migration questions. » ; « Enabling `-force-copy` also automatically enables the `-migrate-state` option. » ; « The `-reconfigure` option disregards any existing configuration, preventing migration of any existing state. »

## 6. plan sans phrase, fichiers .backup
- Non trouvé : message d'erreur exact. E dit seulement : « Once you enable encryption, OpenTofu cannot read your state file without the correct key. » et que OpenTofu « will refuse to read plain text data » si le chiffrement est activé sur un état clair sans fallback. Donc [hypothèse] : plan échoue, texte d'erreur non établi.
- Non trouvé : chiffrement des fichiers .backup. E ne les mentionne pas (hors conseil de sauvegarde manuelle). L : `-backup=FILENAME` change le nom ; « You can use `-backup=-` ... to disable the creation of backup files altogether. » (option CLI de commande, pas du bloc backend). [hypothèse] non vérifiée : le .backup est écrit par la même couche d'état donc chiffré ; à vérifier avec une recette réelle.
