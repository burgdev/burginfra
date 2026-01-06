---
title: Prometheus Stack
aside: false
---

# Prometheus Stack

[Prometheus](https://prometheus.io/) together with [Grafana](https://grafana.com/) is deployed with the [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).

## Setup

:memo: [Source Code](https://github.com/burgdev/burginfra/tree/main/k8s/infrastructure/kube-prometheus-stack)

::: details :gear: Configuration {open}
<<< @/../k8s/infrastructure/kube-prometheus-stack/configs/.env.template{dotenv:no-line-numbers} [configs/.env.template]
:::

::: details :package: Helm Installation
::: code-group
<<< @/../k8s/infrastructure/kube-prometheus-stack/helm/base/values.yaml{yaml} [helm/base/values.yaml]
<<< @/../k8s/infrastructure/kube-prometheus-stack/helm/base/helmrelease.yaml{yaml} [helm/base/helmrelease.yaml]
:::
