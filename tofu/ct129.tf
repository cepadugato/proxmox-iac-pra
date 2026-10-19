# Feuille 5.7b (D28) : CT129 (import-fiches) decrit d'apres `pct config 129` (lecture seule) et importe (import-ct129.tf, id pve/129).
# Meme methode que ct108.tf (5.7a) : hwaddr exact, description decodee (%XX), snapshot parent non gere,
# features (root@pam), password/template_file_id non relisibles -> ignore_changes borne.
# Montages lies (dossier de l'hote) : root@pam seul peut les poser, vzdump ne les sauvegarde pas (feuille 5.16) ;
# decrits sur pve (features_root), en ignore_changes : une cible sans ces dossiers garde ceux de pct restore.
resource "proxmox_virtual_environment_container" "ct129" {
  node_name     = var.node
  vm_id         = 129
  description   = "Service import des fiches de test PC vers Snipe-IT (IP/fiches, D20). Cree 2026-10-02.\n"
  unprivileged  = true
  start_on_boot = true
  started       = var.labo_started

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  # 1 coeur = valeur par defaut du CT : le provider ne relit pas un bloc cpu a 1 coeur a l'import (cf. ct101.tf, preuve-2.1.md).

  memory {
    dedicated = 512
    swap      = 256
  }

  disk {
    datastore_id = var.datastore
    size         = 4
  }

  features {
    nesting = true
  }

  dynamic "mount_point" {
    for_each = var.features_root ? [1] : []
    content {
      volume = "/tank/partage/Fiches"
      path   = "/srv/fiches/entree"
    }
  }

  initialization {
    hostname = "import-fiches"
    dns {
      servers = ["10.0.0.254"]
    }
    ip_config {
      ipv4 {
        address = "10.0.0.37/24"
        gateway = "10.0.0.254"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.macs["129"]
  }

  operating_system {
    type             = "debian"
    template_file_id = var.template_file_id # non relisible apres creation
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      timeout_start,                        # defaut provider, absent de l'etat importe
      features,                             # root@pam requis pour ecrire les features
      mount_point,                          # montages lies : root@pam, hors sauvegarde (5.16)
      operating_system[0].template_file_id, # non relisible
      initialization[0].user_account,       # password/cles : non relisibles
      vm_id,                                # l'import laisse vm_id vide dans l'etat (cf. 1.6)
    ]
  }
}
