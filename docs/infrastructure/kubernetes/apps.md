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
<<< @/../k8s/immich/.env.template{dotenv}
<<< @/../k8s/immich/.env.secret.template{dotenv}
:::

### Commands

<K8sCommandsSnippet namespace="immich" path="k8s/immich" />

## [Zitadel](/apps/zitadel) <Badge type="info" text="zitadel" /> 

Identity and access management (_iam_) platform.

### Storage
One volume for database

### Backup
Not yet

### Commands

<K8sCommandsSnippet namespace="zitadel" path="k8s/zitadel" />