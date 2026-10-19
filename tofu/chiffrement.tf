# Feuille 4.3 : état chiffré (PBKDF2 + AES-GCM), chemin unique etat/pve.tfstate (hors Git).
# La phrase n'est JAMAIS dans un fichier : variable d'environnement TF_VAR_tofu_enc_passphrase
# (poste : recettes/chiffre-4.3.sh ; CI : secret de dépôt TOFU_ENC_PASSPHRASE). Perdre la phrase = état irrécupérable.
variable "tofu_enc_passphrase" {
  type      = string
  sensitive = true
}

terraform {
  backend "local" {
    path = "etat/pve.tfstate"
  }

  encryption {
    key_provider "pbkdf2" "etat" {
      passphrase = var.tofu_enc_passphrase
    }

    method "aes_gcm" "etat" {
      keys = key_provider.pbkdf2.etat
    }

    state {
      method   = method.aes_gcm.etat
      enforced = true
    }

    plan {
      method   = method.aes_gcm.etat
      enforced = true
    }
  }
}
