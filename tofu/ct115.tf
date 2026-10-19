# Feuille 5.7b (D28) : CT115 (miroir) decrit d'apres `pct config 115` (lecture seule) et importe (import-ct115.tf, id pve/115).
# Meme methode que ct108.tf (5.7a) : hwaddr exact, description decodee (%XX), snapshot parent non gere,
# features (root@pam), password/template_file_id non relisibles -> ignore_changes borne.
# Montages lies (dossier de l'hote) : root@pam seul peut les poser, vzdump ne les sauvegarde pas (feuille 5.16) ;
# decrits sur pve (features_root), en ignore_changes : une cible sans ces dossiers garde ceux de pct restore.
resource "proxmox_virtual_environment_container" "ct115" {
  node_name     = var.node
  vm_id         = 115
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
    dedicated = 512
    swap      = 512
  }

  disk {
    datastore_id = var.datastore
    size         = 8
  }

  dynamic "mount_point" {
    for_each = var.features_root ? [1] : []
    content {
      volume = "/tank/miroir-apt"
      path   = "/srv/miroir"
    }
  }

  dynamic "mount_point" {
    for_each = var.features_root ? [1] : []
    content {
      volume    = "/tank/scripts-http"
      path      = "/srv/scripts"
      read_only = true
    }
  }

  initialization {
    hostname = "miroir"
    dns {
      servers = ["10.0.0.254"]
    }
    ip_config {
      ipv4 {
        address = "10.0.0.25/24"
        gateway = "10.0.0.254"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.macs["115"]
  }

  operating_system {
    type             = "debian"
    template_file_id = var.template_file_id # non relisible apres creation
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      timeout_start,                        # defaut provider, absent de l'etat importe
      mount_point,                          # montages lies : root@pam, hors sauvegarde (5.16)
      operating_system[0].template_file_id, # non relisible
      initialization[0].user_account,       # password/cles : non relisibles
      vm_id,                                # l'import laisse vm_id vide dans l'etat (cf. 1.6)
    ]
  }
}
