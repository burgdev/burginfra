# CloudNativePG Operator

CloudNativePG is a Kubernetes operator that manages PostgreSQL clusters natively in Kubernetes.

## Architecture

This deployment follows a **separate database cluster per application** pattern:

- One CloudNativePG operator (cluster-scoped) manages all PostgreSQL instances
- Each application gets its own dedicated PostgreSQL cluster
- Provides isolation, independent scaling, and easier disaster recovery

## Services Created

PostgreSQL clusters are deployed alongside their applications.

When you deploy a CloudNativePG cluster (e.g., `zitadel-postgres`), it automatically creates:

- `{name}-rw` - Read-write service (primary instance)
- `{name}-ro` - Read-only service (replicas only)
- `{name}-r` - Read service (all instances)

Example for Zitadel:

- `zitadel-postgres-rw` - Primary PostgreSQL instance
- `zitadel-postgres-ro` - Read replicas (if instances > 1)
- `zitadel-postgres-r` - Read from any instance

## Monitoring

The operator includes:

- **PodMonitor**: Automatic Prometheus scraping
- **Grafana Dashboard**: Pre-built dashboard for PostgreSQL metrics

## Backup Configuration

Backup support is available but not configured by default. To enable backups:

1. Configure an S3-compatible object storage endpoint
2. Create credentials secret
3. Uncomment the backup section in the cluster manifest
4. Set retention policy

See individual cluster configurations for backup examples.

## Resources

- **Documentation**: <https://cloudnative-pg.io/>
- **GitHub**: <https://github.com/cloudnative-pg/cloudnative-pg>
- **Chart**: <https://github.com/cloudnative-pg/charts>
