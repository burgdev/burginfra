# Podinfo Zitadel OIDC Configuration

This Terraform configuration creates a Zitadel project and OIDC application for Podinfo.

## How it works

1. **Flux Integration**: The `terraform.yaml` file in the base directory defines a Terraform resource that Flux manages
2. **Variable Substitution**: Variables are injected from the cluster-settings ConfigMap using Flux's `varsFrom`
3. **Automatic Deployment**: Flux applies this per environment (staging/production) with appropriate variables
4. **Credential Storage**: OIDC credentials are written to a Kubernetes Secret for use by the application

## Variables

Variables are provided by Flux from:

- `cluster-settings` ConfigMap (BURGDEV_HOST)
- Inline substitution (ENVIRONMENT, derived domains)
- `zitadel-terraform-credentials` Secret (JWT profile for authentication)

## Outputs

The following outputs are written to the `podinfo-oidc-credentials` Secret:

- `client_id`: OIDC client ID
- `client_secret`: OIDC client secret
- `issuer_url`: OIDC issuer URL
- `authorization_endpoint`: OAuth2 authorization endpoint
- `token_endpoint`: OAuth2 token endpoint
- `userinfo_endpoint`: OIDC userinfo endpoint

## Cleanup

When you remove the terraform.yaml resource, Flux will automatically destroy the Terraform resources, removing the project and application from Zitadel.
