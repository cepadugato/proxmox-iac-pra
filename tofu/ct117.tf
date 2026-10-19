# Feuille 5.7b (D28) : CT117 (provisionnement) decrit d'apres `pct config 117` (lecture seule) et importe (import-ct117.tf, id pve/117).
# Meme methode que ct108.tf (5.7a) : hwaddr exact, description decodee (%XX), snapshot parent non gere,
# features (root@pam), password/template_file_id non relisibles -> ignore_changes borne.
resource "proxmox_virtual_environment_container" "ct117" {
  node_name     = var.node
  vm_id         = 117
  description   = "parc-as-code — appliance de provisionnement PXE (remplace lusage de la VM 103)\n"
  unprivileged  = true
  start_on_boot = true
  started       = var.labo_started

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  cpu {
    architecture = "amd64"
    cores        = 2
  }

  memory {
    dedicated = 2048
    swap      = 512
  }

  disk {
    datastore_id = var.datastore
    size         = 16
  }

  features {
    nesting = true
    keyctl  = var.features_root ? true : null
  }

  initialization {
    hostname = "provisionnement"
    dns {
      servers = ["10.0.0.254"]
    }
    ip_config {
      ipv4 {
        address = "10.0.0.14/24"
        gateway = "10.0.0.254"
      }
    }
    ip_config {
      ipv4 {
        address = "10.10.20.1/24"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.macs["117"]
  }

  network_interface {
    name        = "eth1"
    bridge      = "vmbr2" # pont interne sans port (reseau PXE isole)
    mac_address = var.macs["117-eth1"]
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
