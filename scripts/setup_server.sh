#!/usr/bin/env bash
# Description: Securely configure system for k3s, Traefik, and general hardening.
# Safe to re-run (idempotent design).
#
# IMPORTANT: This script need to run on the serve!

set -euo pipefail

### GLOBALS (can be overridden by environment variables) ###
USER_NAME="${USER_NAME:-$USER}"
TIMEZONE="${TIMEZONE:-Europe/Zurich}"

# LVM Storage Configuration
LVM_DISK_DEVICE="${LVM_DISK_DEVICE:-/dev/vda}"
K3S_STORAGE_SIZE="${K3S_STORAGE_SIZE:-50G}"
K3S_VG_NAME="${K3S_VG_NAME:-k3s-vg}"
K3S_LV_NAME="${K3S_LV_NAME:-k3s-lv}"
K3S_MOUNT_PATH="${K3S_MOUNT_PATH:-/var/lib/rancher}"

OPENEBS_PARTITION_SIZE="${OPENEBS_PARTITION_SIZE:-500G}"
OPENEBS_VG_NAME="${OPENEBS_VG_NAME:-openebs-vg}"
OPENEBS_THINPOOL_NAME="${OPENEBS_THINPOOL_NAME:-openebs-vg_thinpool}"
OPENEBS_METADATA_PERCENT="${OPENEBS_METADATA_PERCENT:-10}"

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
	b=""
	rst=""
	d=""
	u=""
	nu=""
	R=""
	G=""
	Y=""
	B=""
	C=""
	M=""
	W=""
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

	# Check if TOTP Authentication is already set
	if ! grep -q '^\s*# TOTP Authentication\s' "$ssh_config"; then
		# Remove existing AuthenticationMethods if it's commented out
		sudo sed -i -E \
			-e '/^(#\s*)?(PasswordAuthentication|AuthenticationMethods)\s+/d' \
			"$ssh_config"
		# Add default AuthenticationMethods
		echo "AuthenticationMethods publickey,password" | sudo tee -a "$ssh_config" >/dev/null
	fi

	# Remove other settings we want to manage
	sudo sed -i -E \
		-e '/^(#\s*)?(PermitRootLogin|PermitEmptyPasswords|X11Forwarding|AllowUsers)\s+/d' \
		"$ssh_config"

	# Add the basic security settings at the end of the file
	{
		echo "PermitRootLogin no"
		echo "PermitEmptyPasswords no"
		echo "X11Forwarding no"
		echo "AllowUsers $USER_NAME"
	} | sudo tee -a "$ssh_config" >/dev/null

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

install_longhorn_deps_help="Installs Longhorn dependencies."
install_longhorn_deps() {
	section "Installing Longhorn dependencies"
	if ! command -v iscsid >/dev/null 2>&1; then
		sudo apt install -y open-iscsi
	else
		echo "open-iscsi already installed, skipping."
	fi
	if lsmod | grep dm_crypt; then
		echo "dm_crypt already loaded, skipping."
	else
		echo "Loading kernel module:"
		sudo modprobe dm_crypt
		echo "dm_crypt" | sudo tee /etc/modules-load.d/dm_crypt.conf
	fi
}

setup_longhorn_storage_help="Sets up Longhorn storage."
setup_longhorn_storage() {
	section "Setting up Longhorn storage"
	local longhorn_dir="/mnt/kubernetes/longhorn"
	local longhorn_uid=1000
	local longhorn_gid=1000

	# Create directory if it doesn't exist
	if [ ! -d "$longhorn_dir" ]; then
		echo "Creating Longhorn directory at $longhorn_dir"
		sudo mkdir -p "$longhorn_dir"
	fi

	# Create longhorn user/group if they don't exist
	if ! getent group $longhorn_gid >/dev/null; then
		sudo groupadd -g $longhorn_gid longhorn || true
	fi

	if ! id -u longhorn >/dev/null 2>&1; then
		sudo useradd -u $longhorn_uid -g $longhorn_gid -r -s /sbin/nologin longhorn || true
	fi

	# Set ownership and permissions
	echo "Setting permissions for $longhorn_dir"
	sudo chown -R $longhorn_uid:$longhorn_gid "$longhorn_dir"
	sudo chmod -R 775 "$longhorn_dir" # Allow group write access

	# Set GID bit so new files inherit the group
	sudo chmod g+s "$longhorn_dir"

	# For SELinux systems
	if command -v sestatus >/dev/null 2>&1 && [ "$(sestatus | grep -c 'enabled')" -gt 0 ]; then
		if command -v chcon >/dev/null 2>&1; then
			sudo chcon -R -t container_file_t "$longhorn_dir" || true
		fi
	fi
}

setup_lvm_help="Configures LVM."
setup_lvm() {
	section "Installing LVM"
	if ! command -v lvm >/dev/null 2>&1; then
		sudo apt install lvm2 -y
	fi

	modules=(dm_mod dm_thin_pool dm_snapshot dm_mirror dm_crypt)
	for mod in "${modules[@]}"; do
		if lsmod | grep -q "^${mod}"; then
			echo "$B${mod}$rst already loaded, skipping."
		else
			echo "Loading ${mod}..."
			sudo modprobe "${mod}"
			echo "${mod}" | sudo tee -a /etc/modules-load.d/openebs-lvm.conf >/dev/null
		fi
	done
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
		#echo "UsePAM yes"
		echo "PasswordAuthentication no"
		echo "# Use PAM for authentication (will require both public key and TOTP)"
		echo "AuthenticationMethods publickey,keyboard-interactive"
	} | sudo tee -a "$ssh_config" >/dev/null

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

setup_kopia_help="Setup kopia"
setup_kopia() {
	section "Setup Kopia"
	policy_json='{"(global)":{"retention":{"keepLatest":10,"keepHourly":48,"keepDaily":7,"keepWeekly":4,"keepMonthly":24,"keepAnnual":3,"ignoreIdenticalSnapshots":true},"files":{"ignoreDotFiles":[".kopiaignore"]},"errorHandling":{"ignoreFileErrors":false,"ignoreDirectoryErrors":false,"ignoreUnknownTypes":true},"scheduling":{"intervalSeconds":3600,"runMissed":true},"compression":{"compressorName":"zstd","neverCompress":[".7z",".7Z",".alz",".ALZ",".bz",".BZ",".bz2",".BZ2",".cab",".CAB",".cbr",".CBR",".cbz",".CBZ",".deb",".DEB",".dl_",".DL_",".dsft",".DSFT",".ex_",".EX_",".gz",".GZ",".jar",".JAR",".lmza",".LMZA",".lzo",".LZO",".mpkg",".MPKG",".msi",".MSI",".msp",".MSP",".msu",".MSU",".pet",".PET",".rar",".RAR",".sft",".SFT",".sit",".SIT",".sitx",".SITX",".sy_",".SY_",".tgz",".TGZ",".tbz2",".TBZ2",".txz",".TXZ",".war",".WAR",".wim",".WIM",".xar",".XAR",".xz",".XZ",".zip",".ZIP",".zipx",".ZIPX",".zst",".ZST",".3gp",".3GP",".3g2",".3G2",".aa3",".AA3",".aac",".AAC",".aif",".AIF",".ape",".APE",".flac",".FLAC",".gsm",".GSM",".iff",".IFF",".m4a",".M4A",".mp3",".MP3",".mpa",".MPA",".mpc",".MPC",".ra",".RA",".ofr",".OFR",".ofs",".OFS",".ogg",".OGG",".opus",".OPUS",".wma",".WMA",".wv",".WV",".asf",".ASF",".asx",".ASX",".avi",".AVI",".bsf",".BSF",".divx",".DIVX",".f4v",".F4V",".flv",".FLV",".hdmov",".HDMOV",".m2p",".M2P",".m4v",".M4V",".mkv",".MKV",".mov",".MOV",".mp4",".MP4",".mpg",".MPG",".mpeg",".MPEG",".mts",".MTS",".ogm",".OGM",".ogv",".OGV",".rm",".RM",".swf",".SWF",".trp",".TRP",".ts",".TS",".vob",".VOB",".webm",".WEBM",".wmv",".WMV",".wtv",".WTV",".emz",".EMZ",".gif",".GIF",".j2c",".J2C",".jpeg",".JPEG",".jpg",".JPG",".nef",".NEF",".pamp",".PAMP",".pdn",".PDN",".png",".PNG",".pspimage",".PSPIMAGE",".tif",".TIF",".tiff",".TIFF",".dng",".DNG",".cr2",".CR2",".dmg",".DMG",".tib",".TIB",".aes",".AES",".axx",".AXX",".gpg",".GPG",".hc",".HC",".kdbx",".KDBX",".tc",".TC",".tpm",".TPM",".fve",".FVE",".apk",".APK",".eftx",".EFTX",".sdg",".SDG",".thmx",".THMX",".vsix",".VSIX",".vsv",".VSV",".wmz",".WMZ",".xpi",".XPI",".eot",".EOT",".woff",".WOFF",".bik",".BIK",".mpq",".MPQ",".docx",".DOCX",".docm",".DOCM",".dotm",".DOTM",".dotx",".DOTX",".epub",".EPUB",".graffle",".GRAFFLE",".hxs",".HXS",".max",".MAX",".mobi",".MOBI",".mshc",".MSHC",".odp",".ODP",".ods",".ODS",".odt",".ODT",".otp",".OTP",".ots",".OTS",".ott",".OTT",".pages",".PAGES",".pptx",".PPTX",".stw",".STW",".trf",".TRF",".webarchive",".WEBARCHIVE",".xlsx",".XLSX",".xlsm",".XLSM",".xlsb",".XLSB",".xps",".XPS",".d",".D",".dess",".DESS",".i",".I",".idx",".IDX",".nupkg",".NUPKG",".pack",".PACK",".swz",".SWZ",".lz",".LZ",".lz4",".LZ4",".z",".Z",".s7z",".S7Z",".ace",".ACE",".arj",".ARJ",".rpm",".RPM"]},"metadataCompression":{"compressorName":"zstd-fastest"},"splitter":{},"actions":{},"osSnapshots":{"volumeShadowCopy":{"enable":0}},"logging":{"directories":{"snapshotted":5,"ignored":5},"entries":{"snapshotted":0,"ignored":5,"cacheHit":0,"cacheMiss":0}},"upload":{"maxParallelSnapshots":1,"parallelUploadAboveSize":2147483648}}}'
	sudo kopia policy import --global --from-file=<(echo "$policy_json")

}

mount_webdav_help="Mount webdav source. WEBDAV_USER|PASSWORD and KDRIVE_* or WEBDAV_URL env variables required."
mount_webdav() {
	section "Mount WebDAV"

	# Install davfs2 if not installed
	if ! command -v mount.davfs &>/dev/null; then
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
	echo "$WEBDAV_URL $WEBDAV_USER $WEBDAV_PASSWORD" | sudo tee -a "$SECRETS_FILE" >/dev/null

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

update_bashrc_help="Updates .bashrc to disable color aliases and common ls aliases."
update_bashrc() {
	section "Updating .bashrc configuration"
	local bashrc_file="$HOME/.bashrc"

	# Uncomment all aliases by removing '#' before 'alias' while preserving indentation
	sed -i -E 's/^(\s*)#(\s*alias )/\1\2/' "$bashrc_file"

	echo "Updated .bashrc - all aliases have been uncommented."
	echo "To apply changes in the current session, run: source ~/.bashrc"
}

setup_k3s_storage_help="Creates LVM volume for k3s data and mounts it at ${K3S_MOUNT_PATH}. Checks for existing data before proceeding."
setup_k3s_storage() {
	section "Setting up k3s LVM storage"

	# Check if k3s data already exists
	if [ -d "$K3S_MOUNT_PATH" ] && [ -n "$(ls -A "$K3S_MOUNT_PATH" 2>/dev/null)" ]; then
		echo "$(s Y "WARNING: $K3S_MOUNT_PATH already contains data!")"
		echo "$(s Y "Please backup and move this data before running this function.")"
		echo "$(s Y "Skipping k3s storage setup to prevent data loss.")"
		return 1
	fi

	# Check if already mounted
	if mountpoint -q "$K3S_MOUNT_PATH"; then
		echo "$K3S_MOUNT_PATH is already mounted, skipping."
		return 0
	fi

	# Ensure parted is installed
	if ! command -v parted &>/dev/null; then
		sudo apt install -y parted
	fi

	# Check if VG already exists
	if sudo vgs "$K3S_VG_NAME" &>/dev/null; then
		echo "Volume group $K3S_VG_NAME already exists, checking LV..."
	else
		# Try to find an existing LVM partition that's not being used
		local part_device=""
		local part_num=""

		# Look for existing LVM partitions on this disk
		for pv_candidate in $(sudo parted -s "$LVM_DISK_DEVICE" print | grep -E '^ [0-9]+.*lvm' | awk '{print $1}'); do
			local candidate_device="${LVM_DISK_DEVICE}${pv_candidate}"
			# Check if this partition is not already part of a VG
			if ! sudo pvs "$candidate_device" &>/dev/null; then
				echo "Found existing unused LVM partition: $candidate_device"
				part_device="$candidate_device"
				part_num="$pv_candidate"
				break
			fi
		done

		# If no existing LVM partition found, create a new one
		if [ -z "$part_device" ]; then
			# Find the next available partition number
			part_num=$(sudo parted -s "$LVM_DISK_DEVICE" print | grep -E '^ [0-9]+' | awk '{print $1}' | sort -n | tail -1)
			part_num=$((part_num + 1))

			# Find the end of the last partition to start our new partition after it
			local start_pos=$(sudo parted -s "$LVM_DISK_DEVICE" unit GB print free | grep -E '^ [0-9]+' | tail -1 | awk '{print $3}')

			# If no partitions exist, start at 1MiB, otherwise use the end of last partition
			if [ -z "$start_pos" ]; then
				start_pos="1MiB"
			fi

			# Calculate end position
			local size_value="${K3S_STORAGE_SIZE%G}"
			local start_value="${start_pos%GB}"
			local end_pos="${size_value}GB"

			# If start_pos is in GB, calculate the actual end position
			if [[ "$start_pos" == *"GB" ]]; then
				end_pos=$(awk "BEGIN {print $start_value + $size_value}")
				end_pos="${end_pos}GB"
			fi

			part_device="${LVM_DISK_DEVICE}${part_num}"

			echo "Creating ${K3S_STORAGE_SIZE} partition (partition ${part_num}) for k3s on ${LVM_DISK_DEVICE}..."
			echo "Start: $start_pos, End: $end_pos"
			sudo parted -s "$LVM_DISK_DEVICE" mkpart primary "$start_pos" "$end_pos"
			sudo parted -s "$LVM_DISK_DEVICE" set "$part_num" lvm on
			sudo partprobe "$LVM_DISK_DEVICE"
			sleep 2
		fi

		# Create Physical Volume if not already initialized
		if ! sudo pvs "$part_device" &>/dev/null; then
			echo "Creating physical volume on $part_device..."
			sudo pvcreate "$part_device"
		fi

		# Create Volume Group
		echo "Creating volume group $K3S_VG_NAME using $part_device..."
		sudo vgcreate "$K3S_VG_NAME" "$part_device"
	fi

	# Create Logical Volume if it doesn't exist
	if ! sudo lvs "$K3S_VG_NAME/$K3S_LV_NAME" &>/dev/null; then
		echo "Creating logical volume $K3S_LV_NAME (using 100% of VG)..."
		sudo lvcreate -l 100%FREE -n "$K3S_LV_NAME" "$K3S_VG_NAME"

		# Format the LV
		echo "Formatting logical volume as ext4..."
		sudo mkfs.ext4 "/dev/$K3S_VG_NAME/$K3S_LV_NAME"
	else
		echo "Logical volume $K3S_LV_NAME already exists"
	fi

	# Create mount point
	sudo mkdir -p "$K3S_MOUNT_PATH"

	# Add to fstab if not already present
	local lv_path="/dev/$K3S_VG_NAME/$K3S_LV_NAME"
	if ! grep -q "$lv_path" /etc/fstab; then
		echo "$lv_path $K3S_MOUNT_PATH ext4 defaults 0 2" | sudo tee -a /etc/fstab
	fi

	# Mount
	sudo mount -a
	echo "$(s G "K3s storage mounted at $K3S_MOUNT_PATH")"
	df -h "$K3S_MOUNT_PATH"
}

setup_openebs_storage_help="Creates LVM thin pool for OpenEBS storage. Uses ${OPENEBS_PARTITION_SIZE} with thin provisioning enabled."
setup_openebs_storage() {
	section "Setting up OpenEBS LVM thin pool storage"

	# Check if VG already exists
	if sudo vgs "$OPENEBS_VG_NAME" &>/dev/null; then
		echo "Volume group $OPENEBS_VG_NAME already exists"

		# Check if thin pool exists
		if sudo lvs "$OPENEBS_VG_NAME/$OPENEBS_THINPOOL_NAME" &>/dev/null; then
			echo "Thin pool $OPENEBS_THINPOOL_NAME already exists, skipping."
			sudo lvs "$OPENEBS_VG_NAME/$OPENEBS_THINPOOL_NAME"
			return 0
		fi
	else
		# Try to find an existing LVM partition that's not being used
		local part_device=""
		local part_num=""

		# Look for existing LVM partitions on this disk
		for pv_candidate in $(sudo parted -s "$LVM_DISK_DEVICE" print | grep -E '^ [0-9]+.*lvm' | awk '{print $1}'); do
			local candidate_device="${LVM_DISK_DEVICE}${pv_candidate}"
			# Check if this partition is not already part of a VG
			if ! sudo pvs "$candidate_device" &>/dev/null; then
				echo "Found existing unused LVM partition: $candidate_device"
				part_device="$candidate_device"
				part_num="$pv_candidate"
				break
			fi
		done

		# If no existing LVM partition found, create a new one
		if [ -z "$part_device" ]; then
			# Find the next available partition number
			part_num=$(sudo parted -s "$LVM_DISK_DEVICE" print | grep -E '^ [0-9]+' | awk '{print $1}' | sort -n | tail -1)
			part_num=$((part_num + 1))

			# Find the end of the last partition to start our new partition after it
			local start_pos=$(sudo parted -s "$LVM_DISK_DEVICE" unit GB print free | grep -E '^ [0-9]+' | tail -1 | awk '{print $3}')

			# If no start position found, something is wrong
			if [ -z "$start_pos" ]; then
				echo "$(s R "Error: Could not determine where to start OpenEBS partition")"
				echo "$(s Y "Please ensure k3s storage is set up first")"
				return 1
			fi

			# Calculate end position
			local size_value="${OPENEBS_PARTITION_SIZE%G}"
			local start_value="${start_pos%GB}"
			local end_pos=$(awk "BEGIN {print $start_value + $size_value}")
			end_pos="${end_pos}GB"

			part_device="${LVM_DISK_DEVICE}${part_num}"

			echo "Creating ${OPENEBS_PARTITION_SIZE} partition (partition ${part_num}) for OpenEBS on ${LVM_DISK_DEVICE}..."
			echo "Start: $start_pos, End: $end_pos"
			sudo parted -s "$LVM_DISK_DEVICE" mkpart primary "${start_pos}" "${end_pos}"
			sudo parted -s "$LVM_DISK_DEVICE" set "$part_num" lvm on
			sudo partprobe "$LVM_DISK_DEVICE"
			sleep 2
		fi

		# Create Physical Volume if not already initialized
		if ! sudo pvs "$part_device" &>/dev/null; then
			echo "Creating physical volume on $part_device..."
			sudo pvcreate "$part_device"
		fi

		# Create Volume Group
		echo "Creating volume group $OPENEBS_VG_NAME using $part_device..."
		sudo vgcreate "$OPENEBS_VG_NAME" "$part_device"
	fi

	# Create thin pool if it doesn't exist
	if ! sudo lvs "$OPENEBS_VG_NAME/$OPENEBS_THINPOOL_NAME" &>/dev/null; then
		# Calculate sizes (reserve metadata percent)
		local data_percent=$((100 - OPENEBS_METADATA_PERCENT))

		echo "Creating thin pool $OPENEBS_THINPOOL_NAME (data: ${data_percent}%, metadata: ${OPENEBS_METADATA_PERCENT}%)..."

		# Create thin pool using all available space
		sudo lvcreate -l "${data_percent}%FREE" --thinpool "$OPENEBS_THINPOOL_NAME" "$OPENEBS_VG_NAME"

		# Configure thin pool for better performance
		sudo lvchange --zero n "$OPENEBS_VG_NAME/$OPENEBS_THINPOOL_NAME"

		echo "$(s G "OpenEBS thin pool created successfully")"
	else
		echo "Thin pool already exists"
	fi

	# Configure automatic extension for thin pool and metadata
	section "Configuring thin pool auto-extension"
	local lvm_conf="/etc/lvm/lvm.conf"

	# Backup LVM config
	if [ ! -f "${lvm_conf}.backup" ]; then
		sudo cp "$lvm_conf" "${lvm_conf}.backup"
	fi

	# Enable thin pool autoextend if not already configured
	if ! grep -q "thin_pool_autoextend_threshold" "$lvm_conf" || grep -q "^[[:space:]]*#.*thin_pool_autoextend_threshold" "$lvm_conf"; then
		echo "Configuring thin pool auto-extension..."
		sudo sed -i '/^[[:space:]]*activation[[:space:]]*{/a\
\	# Auto-extend thin pools when they reach 80% capacity\
\	thin_pool_autoextend_threshold = 80\
\	# Extend by 20% when threshold is reached\
\	thin_pool_autoextend_percent = 20\
\	# Auto-extend metadata volumes\
\	thin_pool_metadata_require_separate_pvs = 0
' "$lvm_conf"
	else
		echo "Thin pool auto-extension already configured"
	fi

	# Display status
	echo ""
	echo "OpenEBS LVM Storage Status:"
	sudo vgs "$OPENEBS_VG_NAME"
	sudo lvs "$OPENEBS_VG_NAME"
	echo ""
	echo "$(s G "OpenEBS storage is ready for use by OpenEBS LVM provisioner")"
	echo "StorageClass should reference VG: $(s B "$OPENEBS_VG_NAME")"
}

check_lvm_thinpool_help="Checks LVM thin pool usage and health for snapshots."
check_lvm_thinpool() {
	section "Checking LVM thin pool status"

	if ! sudo vgs "$OPENEBS_VG_NAME" &>/dev/null; then
		echo "$(s Y "Volume group $OPENEBS_VG_NAME not found. Run setup_openebs_storage first.")"
		return 1
	fi

	if ! sudo lvs "$OPENEBS_VG_NAME/$OPENEBS_THINPOOL_NAME" &>/dev/null; then
		echo "$(s Y "Thin pool $OPENEBS_THINPOOL_NAME not found. Run setup_openebs_storage first.")"
		return 1
	fi

	echo ""
	echo "$(s b "Volume Group Status:")"
	sudo vgs "$OPENEBS_VG_NAME" -o vg_name,vg_size,vg_free

	echo ""
	echo "$(s b "Thin Pool Status:")"
	sudo lvs "$OPENEBS_VG_NAME/$OPENEBS_THINPOOL_NAME" -o lv_name,lv_size,data_percent,metadata_percent,lv_attr

	echo ""
	echo "$(s b "All Logical Volumes:")"
	sudo lvs "$OPENEBS_VG_NAME" -o lv_name,lv_size,data_percent,pool_lv,lv_attr

	# Check for warnings
	local data_usage=$(sudo lvs --noheadings "$OPENEBS_VG_NAME/$OPENEBS_THINPOOL_NAME" -o data_percent 2>/dev/null | tr -d ' ' | tr -d '%')
	local metadata_usage=$(sudo lvs --noheadings "$OPENEBS_VG_NAME/$OPENEBS_THINPOOL_NAME" -o metadata_percent 2>/dev/null | tr -d ' ' | tr -d '%')

	echo ""
	if [ -n "$data_usage" ] && [ "$data_usage" != "" ]; then
		# Use awk instead of bc for better compatibility
		if awk -v usage="$data_usage" 'BEGIN { exit !(usage > 80) }'; then
			echo "$(s R "WARNING: Thin pool data usage is at ${data_usage}%!")"
			echo "$(s Y "Consider extending the volume group or cleaning up old snapshots.")"
		else
			echo "$(s G "Thin pool data usage: ${data_usage}% - OK")"
		fi
	fi

	if [ -n "$metadata_usage" ] && [ "$metadata_usage" != "" ]; then
		if awk -v usage="$metadata_usage" 'BEGIN { exit !(usage > 80) }'; then
			echo "$(s R "WARNING: Thin pool metadata usage is at ${metadata_usage}%!")"
			echo "$(s Y "Metadata pool may need extension.")"
		else
			echo "$(s G "Thin pool metadata usage: ${metadata_usage}% - OK")"
		fi
	fi
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
	sudo lynis audit system >"$lynis_report" 2>&1

	# Check firewall status
	section "Checking firewall status"
	local firewall_report="$log_dir/firewall-report-$(date +%Y%m%d-%H%M%S).txt"
	sudo ufw status verbose >"$firewall_report" 2>&1

	# Check for open ports
	section "Checking open ports"
	local ports_report="$log_dir/ports-report-$(date +%Y%m%d-%H%M%S).txt"
	sudo netstat -tuln | grep LISTEN >"$ports_report" 2>&1

	# Check running services
	section "Checking running services"
	local systemd_report="$log_dir/systemd-report-$(date +%Y%m%d-%H%M%S).txt"
	sudo systemctl list-units --type=service --state=running >"$systemd_report" 2>&1

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

run_all_help="Runs all setup commands including storage setup and k3s installation."
run_all() {
	update_bashrc
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
	setup_lvm
	install_longhorn_deps

	# Setup storage before installing k3s
	setup_k3s_storage
	setup_openebs_storage

	# Install k3s after storage is ready
	install_k3s

	echo ""
	echo "$(s G "==> Server setup complete!")"
	echo ""
	echo "$(s Y "Optional next steps:")"
	echo "  1. Run: $(s B "sudo $0 mount_webdav") - Mount WebDAV storage"
	echo "  2. Run: $(s B "sudo $0 security_audit") - Run security audit"
	echo ""
	echo "$(s R "After completing optional steps, reboot your system:") $(s B "sudo reboot")"
}

help_menu() {
	echo "$(s d Usage:) sudo [$(s i ENV_OVERRIDES)] $(s b $0) [command...]

$(s Y Recommended workflow for new server setup:)
  1. $(s b "sudo $0 run_all")                        - Complete system setup (includes storage and k3s)
  2. $(s b "sudo $0 mount_webdav")                   - Mount WebDAV (optional)
  3. $(s b "sudo $0 security_audit")                 - Security audit (recommended)
  4. $(s b "sudo reboot")                            - Reboot system

$(s Y Example Commands:)
  # Full server setup
  sudo $0 run_all

  # Individual storage setup (if not using run_all)
  sudo $0 setup_k3s_storage setup_openebs_storage install_k3s

  # Mount WebDAV with environment variables
  KDRIVE_ID=1234xxx WEBDAV_USER=xxx@burgdev.ch WEBDAV_PASSWORD=xxx sudo $0 mount_webdav

$(s Y Running multiple commands:)
  sudo $0 update_system setup_firewall install_utils

$(s Y Environment variables:)
  $(s b USER_NAME)               User for SSH and kubeconfig ownership (default: $(s B ${USER_NAME}))
  $(s b TIMEZONE)                Timezone to use (default: $(s B ${TIMEZONE}))

$(s d "(optional)") Used for LVM storage setup ($(s i "${Y}setup_k3s_storage") and $(s i "${Y}setup_openebs_storage")):
  $(s b LVM_DISK_DEVICE)         Disk device for LVM partitions (default: $(s B ${LVM_DISK_DEVICE}))
  $(s b K3S_STORAGE_SIZE)        Size for k3s partition (default: $(s B ${K3S_STORAGE_SIZE}))
  $(s b K3S_VG_NAME)             Volume group name for k3s (default: $(s B ${K3S_VG_NAME}))
  $(s b K3S_LV_NAME)             Logical volume name for k3s (default: $(s B ${K3S_LV_NAME}))
  $(s b K3S_MOUNT_PATH)          Mount path for k3s data (default: $(s B ${K3S_MOUNT_PATH}))
  $(s b OPENEBS_PARTITION_SIZE)  Size for OpenEBS partition (default: $(s B ${OPENEBS_PARTITION_SIZE}))
  $(s b OPENEBS_VG_NAME)         Volume group name for OpenEBS (default: $(s B ${OPENEBS_VG_NAME}))
  $(s b OPENEBS_THINPOOL_NAME)   Thin pool name for OpenEBS (default: $(s B ${OPENEBS_THINPOOL_NAME}))
  $(s b OPENEBS_METADATA_PERCENT) Metadata reserve percentage (default: $(s B ${OPENEBS_METADATA_PERCENT}))

$(s d "(optional)") Used for $(s i "${Y}mount_webdav"):
  $(s b KDRIVE_ID)               $(s R required) - kDrive id (used of $(s b WEBDAV_URL) is not set)
  $(s b WEBDAV_USER)             $(s R required) - WebDAV user (usally email)
  $(s b WEBDAV_PASSWORD)         $(s R required) - WebDAV password
  $(s b WEBDAV_MOUNT_PATH)       Local mount path (default: $(s B ${WEBDAV_MOUNT_PATH}))
  $(s b KDRIVE_PATH)             kDrive path (used of $(s b WEBDAV_URL) is not set) (default: $(s B ${KDRIVE_PATH}))
  $(s b WEBDAV_URL)              Full webdav URL if $(s b KDRIVE_ID) and $(s b KDRIVE_PATH) is not set

$(s Y Commands:)
  $(s b run_all)                 $(s d $run_all_help)
  $(s b update_bashrc)           $(s d $update_bashrc_help)
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
  $(s b setup_lvm)               $(s d $setup_lvm_help)
  $(s b setup_k3s_storage)       $(s d $setup_k3s_storage_help)
  $(s b setup_openebs_storage)   $(s d $setup_openebs_storage_help)
  $(s b install_longhorn_deps)   $(s d $install_longhorn_deps_help)
  $(s b install_k3s)             $(s d $install_k3s_help)

$(s Y Optional Commands:)
  $(s b security_audit)          $(s d $security_audit_help)
  $(s b check_lvm_thinpool)      $(s d $check_lvm_thinpool_help)
  $(s b mount_webdav)            $(s d $mount_webdav_help)
  $(s b configure_totp)          $(s d $configure_totp_help)
  $(s b setup_longhorn_storage)  $(s d $setup_longhorn_storage_help)
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
