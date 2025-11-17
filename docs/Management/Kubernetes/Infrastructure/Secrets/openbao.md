---
title: Openbao (Vault)
aside: false
---

# Openbao (Vault)

[Openbao](https://openbao.org/) is a secure, distributed, and open source key-value store,
forked from [Hashicorp Vault](https://vaultproject.io/).

## Initialization or Restore

After the first start the "vault" needs to be [initialized](https://openbao.org/docs/configuration/self-init/) or
restored (if backup available)

::: tip
Both scripts are interacitve and you need the required credentials (usually saved in bitwarden)
:::

:::code-group

```bash:no-line-numbers [Initialization]
just bao init
```

```bash:no-line-numbers [Restore]
just bao restore
```

:::

::: details Initialization commands
The script runs basically this commands (and some more to create policies and kubernetes access):

```bash
# open a shell to openbao-0
kubectl exec -n burginfra-system -it openbao-0 -- sh
bao operator init -recovery-shares=1 -recovery-threshold=1
# without auto file based unseal: -key-shares=1 -key-threshold=1
```

::: details :memo: Initialization [source code](https://github.com/burgdev/burginfra/tree/main/k8s/infrastructure/openbao/init-openbao)
<<< @/../k8s/infrastructure/openbao/init-openbao{bash} [init-openbao (source code)]
:::

## Setup

:memo: [Source Code](https://github.com/burgdev/burginfra/tree/main/k8s/infrastructure/openbao)

::: details :key: Unseal Key {open}
<<< @/../k8s/infrastructure/openbao/configs/unseal.key.template{dotenv:no-line-numbers} [configs/unseal.key.template]
:::

::: details :package: Helm Installation
::: code-group
<<< @/../k8s/infrastructure/openbao/base/values.yaml{yaml} [base/values.yaml]
<<< @/../k8s/infrastructure/openbao/base/helmrelease.yaml{yaml} [base/helmrelease.yaml]
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
There is a [openbao secrets operator](https://github.com/openbao/openbao-secrets-operator) (BSO), which at the moment does
not give any more features and is not really maintained.
:::

The initialization script prepares the openbao pod to be able to use the VSO.
rll policies are stored under `k8s/infrastructure/openbao/base/policies/` and `VaultAuth` resources
under `k8s/infrastructure/vault-secrets-operators/base/vaultauth.yaml`.

::: warning Do not manually update the policies in openbao!
The policies are synced with the one defined in the repository, every manual change is reverted every few hours.
:::

::: details Openbao apps policies
::: code-group
<<< @/../k8s/infrastructure/openbao/base/policies/apps-kv-all.hcl{hcl} [apps-kv-all.hcl]
<<< @/../k8s/infrastructure/openbao/base/policies/apps-kv-staging.hcl{hcl} [apps-kv-staging.hcl]
<<< @/../k8s/infrastructure/openbao/base/policies/apps-kv-production.hcl{hcl} [apps-kv-production.hcl]
:::
::: details Openbao infra policies
::: code-group
<<< @/../k8s/infrastructure/openbao/base/policies/infra-kv-all.hcl{hcl} [infra-kv-all.hcl]
<<< @/../k8s/infrastructure/openbao/base/policies/infra-kv-staging.hcl{hcl} [infra-kv-staging.hcl]
<<< @/../k8s/infrastructure/openbao/base/policies/infra-kv-system.hcl{hcl} [infra-kv-system.hcl]
<<< @/../k8s/infrastructure/openbao/base/policies/openbao-admin.hcl{hcl} [openbao-admin.hcl]
:::

The `VaultAuth` resources have the same name as the policies.
::: details `VaultAuth` resources
<<< @/../k8s/infrastructure/vault-secrets-operator/base/vaultauth.yaml{yaml} [vaultauth.yaml]
:::

Example:

<<< @/../k8s/apps/podinfo/base/secrets.yaml{yaml} [vaultauth.yaml]

## Resources

* Unseal: <https://openbao.org/docs/configuration/seal/static/>
* Self-init: <https://openbao.org/docs/configuration/self-init/>
* Bank-vaults: <https://bank-vaults.dev/> (manage vault or openbao in kubernetes)

### Installation

* Installation HA with file unseal: <https://nanibot.net/posts/vault/>
* Installation standalone with tls: <https://openbao.org/docs/platform/k8s/helm/examples/standalone-tls/>
