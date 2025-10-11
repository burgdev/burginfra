---
title: Applications
order: 10
---
# Kubernetes Applications

This document lists and describes the applications running on our Kubernetes cluster.

[[toc]]

## [Immich](/apps/immich) <Badge type="info" text="immich" /> 

Self-hosted photo and video backup solution

### Storage
  - PostgreSQL database volume (managed by the chart)
  - Local library storage at `/mnt/immich/library` (defined in settings)

### Settings
Settings are in `.env` files which need to be changed accordingly:

::: code-group

```bash [edit settings]
cd k8s/immich
cp .env.template .env
cp .env.secret.template .env.secret
vi .env
vi .env.secret
```
<<< @/../k8s/immich/base/.env.template{dotenv}
<<< @/../k8s/immich/base/.env.secret.template{dotenv}
:::

### Commands

<K8sCommandsSnippet namespace="immich" path="k8s/immich" />

### Backup & Restore


[Immich documentation](https://docs.immich.app/administration/backup-and-restore/)

The backup is done automatically or manually inside immich.

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
  pg_restore --username=immich --dbname=immich -v --clean --format=custom --if-exists --verbose $BACKUP_FILE

# from sql
kubectl exec -it -n immich $POD -- psql --username=immich --dbname=immich -f $BACKUP_FILE

# all
kubectl exec -it -n immich $POD -- psql --username=immich -f $BACKUP_FILE
```
<<< @/../k8s/immich/restore-db.sh{bash} [restore-db.sh script]

```bash [backup command]
BACKUP_FILE=path/to/immich_dump.dump
DB_USERNAME=immich
kubectl exec -it -n immich $POD -- \
  pg_dumpall --clean --format=custom--if-exists --username=$DB_USERNAME | gzip > "$BACKUP_FILE"
```
:::

## DB Access

Forward port and access for example with `dbeaver`.

```bash
kubectl port-forward -n immich pod/$POD 6543:5432
```

## Infos

Immich kubernetes setup by [jasjeetsri](https://github.com/jasjeetsuri/myk3s/tree/main/yaml_configs/immich)



## [Zitadel](/apps/zitadel) <Badge type="info" text="zitadel" /> 

Identity and access management (_iam_) platform.

### Storage
One volume for database

### Backup
Not yet

### Commands

<K8sCommandsSnippet namespace="zitadel" path="k8s/zitadel" />
