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
>
> ```bash
> sudo systemctl restart k3s
> ```

## HTTPS

A redirect from HTTP to HTTPS is enabled by default for the [traefik](https://traefik.io/solutions/kubernetes-ingress) ingress controller.

This are the settings needed (`certmanager` and `letsencrypt-issuer` are used for production):

::: code-group
<<< @/../k8s/infrastructure/traefik/base/traefik.yaml{yaml}
<<< @/../k8s/infrastructure/traefik/overlays/prod/letsencrypt-issuer.yaml{yaml}
:::

Ingress example (`podinfo`):

::: code-group
<<< @/../k8s/apps/podinfo/base/ingress.yaml{yaml}
<<< @/../k8s/apps/podinfo/overlays/staging/ingress_patch.yaml{yaml}
:::

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


#### Other Devices

See the [`mkcert` Mobile devices](https://github.com/FiloSottile/mkcert?tab=readme-ov-file#mobile-devices) section on how to install the CA on other devices.

For Linux:

```bash
mkcert -CAROOT
```

Copy the `rootCA.pem` from this location to your device and install it.
