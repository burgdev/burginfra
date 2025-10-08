#!/usr/bin/env bash
# Description: Securely configure system for k3s, Traefik, and general hardening.
# Safe to re-run (idempotent design).
#
# IMPORTANT: This script need to run on the serve!

set -euo pipefail

### GLOBALS (can be overridden by environment variables) ###
USER_NAME="${USER_NAME:-$USER}"
TIMEZONE="${TIMEZONE:-'Europe/Zurich'}"

DISK_DEVICE="${DISK_DEVICE:-/dev/vda}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/disk1}"

KDRIVE_ID="${KDRIVE_ID:-}"
KDRIVE_PATH="${KDRIVE_PATH:-burgdev/burginfra/mnt}"
WEBDAV_USER="${WEBDAV_USER:-}"
WEBDAV_PASSWORD="${WEBDAV_PASSWORD:-}"
WEBDAV_MOUNT_PATH="${WEBDAV_MOUNT_PATH:-/mnt/kdrive}"
WEBDAV_URL="${WEBDAV_URL:-}"

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
  echo -e "${b}${G}==> $1${rst}"
}

setup_locale_help="Configures system locale and timezone settings. Uses TIMEZONE environment variable (default: Europe/Zurich)."
setup_locale() {
  section "Configuring system locale and timezone"
  sudo apt update -qq
  sudo apt install -y locales tzdata
  
  # Set timezone from environment variable
  echo "Setting timezone to: $TIMEZONE"
  sudo timedatectl set-timezone "$TIMEZONE"
  
  # Configure locales
  sudo locale-gen en_US.UTF-8 de_CH.UTF-8
  sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
  
  # Export locale settings for current session
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
  
  # Show current timezone setting
  echo "Current time zone: $(timedatectl | grep 'Time zone')"
}

update_system_help="Updates package lists and upgrades installed packages. Installs unattended-upgrades for automatic security patches."
update_system() {
  section "Updating system packages"
  sudo apt update -qq
  sudo apt full-upgrade -y -qq
  sudo apt install -y unattended-upgrades apt-listchanges
  sudo dpkg-reconfigure -f noninteractive --priority=low unattended-upgrades
}

configure_ssh_help="Configures SSH for key-only login, disables root login, and restricts access to the selected user."
configure_ssh() {
  section "Configuring SSH"
  local ssh_config="/etc/ssh/sshd_config"
  
  # Remove any existing settings (except TOTP-specific ones)
  sudo sed -i -E \
    -e '/^(#\s*)?(PermitRootLogin|PasswordAuthentication|PermitEmptyPasswords|X11Forwarding|AllowUsers)\s+/d' \
    "$ssh_config"
  
  # Add the basic security settings at the end of the file
  {
    echo "PermitRootLogin no"
    echo "PasswordAuthentication no"
    echo "PermitEmptyPasswords no"
    echo "X11Forwarding no"
    echo "AllowUsers $USER_NAME"
  } | sudo tee -a "$ssh_config" > /dev/null
  
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

  # Allow SSH (with rate limiting to prevent brute force)
  sudo ufw limit 22/tcp comment 'Rate limit SSH'

  sudo ufw allow 80/tcp comment 'HTTP'
  sudo ufw allow 443/tcp comment 'HTTPS'

  sudo ufw allow 6443/tcp comment 'k3s API'
  sudo ufw allow 10250/tcp comment 'k3s kubelet'
  
  # Allow Kubernetes node port range (30000-32767)
  sudo ufw allow 30000:32767/tcp comment 'Kubernetes NodePort range'
  sudo ufw allow 30000:32767/udp comment 'Kubernetes NodePort range'
  
  # Enable UFW with a 30-second timeout to prevent lockout
  echo "Enabling UFW with 30-second timeout..."
  echo "y" | sudo ufw enable

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

enable_time_sync_help="Ensures system time synchronization using systemd-timesyncd."
enable_time_sync() {
  section "Enabling time synchronization"
  sudo timedatectl set-ntp true
}

_secure_kubeconfig_help="Secures the kubeconfig file by setting proper ownership and permissions."
_secure_kubeconfig() {
  section "Securing kubeconfig"
  local cfg="/etc/rancher/k3s/k3s.yaml"
  if [ -f "$cfg" ]; then
    sudo chmod 600 "$cfg"
    sudo chown "$USER_NAME:$USER_NAME" "$cfg"
  fi
}

install_utils_help="Install commonly used tools, like rsync, rclone, ..."
install_utils() {
  if ! command -v gpg >/dev/null 2>&1; then
    sudo apt install -y gpg
  fi
  if ! command -v vim >/dev/null 2>&1; then
    section "Installing vim"
    sudo apt install -y vim
  fi
  if ! command -v rsync >/dev/null 2>&1; then
    section "Installing rsync"
    sudo apt install -y rsync
  fi
  # In your install_utils function
  section "Installing/updating rclone"
  curl -s https://rclone.org/install.sh | sudo bash -s -- --yes || {
      echo "$(s Y "Warning: Failed to install/update rclone. Continuing...")" >&2
  }
  if ! command -v kopia >/dev/null 2>&1; then
    section "Installing kopia"
    curl -s https://kopia.io/signing-key | sudo gpg --dearmor -o /usr/share/keyrings/kopia-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/kopia-keyring.gpg] https://packages.kopia.io/apt/ stable main" | sudo tee /etc/apt/sources.list.d/kopia.list
    sudo apt update
    sudo apt install -y kopia
  fi
}

install_k3s_help="Installs k3s lightweight Kubernetes distribution."
install_k3s() {
  section "Installing k3s"
  if ! command -v k3s >/dev/null 2>&1; then
    curl -sfL https://get.k3s.io | sh -
    _secure_kubeconfig
  else
    echo "k3s already installed, skipping."
  fi
}

configure_totp_help="Configures TOTP (Google Authenticator) for SSH authentication."
configure_totp() {
    section "Configuring TOTP Authentication"
    
    # Install required packages
    sudo apt install -y libpam-google-authenticator qrencode
    
    # Configure PAM for Google Authenticator
    # Remove any existing google_authenticator line first
    sudo sed -i '/pam_google_authenticator.so/d' /etc/pam.d/sshd
    # Add our configuration at the beginning of the auth section
    echo "auth required pam_google_authenticator.so nullok" | sudo tee -a /etc/pam.d/sshd
    
    # Configure SSH for TOTP
    local ssh_config="/etc/ssh/sshd_config"
    
    # Remove any existing TOTP-related SSH settings
    sudo sed -i -E \
        -e '/^(#\s*)?(ChallengeResponseAuthentication|UsePAM|AuthenticationMethods|KbdInteractiveAuthentication)\s+/d' \
        "$ssh_config"
    
    # Add TOTP-specific SSH settings
    {
        echo "# TOTP Authentication Settings"
        echo "ChallengeResponseAuthentication yes"
        echo "UsePAM yes"
        echo "# Use PAM for authentication (will require both public key and TOTP)"
        echo "AuthenticationMethods publickey,keyboard-interactive"
    } | sudo tee -a "$ssh_config" > /dev/null
    
    # Restart SSH to apply changes
    sudo systemctl restart ssh
    
    # Create TOTP config directory
    mkdir -p ~/.google_authenticator
    chmod 700 ~/.google_authenticator
    
    # Generate or use existing TOTP secret
    if [ -f ~/.google_authenticator/totp_secret ]; then
        echo "Using existing TOTP configuration"
        cp ~/.google_authenticator/totp_secret ~/.google_authenticator/$(hostname)
    else
        echo "Generating new TOTP configuration"
        google-authenticator -t -d -f -r 3 -R 30 -w 3 -Q UTF8 -l "$(hostname)" -s ~/.google_authenticator/$(hostname)
        cp ~/.google_authenticator/$(hostname) ~/.google_authenticator/totp_secret
    fi
    
    # Set permissions
    chmod 600 ~/.google_authenticator/*
    
    # Restart SSH
    sudo systemctl restart sshd
    
    # Show QR code if running in terminal
    if [ -t 1 ]; then
        echo "Scan this QR code with Google Authenticator:"
        secret=$(head -n1 ~/.google_authenticator/$(hostname) | cut -d' ' -f1)
        qrencode -t UTF8 "otpauth://totp/$(hostname)?secret=$secret&issuer=$(hostname)"
    fi
    
    echo -e "\n$(s Y "IMPORTANT: Backup these recovery codes in a secure location:")"
    echo "----------------------------------------"
    tail -n +6 ~/.google_authenticator/$(hostname) | head -n 5
    echo "----------------------------------------"
    echo -e "\n$(s R "You will need these if you lose your TOTP device!")"
    
    # Save a copy of the secret in a secure location
    echo -e "\n$(s G "TOTP configuration complete. Test with:")"
    echo "ssh $USER@$(hostname -f)"
}

mount_webdav_help="Mount webdav source. WEBDAV_USER|PASSWORD and KDRIVE_* or WEBDAV_URL env variables required."
mount_webdav() {
    section "Mount WebDAV"

    # Install davfs2 if not installed
    if ! command -v mount.davfs &> /dev/null; then
        section "Installing davfs2..."
        echo "davfs2 davfs2/suid_install boolean false" | sudo debconf-set-selections
        sudo apt update
        sudo DEBIAN_FRONTEND=noninteractive apt install -y davfs2
    fi

    if [ -z "$WEBDAV_URL" ]; then
      # Ask for KDrive ID (or use env KDRIVE_ID)
      if [ -z "$KDRIVE_ID" ]; then
          read -p "Enter your kDrive ID: " KDRIVE_ID
      fi
      # Encode spaces in folder path
      ENCODED_PATH=$(echo "$KDRIVE_PATH" | sed 's/ /%20/g')
      WEBDAV_URL="https://${KDRIVE_ID}.connect.kdrive.infomaniak.com/$ENCODED_PATH"
    fi

    if [ -z "$WEBDAV_USER" ]; then
        read -p "Enter your webdav username (email): " WEBDAV_USER
    fi
    if [ -z "$WEBDAV_PASSWORD" ]; then
      read -s -p "Enter your webdav password: " WEBDAV_PASSWORD
      echo
    fi
    # Check if WEBDAV_MOUNT_PATH is already mounted
    if mountpoint -q "$WEBDAV_MOUNT_PATH"; then
        echo "$WEBDAV_MOUNT_PATH is already mounted. Unmounting..."
        sudo umount "$WEBDAV_MOUNT_PATH"
    fi

    echo "WebDAV URL: $(s B $WEBDAV_URL)"
    echo "Local mount point: $(s B $WEBDAV_MOUNT_PATH)"

    sudo mkdir -p "$WEBDAV_MOUNT_PATH"
    sudo chown "$(id -u)":"$(id -g)" "$WEBDAV_MOUNT_PATH"

    # Backup fstab
    sudo cp /etc/fstab /etc/fstab.bak

    # Remove existing entries for this URL or mount point
    sudo sed -i "\|$WEBDAV_URL|d" /etc/fstab
    sudo sed -i "\|$WEBDAV_MOUNT_PATH|d" /etc/fstab

    # Add fstab entry
    FSTAB_LINE="$WEBDAV_URL $WEBDAV_MOUNT_PATH davfs file_mode=665,dir_mode=775,uid=$(id -u),gid=$(id -g),rw,_netdev 0 0"
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab

    # Configure credentials
    SECRETS_FILE="/etc/davfs2/secrets"
    # Remove existing entry
    sudo sed -i "\|$WEBDAV_URL|d" "$SECRETS_FILE" || true
    # Add new entry
    echo "$WEBDAV_URL $WEBDAV_USER $WEBDAV_PASSWORD" | sudo tee -a "$SECRETS_FILE" > /dev/null

    # Set permissions
    sudo chmod 600 "$SECRETS_FILE"
    sudo chown root:root "$SECRETS_FILE"

    sudo systemctl daemon-reload

    sudo mount $WEBDAV_MOUNT_PATH
    echo $(s G "Setup complete!")
    echo "Mounted on $(s B $WEBDAV_MOUNT_PATH)"
}

install_lynis_help="Installs rkhunter to detect common rootkits and backdoors."
install_lynis() {
  section "Installing Lynis (security auditing tool)"
  sudo apt install -y lynis
  echo "Run $(s B $0 security_audit) to check your system."
}

run_system_check_help="Runs Lynis (security auditing tool) to check your system."
run_system_check() {
  section "Running Lynis (security auditing tool)"
  sudo lynis audit system
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


security_audit_help="Runs comprehensive security audit using Lynis and other tools."
security_audit() {
  section "Running security audit"
  
  # Create log directory
  local log_dir="/var/log/security-audit"
  sudo mkdir -p "$log_dir"
  
  # Install Lynis if not present
  if ! command -v lynis >/dev/null 2>&1; then
    install_lynis
  fi
  
  # Run Lynis audit
  local lynis_report="$log_dir/lynis-report-$(date +%Y%m%d-%H%M%S).txt"
  section "Running Lynis security audit"
  sudo lynis audit system > "$lynis_report" 2>&1
  
  # Check firewall status
  section "Checking firewall status"
  local firewall_report="$log_dir/firewall-report-$(date +%Y%m%d-%H%M%S).txt"
  sudo ufw status verbose > "$firewall_report" 2>&1
  
  # Check for open ports
  section "Checking open ports"
  local ports_report="$log_dir/ports-report-$(date +%Y%m%d-%H%M%S).txt"
  sudo netstat -tuln | grep LISTEN > "$ports_report" 2>&1
  
  # Check running services
  section "Checking running services"
  local systemd_report="$log_dir/systemd-report-$(date +%Y%m%d-%H%M%S).txt"
  sudo systemctl list-units --type=service --state=running > "$systemd_report" 2>&1
  
  echo "$(s G Security audit complete!)"
  echo "Reports saved to: $(s B $log_dir)"
  echo "  - Lynis: $(s B $(basename "$lynis_report"))"
  echo "  - Firewall: $(s B $(basename "$firewall_report"))"
  echo "  - Ports: $(s B $(basename "$ports_report"))"
  echo "  - Systemd: $(s B $(basename "$systemd_report"))"
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
  setup_locale
  update_system
  configure_ssh
  setup_firewall
  setup_fail2ban
  setup_auditd
  enable_apparmor
  enable_time_sync
  install_utils
  install_lynis
  install_k3s
  #install_rootkit_hunter
  #format_and_mount_disk
  #backup_config
  echo $(s R "Reboot your system")
  echo $(s d "https://www.servercontrolpanel.de")
}

help_menu() {
  echo "$(s d Usage:) sudo [$(s i ENV_OVERRIDES)] $(s b $0) [command...]
  
It is recomanded to run $(s b run_all) first to setup the system and then mount webdav.
After this a $(s b security_audit) is recommended to check the system.

$(s Y Execute this Commands:)
  sudo $0 run_all
  KDRIVE_ID=1234xxx WEBDAV_USER=xxx@burgdev.ch WEBDAV_PASSWORD=xxx sudo $0 mount_webdav
  sudo $0 security_audit
  
It is also possible to run multiple commands:
  sudo $0 update_system setup_firewall

$(s Y Environment variables:)
  $(s b USER_NAME)               User for SSH and kubeconfig ownership (default: $(s B ${USER_NAME}))

$(s d "(optional)") Used for $(s i "${Y}format_and_mount_disk"):
  $(s b DISK_DEVICE)             Target disk for mounting (default: $(s B ${DISK_DEVICE}))
  $(s b MOUNT_POINT)             Mount location (default: $(s B ${MOUNT_POINT}))
  
$(s d "(optional)") Used for $(s i "${Y}mount_webdav"):
  $(s b KDRIVE_ID)               $(s R required) - kDrive id (used of $(s b WEBDAV_URL) is not set)
  $(s b WEBDAV_USER)             $(s R required) - WebDAV user (usally email)
  $(s b WEBDAV_PASSWORD)         $(s R required) - WebDAV password
  $(s b WEBDAV_MOUNT_PATH)       Local mount path (default: $(s B ${WEBDAV_MOUNT_PATH}))
  $(s b KDRIVE_PATH)             kDrive path (used of $(s b WEBDAV_URL) is not set) (default: $(s B ${KDRIVE_PATH}))
  $(s b WEBDAV_URL)              Full webdav URL if $(s b KDRIVE_ID) and $(s b KDRIVE_PATH) is not set

$(s Y Commands:)
  $(s b run_all)                 $(s d $run_all_help)  
  $(s b setup_locale)            $(s d $setup_locale_help)  
  $(s b update_system)           $(s d $update_system_help)  
  $(s b configure_ssh)           $(s d $configure_ssh_help)  
  $(s b setup_firewall)          $(s d $setup_firewall_help)
  $(s b setup_fail2ban)          $(s d $setup_fail2ban_help)
  $(s b setup_auditd)            $(s d $setup_auditd_help)
  $(s b enable_apparmor)         $(s d $enable_apparmor_help)
  $(s b enable_time_sync)        $(s d $enable_time_sync_help)
  $(s b install_utils)           $(s d $install_utils_help)
  $(s b install_lynis)           $(s d $install_lynis_help)
  $(s b install_k3s)             $(s d $install_k3s_help)

$(s Y Optional Commands:)
  $(s b security_audit)          $(s d $security_audit_help)
  $(s b mount_webdav)            $(s d $mount_webdav_help)
  $(s b configure_totp)          $(s d $configure_totp_help)
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
       "$cmd"
    else
      echo "Unknown command: $cmd"
      help_menu
      exit 1
    fi
  done
}


handle_exit() {
    local exit_code=$?
    local line_number=$1
    local command_name=$2
    if [[ "$exit_code" != "0" ]]; then
        echo "$(s R "Error in $command_name at line $line_number with status $exit_code")" >&2
        echo "$(s Y "Warning: Script exited with error. Some operations may not have completed successfully.")" >&2
        exit $exit_code
    fi
}

# Set up trap to check exit code
trap 'handle_exit $LINENO "$BASH_COMMAND"' EXIT

main "$@"
