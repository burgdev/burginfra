---
title: Openbao (Vault)
aside: false
---

# Openbao (Vault)

[Openbao](https://openbao.org/) is a secure, distributed, and open source key-value store, forked from [Hashicorp Vault](https://vaultproject.io/).

## Initialization

After the first start the "vault" needs to be [initialized](https://openbao.org/docs/configuration/self-init/).

```bash
# open a shell to openbao-0
kubectl exec -n burginfra-system -it openbao-0 -- sh
bao operator init -key-shares=1 -key-threshold=1 -recovery-shares=1 -recovery-threshold=1
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

## Resources

* Unseal: <https://openbao.org/docs/configuration/seal/static/>
* Self-init: <https://openbao.org/docs/configuration/self-init/>

### Installation

* Installation HA with file unseal: <https://nanibot.net/posts/vault/>
* Installation standalone with tls: <https://openbao.org/docs/platform/k8s/helm/examples/standalone-tls/>
