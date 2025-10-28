#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(realpath $SCRIPT_DIR/../../)"
. $ROOT_DIR/scripts/_base.sh
cd $SCRIPT_DIR


# Check if environment parameter is provided
if [ $# -lt 1 ]; then
    error "Usage: $(s b $0) <local|prod> [namespace]"
    exit 1
fi

# Validate environment
ENV="$1"
if [ "$ENV" != "local" ] && [ "$ENV" != "prod" ]; then
    error "Invalid environment: $ENV. Must be 'local' or 'prod'"
    error "Usage: $(s b $0) <local|prod> [namespace]"
    exit 1
fi
if [ "$ENV" == "local" ] && [[ $(basename $KUBECONFIG) != "config" ]]; then
    error "KUBECONFIG is not set to 'config'"; exit 1
fi
if [ "$ENV" == "prod" ] && [[ $(basename $KUBECONFIG) != "config-infra.burgdev.ch" ]]; then
     error "KUBECONFIG is not set to 'config-infra.burgdev.ch'"; exit 1
fi

# Get current namespace from kubeconfig if not provided
if [ $# -lt 2 ] || [ -z "$2" ]; then
    NAMESPACE=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null ||:)
    if [ -z "$NAMESPACE" ]; then
        error "No namespace provided and couldn't determine current namespace from kubeconfig"
        exit 1
    fi
    info "Using current namespace from kubeconfig: $NAMESPACE"
else
    NAMESPACE=${2}
fi

title "Deleting all immich resources in namespace '$NAMESPACE' (env: $ENV)"
read -p "Are you sure to coninue? [y/N] " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    error "Aborted."
    exit 1
fi


# Delete all resources except the namespace itself
info "Deleting all resources in namespace $NAMESPACE..."
kubectl delete all --all -n "$NAMESPACE" --wait=false

# Also delete PVCs if they exist
if kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null; then
    info "Deleting PVCs..."
    kubectl delete pvc --all -n "$NAMESPACE" --wait=false
    info "Deleting PVs..."
    kubectl get pv | grep $NAMESPACE | awk '{print $1}' | xargs -I{} kubectl delete pv {}
fi

info "Waiting for resources to be deleted..."
kubectl wait --for=delete all --all -n "$NAMESPACE" --timeout=300s 2>/dev/null ||:

# Final verification with timeout
check_resources() {
    # Use a timeout to prevent hanging
    timeout 30s bash -c '
    remaining=$(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | \
               xargs -n 1 -P 4 -I {} sh -c "kubectl get --show-kind --ignore-not-found -n "'"$NAMESPACE"'" {} 2>/dev/null | tail -n +2" | wc -l)
    echo $remaining
    ' 2>/dev/null || echo "timeout"
}

info "Verifying all resources are deleted (this may take a moment)..."
remaining_resources=$(check_resources)

# If we got a timeout, try a simpler check
if [ "$remaining_resources" == "timeout" ]; then
    warn "Resource check timed out. Trying simplified check..."
    remaining_resources=$(kubectl get all,pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
fi

if [ "${remaining_resources//[[:space:]]/}" -gt 0 ] 2>/dev/null; then
    warn "Some resources might still exist in namespace '$NAMESPACE':"
    
    # Show remaining resources with a timeout
    timeout 10s kubectl get all,pvc -n "$NAMESPACE" 2>/dev/null || \
        warn "(Resource list timed out, continuing...)"
    
    warn "Trying to force delete remaining resources..."
    
    # Try to delete any remaining resources with timeout
    timeout 30s kubectl delete all,pvc --all --grace-period=0 --force --ignore-not-found -n "$NAMESPACE" 2>/dev/null || \
        warn "(Force delete timed out, continuing...)"
    
    # Final simplified check
    remaining_after_force=$(kubectl get all,pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    
    if [ "$remaining_after_force" -gt 0 ]; then
        warn "Some resources might still exist in namespace '$NAMESPACE':"
        kubectl get all,pvc -n "$NAMESPACE" --no-headers 2>/dev/null ||:
        
        # Check for terminating resources
        terminating=$(kubectl get all,pvc -n "$NAMESPACE" --no-headers 2>/dev/null | grep "Terminating" ||:)
        if [ -n "$terminating" ]; then
            warn "Some resources are still terminating. This is normal and they will be removed shortly."
            warn "You can check their status with: $(s b "kubectl get all,pvc -n $NAMESPACE")"
            success "Cleanup initiated. You can safely exit with Ctrl+C if needed."
            exit 0
        else
            error "Failed to delete all resources. Some resources might be stuck."
            error "You may need to manually clean up these resources."
            exit 1
        fi
    else
        success "Successfully force-deleted all resources in namespace '$NAMESPACE'"
    fi
else
    success "All resources in namespace '$NAMESPACE' have been successfully deleted"
fi