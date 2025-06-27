#!/bin/bash

# ==============================================================================
# SideroLabs Omni Example Cluster Management Script
#
# This script provides commands to deploy, resync, or destroy the Talos
# Kubernetes cluster managed by SideroLabs Omni.
#
# Prerequisites:
# 1. An Omni account with registered machines.
#    (https://signup.siderolabs.io/)
# 2. `omnictl` CLI tool installed and configured.
#    (https://omni.siderolabs.com/how-to-guides/install-and-configure-omnictl)
# 3. Machine Classes 'omni-contrib-controlplane' and 'omni-contrib-workers'
#    configured in your Omni instance.
# ==============================================================================

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
# The cluster name is derived from the 'name' field in the cluster template.
CLUSTER_NAME="Talos"
# The main template file for cluster definition.
TEMPLATE_FILE="infra/cluster-template.yaml"

# --- Functions ---

# Function to display usage information
usage() {
    echo "Usage: $0 {deploy|resync|destroy}"
    echo
    echo "This script manages the lifecycle of the SideroLabs Omni example cluster."
    echo
    echo "Commands:"
    echo "  deploy   : Creates or updates the cluster based on the template file."
    echo "  resync   : Resyncs the cluster with the template. Equivalent to 'deploy'."
    echo "  destroy  : Deletes the '$CLUSTER_NAME' cluster from Omni."
    echo
    exit 1
}

# Function to check for necessary prerequisites before running commands
check_prereqs() {
    echo "--> Checking for prerequisites..."
    if ! command -v omnictl &> /dev/null; then
        echo "Error: omnictl CLI tool not found." >&2
        echo "Please install and configure it as per the documentation: https://omni.siderolabs.com/how-to-guides/install-and-configure-omnictl" >&2
        exit 1
    fi
    echo "✔️  omnictl found."

    if [ ! -f "$TEMPLATE_FILE" ]; then
        echo "Error: Cluster template file not found at '$TEMPLATE_FILE'." >&2
        echo "Please ensure you are running this script from the root of the 'omni-contrib' repository." >&2
        exit 1
    fi
    echo "✔️  Cluster template file found."
    echo
}

# Function to deploy or resync the cluster
# This action is idempotent; it creates the cluster if it doesn't exist or
# updates it to match the template if it already exists.
deploy_or_resync() {
    echo "--> Syncing cluster template '$TEMPLATE_FILE' with Omni..."
    echo "This will create the '$CLUSTER_NAME' cluster if it doesn't exist, or update it if it does."
    echo

    # === FIX START ===
    # Change to the infra directory to resolve relative patch paths correctly.
    # We use a subshell (...) to ensure the directory change is temporary.
    (
        cd "$(dirname "$TEMPLATE_FILE")" && \
        omnictl cluster template sync --file "$(basename "$TEMPLATE_FILE")"
    )
    # === FIX END ===
    
    echo
    echo "--> Sync command executed successfully."
    echo "Omni will now begin to allocate machines and bootstrap the cluster."
    echo "You can monitor the progress in your Omni dashboard."
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

# Check for arguments
if [ "$#" -ne 1 ]; then
    usage
fi

ACTION=$1

check_prereqs

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