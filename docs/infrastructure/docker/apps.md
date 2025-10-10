---
title: Applications 
order: 30
---
# Docker Applications 

## Immich

From the [docu](https://immich.app/docs/install/docker-compose):


```bash
cp .env.template .env
vim .env # change all variables with a TODO
./update-config.sh # creates the immich.config.json file
```

```bash
docker compose up
```

Open the browser at `localhost:2283`.

### Backup

Database dump:
::: code-group
```bash [variables]
OUTPUT=$HOME/tmp/immich-db-backups/$(date +%Y%m%d_%H%M%S)_immich_db
DB_USERNAME=immich
DB_DATABASE_NAME=immich
# or
source .env
```
```bash [backup]
mkdir -p $(dirname $OUTPUT)
# DUMP (faster, not readable)
docker exec -t immich_postgres pg_dump --username=$DB_USERNAME --dbname=$DB_DATABASE_NAME \
  --clean --if-exists --format=custom > $OUTPUT.dump

# SQL (readable, slower, used to update database version)
docker exec -t immich_postgres pg_dump --username=$DB_USERNAME --dbname=$DB_DATABASE_NAME \
  --clean --if-exists > $OUTPUT.sql

# dump all
docker exec -t immich_postgres pg_dumpall --username=postgres --clean --if-exists > $OUTPUT.all.sql

# fix search path
sed -i "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
  $OUTPUT.sql
```
```bash [restore]
docker exec -t immich_postgres pg_restore --username=$DB_USERNAME --dbname=$DB_DATABASE_NAME --format=custom $OUTPUT.dump
docker exec -t immich_postgres psql --username=$DB_USERNAME --dbname=$DB_DATABASE_NAME < $OUTPUT.sql
```
:::
