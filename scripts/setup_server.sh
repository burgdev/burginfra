#!/usr/bin/env bash
# Description: Securely configure system for k3s, Traefik, and general hardening.
# Safe to re-run (idempotent design).
#
set -euo pipefail

### GLOBALS (can be overridden by environment variables) ###
USER_NAME="${USER_NAME:-infra}"
K3S_PORT="${K3S_PORT:-6443}"
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"
DISK_DEVICE="${DISK_DEVICE:-/dev/vda}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/disk1}"

# Color definitions (using tput for better compatibility)
if [ -t 1 ]; then
  # Only define colors if output is a terminal
  b=$(tput bold)
  d=$(tput dim)
  i=$(tput sitm)
  rst=$(tput sgr0)
  u=$(tput smul)
  nu=$(tput rmul)
  R=$(tput setaf 1)
  G=$(tput setaf 2)
  Y=$(tput setaf 3)
  B=$(tput setaf 4)
  C=$(tput setaf 6)
  M=$(tput setaf 5)
  W=$(tput setaf 7)
else
  # No colors if not a terminal
  b=""; rst=""; d=""; u=""; nu=""
  R=""; G=""; Y=""; B=""; C=""; M=""; W=""
fi

# Helper function for easier color usage
s() {
  local color=$1
  shift
  echo -n "${!color}$*${rst}"
}

section() {
  echo -e "\n${b}${G}==> $1${rst}"
}

update_system_help="Updates package lists and upgrades installed packages. Installs unattended-upgrades for automatic security patches."
update_system() {
  section "Updating system packages"
  sudo apt update -qq
  sudo apt full-upgrade -y -qq
  sudo apt install -y unattended-upgrades apt-listchanges
  sudo dpkg-reconfigure --priority=low unattended-upgrades
}

configure_ssh_help="Configures SSH for key-only login, disables root login, and restricts access to the selected user."
configure_ssh() {
  section "Configuring SSH"
  local ssh_config="/etc/ssh/sshd_config"
  sudo sed -i \
    -e 's/^#\?PermitRootLogin.*/PermitRootLogin no/' \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
    -e 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords no/' \
    -e 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' \
    -e 's/^#\?UsePAM.*/UsePAM yes/' \
    -e 's/^#\?X11Forwarding.*/X11Forwarding no/' \
    -e "/^#\?AllowUsers/ d" "$ssh_config"

  echo "AllowUsers $USER_NAME" | sudo tee -a "$ssh_config" > /dev/null
  sudo systemctl restart ssh
}

setup_firewall_help="Configures UFW firewall with basic rules for k3s and general security."
setup_firewall() {
  section "Configuring firewall"
  sudo apt install -y ufw
  sudo sed -i 's/IPV6=no/IPV6=yes/' /etc/default/ufw

  sudo ufw --force reset
  sudo ufw default deny incoming
  sudo ufw default allow outgoing

  sudo ufw allow ssh
  sudo ufw allow ${K3S_PORT}/tcp
  sudo ufw allow 10250/tcp
  sudo ufw allow ${HTTP_PORT}/tcp
  sudo ufw allow ${HTTPS_PORT}/tcp

  echo "y" | sudo ufw enable || true
  sudo ufw status verbose
}

setup_fail2ban_help="Installs and enables Fail2Ban to protect SSH and other services from brute-force attacks."
setup_fail2ban() {
  section "Installing Fail2Ban"
  sudo apt install -y fail2ban
  sudo systemctl enable --now fail2ban
}

setup_auditd_help="Installs and configures auditd for system auditing."
setup_auditd() {
  section "Installing Auditd"
  sudo apt install -y auditd audispd-plugins
  sudo systemctl enable --now auditd
}

enable_apparmor_help="Ensures AppArmor is active and enforces profiles for better process isolation and system integrity."
enable_apparmor() {
  section "Enabling AppArmor"
  sudo apt install -y apparmor apparmor-utils
  sudo systemctl enable --now apparmor
  sudo aa-status || true
}

install_rootkit_hunter_help="Installs rkhunter to detect common rootkits and backdoors."
install_rootkit_hunter() {
  section "Installing Rootkit Hunter"
  sudo apt install -y rkhunter
  sudo rkhunter --update
  sudo rkhunter --propupd
}

enable_time_sync_help="Ensures system time synchronization using systemd-timesyncd."
enable_time_sync() {
  : '
  Ensures system time synchronization using systemd-timesyncd.
  '
  section "Enabling time synchronization"
  sudo timedatectl set-ntp true
}

format_and_mount_disk_help="Formats the specified DISK_DEVICE (default /dev/vda) as ext4 and mounts it to MOUNT_POINT (default /mnt/disk1)."
format_and_mount_disk() {
  section "Formatting and mounting disk"

  if mountpoint -q "$MOUNT_POINT"; then
    echo "$MOUNT_POINT is already mounted, skipping."
    return
  fi

  sudo apt install -y parted

  # Ensure partition table exists
  if ! sudo parted -m "$DISK_DEVICE" print | grep -q "^1:"; then
    echo "Creating new partition on $DISK_DEVICE..."
    sudo parted -s "$DISK_DEVICE" mklabel gpt
    sudo parted -s -a optimal "$DISK_DEVICE" mkpart primary ext4 0% 100%
  else
    echo "Partition already exists, skipping creation."
  fi

  local part="${DISK_DEVICE}1"

  # Wait for the kernel to detect the new partition
  sudo partprobe "$DISK_DEVICE"
  sleep 2

  # Format if not already ext4
  if ! sudo blkid "$part" | grep -q "ext4"; then
    echo "Formatting $part as ext4..."
    sudo mkfs.ext4 -F "$part"
  else
    echo "$part already formatted."
  fi

  sudo mkdir -p "$MOUNT_POINT"

  local uuid
  uuid=$(sudo blkid -s UUID -o value "$part")
  if ! grep -q "$uuid" /etc/fstab; then
    echo "UUID=$uuid $MOUNT_POINT ext4 defaults 0 2" | sudo tee -a /etc/fstab
  fi

  sudo mount -a
  echo "Disk mounted at $MOUNT_POINT"
}
install_k3s_help="Installs k3s lightweight Kubernetes distribution."
install_k3s() {
  : '
  Installs k3s (lightweight Kubernetes) with Traefik enabled.
  '
  section "Installing k3s"
  if ! command -v k3s >/dev/null 2>&1; then
    curl -sfL https://get.k3s.io | sh -
  else
    echo "k3s already installed, skipping."
  fi
}

secure_kubeconfig_help="Secures the kubeconfig file by setting proper ownership and permissions."
secure_kubeconfig() {
  : '
  Sets secure permissions for the kubeconfig file.
  '
  section "Securing kubeconfig"
  local cfg="/etc/rancher/k3s/k3s.yaml"
  if [ -f "$cfg" ]; then
    sudo chmod 600 "$cfg"
    sudo chown "$USER_NAME:$USER_NAME" "$cfg"
  fi
}

backup_config_help="Backs up the current configuration to a timestamped file."
backup_config() {
  : '
  Creates a timestamped backup of important configuration files.
  '
  section "Backing up configurations"
  local backup_dir="/root/config_backup_$(date +%F_%H%M)"
  sudo mkdir -p "$backup_dir"
  sudo cp -a /etc/ssh /etc/ufw /etc/fail2ban /etc/audit /etc/rancher "$backup_dir" 2>/dev/null || true
  echo "Backup stored at $backup_dir"
}

run_all_help="Runs all the following commands:"
run_all() {
  update_system
  configure_ssh
  setup_firewall
  setup_fail2ban
  setup_auditd
  enable_apparmor
  install_rootkit_hunter
  enable_time_sync
  #format_and_mount_disk
  install_k3s
  secure_kubeconfig
  #backup_config
}

### 15. Help Menu ###
help_menu() {
  echo "$(s d Usage:) sudo [$(s i ENV_OVERRIDES)] $(s b $0) [command...]

$(s Y Examples:)
  sudo ./setup_infra.sh run_all
  sudo ./setup_infra.sh install_k3s setup_firewall
  USER_NAME=root DISK_DEVICE=/dev/sdb ./setup_infra.sh format_and_mount_disk

$(s Y Environment variables:)
  $(s b USER_NAME)               User for SSH and kubeconfig ownership (default: $(s B ${USER_NAME}))
  $(s b K3S_PORT)                k3s API port (default: $(s B ${K3S_PORT}))
  $(s b HTTP_PORT)               HTTP port (default: $(s B ${HTTP_PORT}))
  $(s b HTTPS_PORT)              HTTPS port (default: $(s B ${HTTPS_PORT}))
  $(s b DISK_DEVICE)             Target disk for mounting (default: $(s B ${DISK_DEVICE}))
  $(s b MOUNT_POINT)             Mount location (default: $(s B ${MOUNT_POINT}))

$(s Y Commands:)
  $(s b run_all)                 $(s d $run_all_help)  
  $(s b update_system)           $(s d $update_system_help)  
  $(s b configure_ssh)           $(s d $configure_ssh_help)  
  $(s b setup_firewall)          $(s d $setup_firewall_help)
  $(s b setup_fail2ban)          $(s d $setup_fail2ban_help)
  $(s b setup_auditd)            $(s d $setup_auditd_help)
  $(s b enable_apparmor)         $(s d $enable_apparmor_help)
  $(s b install_rootkit_hunter)  $(s d $install_rootkit_hunter_help)
  $(s b enable_time_sync)        $(s d $enable_time_sync_help)
  $(s b install_k3s)             $(s d $install_k3s_help)
  $(s b secure_kubeconfig)       $(s d $secure_kubeconfig_help)

$(s Y Optional Commands:)
  $(s b format_and_mount_disk)   $(s d $format_and_mount_disk_help)
  $(s b backup_config)           $(s d $backup_config_help)
"
}

main() {
  if [ $# -eq 0 ]; then
    help_menu
    exit 1
  fi
  for cmd in "$@"; do
    if declare -f "$cmd" >/dev/null 2>&1; then
       echo "run '$cmd'"
      # "$cmd"
    else
      echo "Unknown command: $cmd"
      help_menu
      exit 1
    fi
  done
}

main "$@"
