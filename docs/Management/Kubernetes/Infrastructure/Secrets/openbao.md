---
title: Openbao (Vault)
aside: false
---

# Openbao (Vault)

[Openbao](https://openbao.org/) is a secure, distributed, and open source key-value store,
forked from [Hashicorp Vault](https://vaultproject.io/).

## Initialization

After the first start the "vault" needs to be [initialized](https://openbao.org/docs/configuration/self-init/).

```bash
# open a shell to openbao-0
kubectl exec -n burginfra-system -it openbao-0 -- sh
bao operator init -recovery-shares=1 -recovery-threshold=1
# without auto file based unseal: -key-shares=1 -key-threshold=1
```

## Setup

:memo: [Source Code](https://github.com/burgdev/burginfra/tree/main/k8s/infrastructure/openbao)

::: details :key: Unseal Key {open}
<<< @/../k8s/infrastructure/openbao/configs/unseal.key.template{dotenv:no-line-numbers} [configs/unseal.key.template]
:::

::: details :package: Helm Installation
::: code-group
<<< @/../k8s/infrastructure/openbao/base/values.yaml{yaml} [base/values.yaml]
<<< @/../k8s/infrastructure/openbao/base/helmrelease.yaml{yaml} [ase/helmrelease.yaml]
:::

::: details :globe_with_meridians: Ingress
::: code-group
<<< @/../k8s/infrastructure/openbao/overlays/system/ingress.yaml{yaml} [overlays/prod/ingress.yaml (SYSTEM)]
<<< @/../k8s/infrastructure/openbao/overlays/staging/ingress.yaml{yaml} [overlays/staging/ingress.yaml (STAGING)]
:::

## Vault Secrets Operator

The [vault secrets operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso) (VSO) allows Pods
to consume Vault secrets natively from Kubernetes Secrets.

::: info
There is a [openbao secrets opertor](https://github.com/openbao/openbao-secrets-operator) (BSO), which at the moment does
not give any more features and is not really maintained.
:::

```bash
# open shell to openbao pod
kubectl exec -n burginfra-system -it openbao-0 -- sh

bao login ROOT_TOKEN # use the root token created above
bao auth enable kubernetes # enable kubernetes auth

bao write auth/kubernetes/config \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

bao write auth/kubernetes/role/default \
  bound_service_account_names=vault-secrets-operator-controller-manager \
  bound_service_account_namespaces=burginfra-system \
  policies=vso-read \
  ttl=24h
```

## Resources

* Unseal: <https://openbao.org/docs/configuration/seal/static/>
* Self-init: <https://openbao.org/docs/configuration/self-init/>

### Installation

* Installation HA with file unseal: <https://nanibot.net/posts/vault/>
* Installation standalone with tls: <https://openbao.org/docs/platform/k8s/helm/examples/standalone-tls/>
