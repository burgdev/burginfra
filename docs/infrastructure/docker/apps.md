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
