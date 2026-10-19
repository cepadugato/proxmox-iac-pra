# Décision D25 (feuille 5.6a) : verrou de cible. L'état de pve porte cible = "pve", celui du labo cible = "labo".
# Planifier avec la mauvaise cible change triggers_replace, donc propose de détruire/recréer le verrou : prevent_destroy
# fait échouer le plan, quelle que soit la commande ou la variable passée à tofu. Ne pas retirer ce fichier.
# La précondition lie aussi la cible à son endpoint : un endpoint du labo avec cible = "pve" (ou l'inverse) est refusé.
locals {
  endpoint_de_cible = {
    pve  = "https://127.0.0.1:8006"
    labo = "https://10.255.70.2:8006"
  }
}

resource "terraform_data" "verrou_cible" {
  triggers_replace = var.cible

  lifecycle {
    prevent_destroy = true

    precondition {
      # secours (5.15) : endpoint variable, mais jamais celui de pve ni celui du labo ; en répétition, celui du labo seulement
      condition = (var.cible == "secours"
        ? (var.repetition_labo
          ? trimsuffix(var.proxmox_endpoint, "/") == local.endpoint_de_cible["labo"]
        : !contains(values(local.endpoint_de_cible), trimsuffix(var.proxmox_endpoint, "/")))
      : trimsuffix(var.proxmox_endpoint, "/") == lookup(local.endpoint_de_cible, var.cible, ""))
      error_message = "REFUS : l'endpoint ne correspond pas à la cible déclarée (var.cible)."
    }
  }
}
