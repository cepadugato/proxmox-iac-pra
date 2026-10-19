# Feuille 5.7a (D26) : CT128 (homarr) decrit d'apres `pct config 128` (lecture seule) et importe (import-ct128.tf, id pve/128).
# Meme methode que ct100/ct101/ct122 (feuille 1.6) : hwaddr exact, description decodee (%XX), snapshot parent autoup non gere,
# features (root@pam), password/template_file_id non relisibles -> ignore_changes borne.
# Non decrit (aucun attribut du provider, root@pam) : timezone Europe/Paris et acces tun
# (lxc.cgroup2.devices.allow c 10:200 rwm, lxc.mount.entry /dev/net/tun). Une recreation par tofu les perd :
# les remettre a la main, ou restaurer la sauvegarde par-dessus (pct restore garde la configuration).
resource "proxmox_virtual_environment_container" "ct128" {
  node_name     = var.node
  vm_id         = 128
  description   = "<div align='center'>\n  <a href='https://community-scripts.org' target='_blank' rel='noopener noreferrer'>\n    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>\n  </a>\n\n  <h2 style='font-size: 24px; margin: 20px 0;'>homarr LXC</h2>\n\n  <p style='margin: 16px 0;'>\n    <a href='https://community-scripts.org/donate' target='_blank' rel='noopener noreferrer'>\n      <img src='https://img.shields.io/badge/❤️-Sponsoring%20%26%20Donations-FF5E5B' alt='Sponsoring and donations' />\n    </a>\n  </p>\n\n  <p style='margin: 12px 0;'>\n    <a href='https://community-scripts.org/scripts/homarr' target='_blank' rel='noopener noreferrer'>\n      <img src='https://img.shields.io/badge/📦-Open%20Script%20Page-00617f' alt='Open script page' />\n    </a>\n  </p>\n\n  <span style='margin: 0 10px;'>\n    <i class=\"fa fa-github fa-fw\" style=\"color: #f5f5f5;\"></i>\n    <a href='https://github.com/community-scripts/ProxmoxVE' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>GitHub</a>\n  </span>\n  <span style='margin: 0 10px;'>\n    <i class=\"fa fa-comments fa-fw\" style=\"color: #f5f5f5;\"></i>\n    <a href='https://github.com/community-scripts/ProxmoxVE/discussions' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Discussions</a>\n  </span>\n  <span style='margin: 0 10px;'>\n    <i class=\"fa fa-exclamation-circle fa-fw\" style=\"color: #f5f5f5;\"></i>\n    <a href='https://github.com/community-scripts/ProxmoxVE/issues' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Issues</a>\n  </span>\n</div>\n"
  unprivileged  = true
  start_on_boot = true
  started       = var.labo_started
  tags          = ["arr", "community-script", "dashboard"]

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
    size         = 8
  }

  features {
    nesting = true
    keyctl  = var.features_root ? true : null
    fuse    = var.features_root ? true : null
  }

  initialization {
    hostname = "homarr"
    dns {
      servers = ["10.0.0.254"]
    }
    ip_config {
      ipv4 {
        address = "10.0.0.35/24"
        gateway = "10.0.0.254"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.macs["128"]
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
