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
    kubeconform -summary -ignore-missing-schemas -ignore-filename-pattern ".*-?values.*\.yaml" -output pretty k8s
    @success "🏁 Kubeconform passed!"

# ❓ Show help
[private]
help task="":
    @just-help check {{task}}
