import 'core.just'

# 🌐 Serve docu for preview (default)
[default]
serve port='3031':
    @header "$(doc docs serve)"
    @info "Serving at 'localhost:{{port}}'."
    cd {{justfile_dir()}}; npx vitepress dev docs --port {{port}}

# 📦 Build docu
build:
    @header "$(doc docs build)"
    cd {{justfile_dir()}}; npx vitepress build docs
    @success "🏁 Documentation build in 'site' directory."

# ❓ Show help
[private]
help task="":
    @just-help docs {{task}}
