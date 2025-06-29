#!/bin/bash

# ==============================================================================
# SideroLabs Omni Example Cluster Management Script
#
# This script provides commands to deploy, resync, or destroy the Talos
# Kubernetes cluster managed by SideroLabs Omni. It now includes a command
# to install bash completion for its options and detects OIDC auth issues.
#
# Prerequisites:
# 1. An Omni account with registered machines.
#    (https://signup.siderolabs.io/)
# 2. `omnictl` CLI tool installed and configured.
#    (https://omni.siderolabs.com/how-to-guides/install-and-configure-omnictl)
# 3. `kubectl` with OIDC correctly configured for your cluster.
# 4. Machine Classes 'omni-contrib-controlplane' and 'omni-contrib-workers'
#    configured in your Omni instance.
# ==============================================================================

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
# The cluster name is derived from the 'name' field in the cluster template.
CLUSTER_NAME="Talos" #
# The main template file for cluster definition.
TEMPLATE_FILE="infra/cluster-template.yaml" #
# The Omni Service Account secret ID from Bitwarden Secrets Manager.
export OMNI_SERVICEACCOUNT_SECRET_ID="459a62b0-31fb-4f07-9976-b30800cbe5d8"

# --- Functions ---

# Function to display usage information
usage() {
    echo "Usage: $0 {deploy|resync|destroy|install-completion}"
    echo
    echo "This script manages the lifecycle of the SideroLabs Omni example cluster."
    echo
    echo "Commands:"
    echo "  deploy              : Creates or updates the cluster based on the template file."
    echo "  resync              : Resyncs the cluster with the template. Equivalent to 'deploy'."
    echo "  destroy             : Deletes the '$CLUSTER_NAME' cluster from Omni."
    echo "  install-completion  : Installs bash completion for this script into your ~/.bashrc file."
    echo
    exit 1
}

# The bash completion function that will be installed.
# It provides autocompletion for the script's commands.
_manage_cluster_completions() {
    local cur_word commands
    cur_word="${COMP_WORDS[COMP_CWORD]}"
    commands="deploy resync destroy install-completion"

    # Only complete the first argument after the script name.
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${commands}" -- "${cur_word}") )
    fi
}

# Function to install the bash completion logic into the user's .bashrc
install_completion() {
    local bashrc_file="$HOME/.bashrc"
    local completion_tag="# SideroLabs Omni cluster management script completion"

    echo "--> Checking for existing bash completion setup in $bashrc_file..."

    if grep -qF "$completion_tag" "$bashrc_file"; then
        echo "✔️  Completion is already installed in '$bashrc_file'."
        echo "To apply changes, please uninstall the old block of code from your .bashrc and run this again."
        return
    fi

    echo "--> No existing setup found. Installing completion..."
    {
        echo
        echo "$completion_tag"
        # Use 'declare -f' to get the source code of the completion function
        # and append it to .bashrc.
        declare -f _manage_cluster_completions
        # Register the completion function for different ways of calling the script.
        echo "complete -F _manage_cluster_completions ./manage-cluster.sh"
        echo "complete -F _manage_cluster_completions manage-cluster.sh"
    } >> "$bashrc_file"

    echo "✔️  Completion logic successfully added to '$bashrc_file'."
    echo
    echo "To activate it, please run the following command or open a new terminal:"
    echo "  source $bashrc_file"
}


# Function to deploy or resync the cluster
deploy_or_resync() {
    echo "--> Syncing cluster template '$TEMPLATE_FILE' with Omni..."
    echo "This will create the '$CLUSTER_NAME' cluster if it doesn't exist, or update it if it does."
    echo

    (
        cd "$(dirname "$TEMPLATE_FILE")" && \
        omnictl cluster template sync --file "$(basename "$TEMPLATE_FILE")"
    )

    echo
    echo "--> Sync command executed successfully."
    echo "Omni will now begin to allocate machines and bootstrap the cluster."

    # Wait for the Kubernetes API to be ready before proceeding
    echo "--> Waiting for Kubernetes API server to be ready..."
    while ! kubectl get nodes > /dev/null 2>&1; do
        echo "    Kubernetes API not available yet. Retrying in 10 seconds..."
        sleep 10
    done
    echo "✔️  Kubernetes API is ready."

    # Wait for the Cilium Operator deployment to exist.
    echo "--> Waiting for the Cilium Operator deployment to be created..."
    until kubectl get deployment cilium-operator -n kube-system > /dev/null 2>&1; do
        echo "    Cilium Operator deployment not found yet. Retrying in 10 seconds..."
        sleep 10
    done
    echo "✔️  Cilium Operator deployment found."

    # Wait for the Cilium Operator deployment to complete its rollout.
    echo "--> Waiting for Cilium Operator to become available..."
    kubectl rollout status deployment/cilium-operator -n kube-system --timeout=5m
    echo "✔️  Cilium Operator is ready."

    echo
    echo "--> Deployment complete. The cilium-ingress service should now receive an external IP."
}


# Function to destroy the cluster
destroy() {
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!! WARNING: This is a destructive action that cannot be undone. !!"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
    echo "You are about to permanently delete the '$CLUSTER_NAME' cluster from Omni."

    # User confirmation prompt
    read -p "Are you sure you want to continue? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "--> Proceeding with cluster destruction..."
        omnictl cluster delete "$CLUSTER_NAME"
        echo
        echo "--> Cluster '$CLUSTER_NAME' deletion initiated."
    else
        echo "--> Cluster destruction cancelled by user."
    fi
}


# --- Main Script Logic ---

# Handle install-completion separately as it has no other prerequisites.
if [[ "$1" == "install-completion" ]]; then
    install_completion
    exit 0
fi

# Check for arguments
if [ "$#" -ne 1 ]; then
    usage
fi

ACTION=$1

case $ACTION in
    deploy|resync)
        deploy_or_resync
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
