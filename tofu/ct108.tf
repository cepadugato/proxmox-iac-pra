# Feuille 5.7a (D26) : CT108 (annuaire) decrit d'apres `pct config 108` (lecture seule) et importe (import-ct108.tf, id pve/108).
# Meme methode que ct100/ct101/ct122 (feuille 1.6) : hwaddr exact, description decodee (%XX), snapshot parent autoup non gere,
# features (root@pam), password/template_file_id non relisibles -> ignore_changes borne.
resource "proxmox_virtual_environment_container" "ct108" {
  node_name     = var.node
  vm_id         = 108
  description   = "Annuaire des comptes (LLDAP) pour Authelia - IP/portail/annuaire\n"
  unprivileged  = true
  start_on_boot = true
  started       = var.labo_started
  tags          = ["asso", "portail"]

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  # 1 coeur = valeur par defaut du CT : le provider ne relit pas un bloc cpu a 1 coeur a l'import (cf. ct101.tf, preuve-2.1.md).

  memory {
    dedicated = 256
    swap      = 256
  }

  disk {
    datastore_id = var.datastore
    size         = 4
  }

  features {
    nesting = true
  }

  initialization {
    hostname = "annuaire"
    dns {
      servers = ["10.0.0.254"]
    }
    ip_config {
      ipv4 {
        address = "10.0.0.36/24"
        gateway = "10.0.0.254"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.macs["108"]
    firewall    = true
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
