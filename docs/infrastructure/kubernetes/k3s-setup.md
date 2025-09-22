---
title: k3s Setup
exclude: true
---

## k3s Setup Guide


### Install k3s

```bash
# Install k3s with default options
curl -sfL https://get.k3s.io | sh -

# Verify installation
sudo k3s kubectl get nodes
```

### Configure kubectl

For non-root users to use kubectl:

```bash
mkdir -p $HOME/.kube
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

export KUBECONFIG=$HOME/.kube/config
```

Add the export line to your `~/.bashrc` or `~/.zshrc` to make it permanent.

### Verify Installation

```bash
# Check k3s service status
sudo systemctl status k3s

# Check cluster info
kubectl cluster-info

# Get nodes
kubectl get nodes
```

### Post-Installation

#### Install k9s (Terminal UI)

```bash
# For Linux
wget https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz
tar xzf k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/local/bin/

# For macOS/linux (using Homebrew)
# brew install derailed/k9s/k9s
```

### Uninstallation

To completely remove k3s:

```bash
/usr/local/bin/k3s-uninstall.sh
```
