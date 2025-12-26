import 'core.just'


# 🚀 Setup server (initialization)
setup user="burg" host="infra-vps1.burgdev.ch":
    @header "$(doc server setup)"
    @warn "The script is gonna ask a few times for your users password (not root!)."
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "{{host}}"
    ssh {{user}}@{{host}} 'rm -f /tmp/setup_server.sh'
    scp {{justfile_dir()}}/scripts/setup_server.sh {{user}}@{{host}}:/tmp/setup_server.sh
    ssh -t {{user}}@{{host}} 'bash /tmp/setup_server.sh run_all'
    ssh {{user}}@{{host}} 'rm -f /tmp/setup_server.sh'
    ssh -t {{user}}@{{host}} 'sudo reboot'
    @success "Wait until server is reboot."
    @info $'Run \'\e[34mjust server bootstrap\e[0m\' to bootstrap the server (cluster init).'

# 🚀 Bootstrap server (kubernetes)
bootstrap user="burg" host="infra-vps1.burgdev.ch":
    #! ./.shell-wrapper.sh
    K3S_HOST="{{host}}"
    K3S_USER="{{user}}"
    {{justfile_dir()}}/scripts/setup_myself.sh run_all
    just flux bootstrap

# ❓ Show help
[private]
[default]
help task="":
    @just-help server {{task}}








