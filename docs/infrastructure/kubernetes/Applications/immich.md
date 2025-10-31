---
title: Immich
order: 10
---
# Immich

Running [Immich](/apps/immich) in kuberenets:

[[toc]]


Self-hosted photo and video backup solution

## Storage
  - PostgreSQL database
  - Redis cache ([valkey](https://valkey.io/))
  - Volumes are mounted as `hostPath` volumes at `/mnt/kubernetes/volumes/immich/`
    - `cache` for cache storage (valkey)
    - `database` for database storage
    - `server/data` for data storage
    - `server/external` for external storage

## Settings
Settings are in `.env` files which need to be changed accordingly:

Copy them into `overlay/local` and `overlay/prod` and change the needed values.
You can delete all variables which are not needed, it takes the default from `base/.env.template`.

The same for `.env.secret` files, but you need to have all values defined.

::: code-group

```bash [edit settings]
cd k8s/immich
cp base/.env.template overlay/local/.env
cp base/.env.template overlay/prod/.env
cp base/.env.secret.template overlay/local/.env.secret
cp base/.env.secret.template overlay/prod/.env.secret
vim overlay/*/.env* # edit files, remove not needed variables
```
<<< @/../k8s/apps/immich/base/.env.template{dotenv}
<<< @/../k8s/apps/immich/base/.env.secret.template{dotenv}
:::

## Commands

<K8sCommandsSnippet namespace="immich" path="k8s/immich" />

## Backup & Restore

[Immich documentation](https://docs.immich.app/administration/backup-and-restore/)

The backup is done automatically or manually inside immich.

### Restore

Create database if it does not exist:

```bash
POD=$(kubectl get pods -n immich -l app=immich-database -o jsonpath="{.items[0].metadata.name}")
kubectl exec -i -n immich $POD -- \
  psql --username=immich --dbname=postgres -c "CREATE DATABASE immich WITH OWNER immich;"
```

Restore the dump:
::: code-group
```bash [restore commands]
BACKUP_FILE=path/to/immich_dump.dump
DB_USERNAME=immich

# using restore script
./k8s/immich/restore-db.sh

# MANUALLY ------------------
ENV=prod # or local
DP=${ENV}-immich-server
# stop immich server -- set it to replicas 1 again after everthing is done!
kubectl scale deployment $DP --replicas=0 -n immich

# which runs this command
gunzip --stdout "$BACKUP_FILE" \
    | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
    |  kubectl exec -it -n immich $POD -- psql --username=$DB_USERNAME --dbname=postgres

# custom commands if manuel dump was used
kubectl cp $BACKUP_FILE immich/$POD:$BACKUP_FILE
# dump
kubectl exec -it -n immich $POD -- \
  pg_restore --username=immich --dbname=immich -v --clean \
    --format=custom --if-exists --verbose $BACKUP_FILE

# from sql
kubectl exec -it -n immich $POD -- psql --username=immich \
  --dbname=immich -f $BACKUP_FILE

# all
kubectl exec -it -n immich $POD -- psql --username=immich -f $BACKUP_FILE
```
<<< @/../k8s/apps/immich/restore-db.sh{bash} [restore-db.sh script]

```bash [backup command]
BACKUP_FILE=path/to/immich_dump.dump
DB_USERNAME=immich
kubectl exec -it -n immich $POD -- \
  pg_dumpall --clean --format=custom--if-exists --username=$DB_USERNAME \
  | gzip > "$BACKUP_FILE"
```
:::

## Database Access

Forward port and access for example with [dbeaver](https://dbeaver.io/).

```bash
POD=$(kubectl get pods -n immich -l app=immich-database -o jsonpath="{.items[0].metadata.name}"
kubectl port-forward -n immich pod/$POD 6543:5432
```

## Additional Infos

* Immich kubernetes setup by [jasjeetsri](https://github.com/jasjeetsuri/myk3s/tree/main/yaml_configs/immich)
* Immich kubernetes setup by [frankzhao](https://www.frankzhao.com.au/Kubernetes/Immich)
* Immich helm chart: [github.com/immich-app/immich-charts](https://github.com/immich-app/immich-charts)
