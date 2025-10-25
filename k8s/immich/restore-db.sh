#!/bin/bash
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd $SCRIPT_DIR
# Color definitions (using tput for better compatibility)
if [ -t 1 ]; then
  # Only define colors if output is a terminal
  b=$(tput bold); d=$(tput dim); i=$(tput sitm); rst=$(tput sgr0); u=$(tput smul); nu=$(tput rmul)
  red=$(tput setaf 1); green=$(tput setaf 2); yellow=$(tput setaf 3); blue=$(tput setaf 4);
  cyan=$(tput setaf 6); magenta=$(tput setaf 5); white=$(tput setaf 7)
else
  # No colors if not a terminal
  b=""; rst=""; d=""; u=""; nu=""
  red=""; green=""; yellow=""; blue=""; cyan=""; magenta=""; white=""
fi

# Helper function for easier color usage
s() {
  local color=$1
  shift
  echo -n "${!color}$*${rst}"
}
debug() {
    echo "${d}$1${rst}"
}
info() {
    echo "${s}$1${rst}"
}
warn() {
    echo "${yellow}$1${rst}"
}
error() {
    echo "${red}$1${rst}"
}


USAGE="$(s d Usage:) BACKUP_FILE=<backup_file> $(s d '[POD=<pod_name>] [DB_USERNAME=<db_username>]') $(s b $0)"

if [ -z $BACKUP_FILE ]; then
    printf "$USAGE\n\n"
    warn "Set 'BACKUP_FILE' environment variable to the path of the backup file."
    exit 1
fi

# get pod name
if [ -z "$POD" ]; then
    POD=${POD:-$(kubectl get pods -n immich -l app=immich-database -o jsonpath="{.items[0].metadata.name}")}
    info "Found pod $(s yellow $POD)"
else
    debug "Using pod $(s yellow $POD)"
fi

# get environment (prefix of pod name)
ENV=$(echo "$POD" | cut -d'-' -f1)

cd overlays/$ENV
if [ -z "$DB_USERNAME" ]; then
    if [ -f .env.secret ]; then
        source .env.secret # get database user
        DB_USERNAME=$username
    else
        printf "$USAGE\n\n"
        warn "Set 'DB_USERNAME' environment variable to the database user."
        exit 1
    fi
fi
cd - > /dev/null

if [ ! -f $BACKUP_FILE ]; then
    printf "$USAGE\n\n"
    warn "Could not find file 'BACKUP_FILE' (env variable BACKUP_FILE)."
    exit 1
fi

info "Restore database from '$(s blue $BACKUP_FILE)' file into '$(s yellow $POD)' as user '$(s blue $DB_USERNAME)'."
read -p "Are you sure? [y/N] " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]; then
    DEPLOYMENT=${ENV}-immich-server
    replicas=$(kubectl get deployment -n immich $DEPLOYMENT -o jsonpath="{.spec.replicas}")
    info "Stopping deployment $(s yellow $DEPLOYMENT)"
    kubectl scale deployment $DEPLOYMENT --replicas=0 -n immich
    gunzip --stdout "$BACKUP_FILE" \
        | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
        |  kubectl exec -it -n immich $POD -- psql --username=$DB_USERNAME --dbname=postgres
    info "Starting deployment $(s yellow $DEPLOYMENT) (replicas=$(s blue $replicas))"
    kubectl scale deployment $DEPLOYMENT --replicas=$replicas -n immich
else
    error "Aborted."
    exit 1
fi
