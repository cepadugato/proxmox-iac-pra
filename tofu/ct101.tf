# Feuille 2.1 : CT101 (demandes) importe (import-ct101.tf, id pve/101). Meme methode que ct100.tf (feuille 1.6).
# Specifique : 1 coeur, nameserver 10.0.0.254 (initialization.dns), features nesting seul.
# Pieges traites comme CT100 : description decodee (%XX), hwaddr exact, snapshot parent autoup non gere,
# features (root@pam), password/template_file_id non relisibles -> ignore_changes borne.
resource "proxmox_virtual_environment_container" "ct101" {
  node_name     = var.node
  vm_id         = 101
  description   = "Gestion des demandes de materiel - FastAPI+SQLite (application tierce) - projet IP/gestion-demandes\n"
  unprivileged  = true
  start_on_boot = true
  started       = var.labo_started

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  # 1 coeur = valeur par defaut du CT (pct config : cores: 1) ; le provider ne relit pas un bloc cpu
  # a 1 coeur a l'import (plan: "+ cpu" persistant), donc le bloc est omis. Voir preuve-2.1.md.

  memory {
    dedicated = 1024
    swap      = 512
  }

  disk {
    datastore_id = var.datastore
    size         = 8
  }

  features {
    nesting = true
  }

  initialization {
    hostname = "demandes"
    dns {
      servers = ["10.0.0.254"]
    }
    ip_config {
      ipv4 {
        address = "10.0.0.22/24"
        gateway = "10.0.0.254"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.macs["101"]
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
      operating_system[0].template_file_id, # non relisible
      initialization[0].user_account,       # password/cles : non relisibles
      vm_id,                                # l'import laisse vm_id vide dans l'etat (cf. 1.6)
    ]
  }
}
