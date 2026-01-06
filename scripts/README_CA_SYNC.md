# Local CA Certificate Auto-Sync

Automatically synchronize self-signed certificates from your local Kubernetes cluster to your system's trust store.

## Quick Setup

```bash
sudo ./setup_auto_ca_sync.sh
```

That's it! Certificates will now:
- ✓ Install automatically from **all namespaces**
- ✓ Update every hour
- ✓ Clean up expired/removed certificates
- ✓ Sync on system boot

## What Gets Installed

```
/usr/local/share/ca-certificates/k8s-local/
├── production_podinfo-tls.crt
├── production_umami-tls.crt
├── production_wd-backend-tls.crt
├── staging_immich-server-tls.crt
└── burginfra-system_openbao-ui-tls.crt
```

## Usage

### Check Status
```bash
sudo systemctl status k8s-local-ca-sync.timer
```

### View Logs
```bash
sudo journalctl -u k8s-local-ca-sync.service -f
```

### Force Sync Now
```bash
sudo systemctl start k8s-local-ca-sync.service
# or
sudo ./install_local_ca.sh
```

### Manual Operations
```bash
# Install from all namespaces
sudo ./install_local_ca.sh

# Install from specific namespace only
sudo ./install_local_ca.sh production

# Watch mode (continuous monitoring)
sudo ./install_local_ca.sh --watch
```

## Disable/Uninstall

### Temporarily Disable
```bash
sudo systemctl stop k8s-local-ca-sync.timer
```

### Permanently Disable
```bash
sudo systemctl disable --now k8s-local-ca-sync.timer
```

### Complete Uninstall
```bash
sudo systemctl disable --now k8s-local-ca-sync.timer
sudo rm /etc/systemd/system/k8s-local-ca-sync.*
sudo systemctl daemon-reload
sudo rm -rf /usr/local/share/ca-certificates/k8s-local
sudo update-ca-certificates --fresh
```

## Files

- `install_local_ca.sh` - Main sync script
- `setup_auto_ca_sync.sh` - One-time setup script
- `k8s-local-ca-sync.service` - Systemd service definition
- `k8s-local-ca-sync.timer` - Systemd timer (runs hourly)

## Troubleshooting

### Still seeing browser warnings?

1. **Check if timer is running:**
   ```bash
   sudo systemctl list-timers k8s-local-ca-sync.timer
   ```

2. **Check logs for errors:**
   ```bash
   sudo journalctl -u k8s-local-ca-sync.service -n 50
   ```

3. **Verify certificates are installed:**
   ```bash
   ls -la /usr/local/share/ca-certificates/k8s-local/
   ```

4. **Force a sync:**
   ```bash
   sudo systemctl start k8s-local-ca-sync.service
   ```

5. **Restart browser completely** (not just reload page)

### Firefox not trusting certificates?

Firefox uses its own certificate store. See the main documentation:
```bash
cat ../docs/install-local-ca.md
```

## How It Works

1. **Discovery**: Scans all namespaces for cert-manager certificates
2. **Extract**: Gets CA cert (or self-signed cert) from secrets
3. **Install**: Saves to `/usr/local/share/ca-certificates/k8s-local/`
4. **Cleanup**: Removes certificates no longer in cluster
5. **Update**: Runs `update-ca-certificates` to update system trust store

## Schedule

- **On boot**: 2 minutes after system starts
- **Hourly**: Every 60 minutes
- **On-demand**: Run manually anytime

## Security

- Only for **local development** clusters
- Certificates are **not exported** or shared
- Auto-cleanup prevents stale certificates
- System trust store properly maintained
