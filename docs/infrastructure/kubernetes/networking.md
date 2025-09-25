---
title: Networking
order: 50
---
# Networking

For local testing the routes need to be defined in `/etc/hosts`.

For example:

```bash
cat <<EOF | sudo tee -a /etc/hosts
127.0.1.1       pix.burginfra iam.burginfra
EOF
```

> [!TIP]
> It might be needed to restart `k3s`:
> ```bash
> sudo systemctl restart k3s
> ```

## HTTPS

A redirect from HTTP to HTTPS is enabled by defualt for the [traefik](https://traefik.io/solutions/kubernetes-ingress) ingress controller.


### Certificates (local)

For local testing you can use the self-signed certificates.

[`mkcert`](https://mkcert.dev/) can be used for this.

#### Setup
```bash
# install mkcert
sudo apt install libnss3-tools
brew install mkcert
# Install the local CA
mkcert -install
```
#### Create Certificates

```bash
mkcert "*.local.gd" "*.burginfra" "*.traefik.me"
mv _wildcard.*-key.pem privkey.pem
mv _wildcard.*.pem fullchain.pem
```

