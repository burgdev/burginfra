# OpenBao Policies

This directory contains OpenBao policies that are automatically deployed and configured.

## Policy Metadata

Add these comment lines at the top of your `.hcl` policy file:

```hcl
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: staging,production
# KUBERNETES_SERVICE_ACCOUNT: custom-sa-name
```

### Variables

- **`OPENBAO_ACCESS`** (optional): Access method for this policy. Currently only `kubernetes` is supported. If omitted, only the policy is created without any access configuration.
  - Example: `kubernetes`

- **`KUBERNETES_NAMESPACES`** (required if using kubernetes access): Comma-separated list of K8s namespaces that can use this policy, or `*` for all namespaces.
  - Example: `staging,production` or `*`

- **`KUBERNETES_SERVICE_ACCOUNT`** (optional): K8s service account name. Default: `vault-secrets-operator-controller-manager`
  - Example: `my-service-account`

### How It Works

**Regular policy (multiple namespaces):**

```hcl
# Policy file: apps-kv-staging.hcl
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: staging,production
```

Creates one Kubernetes role: `apps-kv-staging` bound to namespaces `staging` and `production`

**Wildcard namespace:**

```hcl
# Policy file: infra-kv-all.hcl
# OPENBAO_ACCESS: kubernetes
# KUBERNETES_NAMESPACES: *
```

Creates one Kubernetes role: `infra-kv-all` bound to all namespaces (`*`)

**No access configuration:**

```hcl
# No OPENBAO_ACCESS metadata
```

Only creates the policy - no Kubernetes roles created. Use this for policies that are manually assigned or referenced by other policies.

## Examples

See [policy.template.hcl](policy.template.hcl) for a complete example.

## Adding a New Policy

1. **Create the policy file** `my-policy.hcl` in this directory with metadata comments

2. **Add to kustomization.yaml**:

   ```yaml
   configMapGenerator:
     - name: openbao-policies
       files:
         - policies/my-policy.hcl
   ```

3. **Add VaultAuth resource** in `k8s/infrastructure/vault-secrets-operator/base/vaultauth.yaml`:

   ```yaml
   ---
   apiVersion: secrets.hashicorp.com/v1beta1
   kind: VaultAuth
   metadata:
     name: my-policy
   spec:
     method: kubernetes
     mount: kubernetes
     vaultConnectionRef: openbao-${ENVIRONMENT}
     kubernetes:
       role: my-policy
       serviceAccount: vault-secrets-operator-controller-manager
   ```

   **Important:** The VaultAuth `name` and `role` must match the policy filename (without `.hcl`)

4. **Commit and push**

The policy will be automatically deployed by Flux and configured by the `openbao-configure-policies` job.

## Not Yet Implemented

- Token auth method
- AppRole auth method
- LDAP auth method
- Other auth methods

The metadata format supports future expansion:

```hcl
# OPENBAO_ACCESS: kubernetes,token
# KUBERNETES_NAMESPACES: production
# TOKEN_RENEWABLE: true
# TOKEN_TTL: 24h
```

## Resources

- [OpenBao Policy Syntax](https://openbao.org/docs/concepts/policies/)
- [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/platform/k8s/vso)
