# Production user-model bootstrap (phase 2) — run when promoting the auth modernization

The wodore-backend auth modernization (#183: `auth.User` → `accounts.User`,
django-allauth / django-oauth-toolkit / argon2-cffi / fido2) is **live on
staging only**. Production behavior is unchanged until its image is
promoted. When ready, follow this runbook — it mirrors what was done and
verified on staging (burginfra #97–#99, wodore-backend #192–#196).

## Prerequisites (already merged)

- `bootstrap_user_model` management command (idempotent, applies all
  remaining migrations itself; plain `migrate` FAILS with
  `InconsistentMigrationHistory` on pre-switch databases)
- Settings load fixed for staging/production (wodore-backend #195)
- Zitadel RP routes restored (wodore-backend #196) — SSO redirect works
- Image must be >= `sha-ddc69ac` (20260926T2308)

## Steps

1. Copy `overlays/job-migrate-bootstrap.yaml` to
   `overlays/production/` and wire it into the production overlay's
   `kustomization.yaml` (same `patches:` entry, target Job
   `wd-backend-migrate`).
2. Snapshot production users for verification:
   `python manage.py shell` → `get_user_model()` pks/emails/flags.
3. Bump `WD_BACKEND_TAG` in `k8s/apps/wodore/flux/production/flux-kustom.yaml`
   to the new image (or let the bot commit to the staging branch and promote
   as usual — the production tag lives in the production flux-kustom, so set
   it explicitly).
4. `flux reconcile kustomization app-wodore-production --with-source`
5. Watch the migrate job: expect "Pre-switch database detected —
   bootstrapping accounts.0001_initial", "users copied, pks kept",
   "retarget_user_fks: re-pointed N constraints", then the remaining
   migrations.
6. Rollouts complete on backend + qcluster.

## Verify after deploy

- `/health/` green
- `/admin/` redirects to the Zitadel SSO login and an admin can log in
- API `/v1/docs` responds; Zitadel-issued tokens still validate
- In a shell: `get_user_model()._meta.label` → `accounts.User`;
  user emails/pks match the step-2 snapshot
- qcluster: admin task runner shows the running cluster (shared cache)

## Cleanup (do not forget)

Revert the production overlay patch back to plain
`python manage.py migrate --noinput` once production is bootstrapped.
The staging patch was already removed (2026-10-08): staging bootstrapped
in #97–#99 and runs the base plain-migrate job again.
`bootstrap_user_model` is idempotent, but plain migrate is the correct
steady-state entry point.
