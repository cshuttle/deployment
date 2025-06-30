#!/bin/bash

# ==============================================================================
# SideroLabs Omni Example Cluster Management Script
#
# This script provides commands to deploy, re-deploy, or destroy the Talos
# Kubernetes cluster managed by SideroLabs Omni. It now includes a command
# to install bash completion for its options and detects OIDC auth issues.
# It has been updated to bootstrap the Bitwarden Secrets Manager Operator
# authentication token at deploy time.
#
# Prerequisites:
# 1. An Omni account with registered machines.
#    (https://signup.siderolabs.io/)
# 2. `omnictl` CLI tool installed and configured.
#    (https://omni.siderolabs.com/how-to-guides/install-and-configure-omnictl)
# 3. `kubectl` with OIDC correctly configured for your cluster.
# 4. Bitwarden Secrets Manager CLI (`bws`) installed and available in your PATH.
#    (https://bitwarden.com/help/secrets-manager-cli/)
# 5. `yq` CLI tool installed for parsing JSON/YAML.
# 6. The BWS_ACCESS_TOKEN environment variable must be exported in your shell.
# 7. Machine Classes 'omni-contrib-controlplane' and 'omni-contrib-workers'
#    configured in your Omni instance.
# ==============================================================================

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
# The cluster name is derived from the 'name' field in the cluster template.
CLUSTER_NAME="Talos" #
# The main template file for cluster definition.
TEMPLATE_FILE="infra/cluster-template.yaml" #
# The Omni Service Account secret ID from Bitwarden Secrets Manager.
export OMNI_SERVICEACCOUNT_SECRET_ID="459a62b0-31fb-4f07-9976-b30800cbe5d8" #

# --- Bitwarden Operator Bootstrap Configuration ---
# The secret ID from Bitwarden that holds the access token for the Kubernetes Operator.
# IMPORTANT: Replace this placeholder with your actual secret ID.
BW_OPERATOR_TOKEN_SECRET_ID="REPLACE_THIS_WITH_YOUR_OPERATOR_TOKEN_SECRET_ID"
# The Kubernetes namespace and secret name for the Bitwarden auth token.
BW_K8S_SECRET_NAMESPACE="storage"
BW_K8S_SECRET_NAME="bw-auth-token"


# --- Functions ---

# Function to display usage information
usage() {
    echo "Usage: $0 {deploy|re-deploy|destroy|install-completion}"
    echo
    echo "This script manages the lifecycle of the SideroLabs Omni example cluster."
    echo
    echo "Commands:"
    echo "  deploy              : Creates or updates the cluster based on the template file." #
    echo "  re-deploy           : Re-applies the cluster template. Equivalent to 'deploy'." #
    echo "  destroy             : Deletes the '$CLUSTER_NAME' cluster from Omni." #
    echo "  install-completion  : Installs or reinstalls bash completion for this script into your ~/.bashrc file." #
    echo
    exit 1
}

# The bash completion function that will be installed.
_manage_cluster_completions() {
    local cur_word commands
    cur_word="${COMP_WORDS[COMP_CWORD]}"
    commands="deploy re-deploy destroy install-completion"

    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${commands}" -- "${cur_word}") )
    fi
}

# Function to install or reinstall the bash completion logic
install_completion() {
    local bashrc_file="$HOME/.bashrc"
    local start_tag="# SideroLabs Omni cluster management script completion START"
    local end_tag="# SideroLabs Omni cluster management script completion END"
    local legacy_tag="# SideroLabs Omni cluster management script completion"

    echo "--> Checking for existing bash completion setup in $bashrc_file..." #

    if grep -qF "$start_tag" "$bashrc_file"; then
        echo "✔️  An existing installation was found." #
        read -p "Do you want to reinstall it? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "--> Removing existing completion logic..." #
            sed -i.bak "/^${start_tag}$/,/^${end_tag}$/d" "$bashrc_file"
            echo "    Backup of previous .bashrc created at ${bashrc_file}.bak" #
            echo "✔️  Existing logic removed." #
        else
            echo "--> Reinstallation cancelled." #
            return
        fi
    elif grep -qF "$legacy_tag" "$bashrc_file"; then
        echo "✔️  A legacy installation was found." #
        read -p "Do you want to automatically replace it with the new version? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "--> Removing legacy completion logic..." #
            cp "$bashrc_file" "${bashrc_file}.bak"
            local legacy_start_pattern="^${legacy_tag}$"
            local legacy_end_pattern="^complete -F _manage_cluster_completions manage-cluster.sh$"
            sed -i.sed_bak "/${legacy_start_pattern}/,/${legacy_end_pattern}/d" "$bashrc_file"
            echo "    Backup of previous .bashrc created at ${bashrc_file}.bak" #
            echo "✔️  Legacy logic removed." #
        else
            echo "--> Reinstallation cancelled. Please remove the legacy block manually to proceed." #
            return
        fi
    fi

    echo "--> Installing new completion logic..." #
    {
        echo
        echo "$start_tag"
        declare -f _manage_cluster_completions
        echo "complete -F _manage_cluster_completions ./manage-cluster.sh"
        echo "complete -F _manage_cluster_completions manage-cluster.sh"
        echo "$end_tag"
    } >> "$bashrc_file"

    echo "✔️  Completion logic successfully added to '$bashrc_file'." #
    echo
    echo "To activate it, please run the following command or open a new terminal:"
    echo "  source $bashrc_file"
}

# Function to create the Kubernetes secret for the Bitwarden Operator
create_bitwarden_auth_secret() {
    echo "--> [Extra Step] Creating Bitwarden Operator authentication secret..."

    if ! command -v bws &> /dev/null; then
        echo "    Error: 'bws' CLI not found. Please install it to proceed." >&2
        exit 1
    fi
    
    if ! command -v yq &> /dev/null; then
        echo "    Error: 'yq' CLI not found. Please install it to proceed." >&2
        exit 1
    fi

    if [ -z "$BWS_ACCESS_TOKEN" ]; then
        echo "    Error: BWS_ACCESS_TOKEN environment variable is not set." >&2
        exit 1
    fi
    
    if [[ "$BW_OPERATOR_TOKEN_SECRET_ID" == "REPLACE_THIS_WITH_YOUR_OPERATOR_TOKEN_SECRET_ID" ]]; then
        echo "    Error: BW_OPERATOR_TOKEN_SECRET_ID is not set in the script." >&2
        echo "    Please edit manage-cluster.sh and set the correct secret ID." >&2
        exit 1
    fi

    echo "    Fetching token from Bitwarden Secrets Manager..."
    local token_value
    token_value=$(bws secret get "$BW_OPERATOR_TOKEN_SECRET_ID" | yq -r '.value')

    if [ -z "$token_value" ]; then
        echo "    Error: Failed to retrieve token from Bitwarden. Check the Secret ID and your permissions." >&2
        exit 1
    fi

    echo "    Creating Kubernetes secret '$BW_K8S_SECRET_NAME' in namespace '$BW_K8S_SECRET_NAMESPACE'..."
    kubectl get ns "$BW_K8S_SECRET_NAMESPACE" > /dev/null 2>&1 || kubectl create ns "$BW_K8S_SECRET_NAMESPACE"

    # Use --dry-run and patch to create or update the secret idempotently
    kubectl create secret generic "$BW_K8S_SECRET_NAME" \
        --from-literal=token="$token_value" \
        --namespace "$BW_K8S_SECRET_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo "✔️  [Extra Step] Bitwarden Operator secret is configured."
}

# Function to deploy or re-deploy the cluster
deploy_or_redeploy() {
    echo "🚀 Starting cluster deployment/re-deployment process..." #
    echo "--> [1/4] Syncing cluster template '$TEMPLATE_FILE' with Omni..." #
    echo "    This will create the '$CLUSTER_NAME' cluster if it doesn't exist, or update it if it does." #
    echo

    (
        cd "$(dirname "$TEMPLATE_FILE")" && \
        omnictl cluster template sync --file "$(basename "$TEMPLATE_FILE")"
    )

    echo
    echo "✔️  [1/4] Sync command executed successfully." #
    echo "    Omni will now begin to allocate machines and bootstrap the cluster." #
    echo "--> [2/4] Waiting for Kubernetes API server to be ready..." #
    while ! kubectl get nodes > /dev/null 2>&1; do
        echo "    ... Kubernetes API not available yet. Retrying in 10 seconds..." #
        sleep 10
    done
    echo "✔️  [2/4] Kubernetes API is ready." #

    # Bootstrap the Bitwarden authentication secret
    create_bitwarden_auth_secret

    echo "--> [3/4] Waiting for Cilium Operator to be deployed..." #
    echo "    (a) Waiting for deployment to be created..." #
    until kubectl get deployment cilium-operator -n kube-system > /dev/null 2>&1; do
        echo "        ... Cilium Operator deployment not found yet. Retrying in 10 seconds..." #
        sleep 10
    done
    echo "    ✔️  (a) Cilium Operator deployment found." #

    echo "    (b) Waiting for rollout to complete..." #
    kubectl rollout status deployment/cilium-operator -n kube-system --timeout=5m
    echo "✔️  [3/4] Cilium Operator is ready." #

    echo "--> [4/4] Finalizing deployment..." #
    echo
    echo "✅ Deployment complete. The cilium-ingress service should now receive an external IP."
}


# Function to destroy the cluster
destroy() {
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" #
    echo "!! WARNING: This is a destructive action that cannot be undone. !!" #
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" #
    echo
    echo "You are about to permanently delete the '$CLUSTER_NAME' cluster from Omni." #

    read -p "Are you sure you want to continue? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "--> Proceeding with cluster destruction..." #
        omnictl cluster delete "$CLUSTER_NAME" #
        echo
        echo "--> Cluster '$CLUSTER_NAME' deletion initiated." #
    else
        echo "--> Cluster destruction cancelled by user." #
    fi
}


# --- Main Script Logic ---

if [[ "$1" == "install-completion" ]]; then
    install_completion
    exit 0
fi

if [ "$#" -ne 1 ]; then
    usage
fi

ACTION=$1

case $ACTION in
    deploy|re-deploy)
        deploy_or_redeploy
        ;;
    destroy)
        destroy
        ;;
    *)
        echo "Error: Invalid command '$ACTION'" >&2
        usage
        ;;
esac

exit 0