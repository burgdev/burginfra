import 'core.just'


# 🚀 Initialize openbao (cluster: local|burginfra)
init cluster="local" namespace="burginfra-system":
    @header "$(doc bao init)"
    @{{justfile_dir()}}/k8s/infrastructure/openbao/init-openbao -c {{cluster}} -n {{namespace}}

# 🚀 Restore openbao (interactive)
restore:
    @header "$(doc bao restore)"
    @{{justfile_dir()}}/k8s/infrastructure/openbao/restore


# ❓ Show help
[private]
[default]
help task="":
    @just-help bao {{task}}


