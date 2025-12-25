#!/usr/bin/env bash
# Description: Setup automatic CA certificate synchronization
# This installs a systemd timer that automatically updates your system's
# CA certificates when Kubernetes certificates change

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_FILE="k8s-local-ca-sync.service"
TIMER_FILE="k8s-local-ca-sync.timer"

echo "Setting up automatic CA certificate synchronization..."

# Make install_local_ca.sh executable
chmod +x "$SCRIPT_DIR/install_local_ca.sh"

# Copy systemd files
echo "Installing systemd service and timer..."
sudo cp "$SCRIPT_DIR/$SERVICE_FILE" /etc/systemd/system/
sudo cp "$SCRIPT_DIR/$TIMER_FILE" /etc/systemd/system/

# Reload systemd
echo "Reloading systemd..."
sudo systemctl daemon-reload

# Enable and start timer
echo "Enabling and starting timer..."
sudo systemctl enable "$TIMER_FILE"
sudo systemctl start "$TIMER_FILE"

# Initial run
echo ""
echo "Running initial certificate sync..."
sudo "$SCRIPT_DIR/install_local_ca.sh"

echo ""
echo "✓ Setup complete!"
echo ""
echo "Automatic CA sync is now enabled and will run:"
echo "  - On system boot (after 2 minutes)"
echo "  - Every hour"
echo ""
echo "Useful commands:"
echo "  Status:       sudo systemctl status k8s-local-ca-sync.timer"
echo "  Logs:         sudo journalctl -u k8s-local-ca-sync.service -f"
echo "  Manual sync:  sudo $SCRIPT_DIR/install_local_ca.sh"
echo "  Disable:      sudo systemctl disable k8s-local-ca-sync.timer"
echo "  Uninstall:    sudo systemctl disable --now k8s-local-ca-sync.timer && sudo rm /etc/systemd/system/k8s-local-ca-sync.*"
