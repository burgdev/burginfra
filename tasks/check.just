import 'core.just'

# ▶️  Run all core quality checks (default)
[default]
all: format conform

# 🧹 Format code
format:
    @header "$(doc check format)"
    ~/go/bin/yamlfmt -lint k8s
    @success "🏁 Format passed!"

# 🧹 Format code
conform:
    @header "$(doc check conform)"
    # Ignored classes (by design, see PR):
    #  - values / *_patch / deployment-(cors|entrypoint) / app configs
    #    (graphhopper config.yml, mapproxy.yaml) / docker-compose examples /
    #    restic+volsync JSONs — not standalone k8s manifests
    #  - vso-*-envvars — top-level YAML arrays, not single resources
    #  - the listed base deployments/cronjob — envsubst templates whose
    #    ${VAR} placeholders cannot satisfy the schema until rendered
    kubeconform -summary -ignore-missing-schemas \
      -ignore-filename-pattern ".*-?values.*\.yaml" \
      -ignore-filename-pattern ".*\.json$" \
      -ignore-filename-pattern ".*config\.yml$" \
      -ignore-filename-pattern ".*mapproxy\.yaml$" \
      -ignore-filename-pattern ".*docker-compose.*\.ya?ml$" \
      -ignore-filename-pattern ".*vso-.*envvars.*\.yaml$" \
      -ignore-filename-pattern ".*deployment_patch\.yaml$" \
      -ignore-filename-pattern ".*deployment-(cors-origins|entrypoint)\.yaml$" \
      -ignore-filename-pattern ".*/(graphhopper|umami|valhalla)/base/deployment\.yaml$" \
      -ignore-filename-pattern ".*/apps/backend/base/(deployment|deployment-qcluster|cronjob-availability)\.yaml$" \
      -ignore-filename-pattern ".*/apps/(frontend|imagor)/base/deployment\.yaml$" \
      -output pretty k8s
    @success "🏁 Kubeconform passed!"

# ❓ Show help
[private]
help task="":
    @just-help check {{task}}
