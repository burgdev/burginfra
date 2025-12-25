# Installing Local Self-Signed CA Certificates

This guide explains how to install your Kubernetes cluster's self-signed certificates to your system's trust store, eliminating browser warnings.

## Automatic Setup (Recommended)

Set up automatic certificate synchronization that runs hourly and on boot:

```bash
cd /home/tobias/git/burgdev/burginfra
sudo ./scripts/setup_auto_ca_sync.sh
```

This will:
1. Install all certificates from **all namespaces** automatically
2. Set up a systemd timer to check for updates every hour
3. Clean up old/expired certificates automatically
4. Update on system boot

**That's it!** Certificates will now stay up-to-date automatically.

## Manual Installation

If you prefer one-time manual installation:

```bash
cd /home/tobias/git/burgdev/burginfra

# Install from all namespaces (default)
sudo ./scripts/install_local_ca.sh

# Install from specific namespace only
sudo ./scripts/install_local_ca.sh production
```

This will:
1. Extract all CA certificates from the cluster
2. Install them to `/usr/local/share/ca-certificates/k8s-local/`
3. Clean up certificates that no longer exist
4. Update your system's CA trust store
5. Restart your browser to see the changes

## Manual Installation

If you prefer to install certificates manually:

### 1. Extract Certificate

```bash
# For a specific certificate (e.g., podinfo)
kubectl --kubeconfig=~/.kube/config-localhost get secret podinfo-tls -n production \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/podinfo.crt
```

### 2. Install Certificate

```bash
# Copy to system CA directory
sudo mkdir -p /usr/local/share/ca-certificates/k8s-local
sudo cp /tmp/podinfo.crt /usr/local/share/ca-certificates/k8s-local/

# Update CA certificates
sudo update-ca-certificates
```

### 3. Restart Browser

Close and reopen your browser for changes to take effect.

## Managing Automatic Sync

### Check Status

```bash
# Check timer status
sudo systemctl status k8s-local-ca-sync.timer

# Check when it will run next
sudo systemctl list-timers k8s-local-ca-sync.timer

# View logs
sudo journalctl -u k8s-local-ca-sync.service -f
```

### Disable/Enable

```bash
# Temporarily stop
sudo systemctl stop k8s-local-ca-sync.timer

# Disable auto-sync
sudo systemctl disable k8s-local-ca-sync.timer

# Re-enable
sudo systemctl enable --now k8s-local-ca-sync.timer
```

### Force Manual Sync

```bash
# Trigger sync immediately (doesn't wait for timer)
sudo systemctl start k8s-local-ca-sync.service

# Or run the script directly
sudo ./scripts/install_local_ca.sh
```

### Uninstall

```bash
sudo systemctl disable --now k8s-local-ca-sync.timer
sudo rm /etc/systemd/system/k8s-local-ca-sync.*
sudo systemctl daemon-reload
sudo rm -rf /usr/local/share/ca-certificates/k8s-local
sudo update-ca-certificates --fresh
```

## Verify Installation

```bash
# List installed certificates
ls -la /usr/local/share/ca-certificates/k8s-local/

# Check if certificate is trusted
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt /usr/local/share/ca-certificates/k8s-local/podinfo-tls.crt
```

## Browser-Specific Notes

### Chrome/Chromium
- Certificates are automatically loaded from the system trust store
- May need to restart browser completely (not just reload)
- Check: Settings → Privacy and security → Security → Manage certificates

### Firefox
Firefox uses its own certificate store and doesn't automatically use system certificates.

**Option 1: Import manually**
1. Go to `about:preferences#privacy`
2. Scroll to "Certificates" → Click "View Certificates"
3. Click "Import" and select the certificate file

**Option 2: Force Firefox to use system certificates**
Add to `/etc/firefox/policies/policies.json`:
```json
{
  "policies": {
    "Certificates": {
      "ImportEnterpriseRoots": true
    }
  }
}
```

## Troubleshooting

### Still seeing warnings?

1. **Hard refresh**: Press `Ctrl+Shift+R` in your browser
2. **Clear SSL cache**: 
   ```bash
   # Chrome/Chromium
   chrome://net-internals/#sslReset
   ```
3. **Check certificate validity**:
   ```bash
   openssl x509 -in /usr/local/share/ca-certificates/k8s-local/podinfo-tls.crt -text -noout
   ```
4. **Verify system trust**:
   ```bash
   update-ca-certificates -v
   ```

### Certificate expired?

If you're using automatic sync, certificates are updated automatically when renewed. If not:

```bash
sudo ./scripts/install_local_ca.sh
```

## Security Considerations

- These certificates are **only for local development**
- Do NOT use self-signed certificates in production
- For production, use Let's Encrypt (already configured in your cluster)
- Self-signed certificates should NEVER be distributed to users

## How It Works

The automatic sync system:

1. **Systemd Timer**: Runs every hour and on boot
2. **Certificate Discovery**: Scans all namespaces for certificates
3. **Smart Updates**: Only updates changed/new certificates
4. **Cleanup**: Removes certificates that no longer exist in cluster
5. **Logging**: All changes logged to systemd journal

Certificates are named: `{namespace}_{certificate-name}.crt`

Example: `production_podinfo-tls.crt`, `staging_immich-server-tls.crt`
