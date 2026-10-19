# Feuille 5.7b (D28) : CT9020 (netbootxyz-poc) decrit d'apres `pct config 9020` (lecture seule) et importe (import-ct9020.tf, id pve/9020).
# Meme methode que ct108.tf (5.7a) : hwaddr exact, description decodee (%XX), snapshot parent non gere,
# features (root@pam), password/template_file_id non relisibles -> ignore_changes borne.
# Montages lies (dossier de l'hote) : root@pam seul peut les poser, vzdump ne les sauvegarde pas (feuille 5.16) ;
# decrits sur pve (features_root), en ignore_changes : une cible sans ces dossiers garde ceux de pct restore.
# CT privilegie : le jeton ne peut pas le creer ; sur une cible de secours il est restaure par root puis importe (5.8b).
resource "proxmox_virtual_environment_container" "ct9020" {
  node_name     = var.node
  vm_id         = 9020
  unprivileged  = false
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

  dynamic "mount_point" {
    for_each = var.features_root ? [1] : []
    content {
      volume = "/tank/iso-netboot"
      path   = "/opt/nbxyz/assets/local"
    }
  }

  initialization {
    hostname = "netbootxyz-poc"
    # pas de nameserver dans pct config 9020 : le CT herite du DNS de l'hote
    ip_config {
      ipv4 {
        address = "10.0.0.19/24"
        gateway = "10.0.0.254"
      }
    }
    ip_config {
      ipv4 {
        address = "10.10.10.1/24"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.macs["9020"]
  }

  network_interface {
    name        = "eth1"
    bridge      = "vmbr1" # pont interne sans port (reseau PXE isole)
    mac_address = var.macs["9020-eth1"]
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
