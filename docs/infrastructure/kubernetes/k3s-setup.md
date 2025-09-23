---
title: k3s Setup
exclude: true
---
![Logo](https://k3s.io/img/k3s-logo-dark.svg){width=100}

[Official installation guide](https://docs.k3s.io/installation) | [`k9s` Installation](k9s-setup)


Run the following commands on your host PC for installation (or later on the nodes):

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

### Uninstallation

To completely remove k3s:

```bash
/usr/local/bin/k3s-uninstall.sh
```
