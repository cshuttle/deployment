Of course. Manually applying files after a deployment is not ideal for a repeatable workflow. Until you have Argo CD running to manage the application lifecycle, you can automate these steps by enhancing your existing `manage-cluster.sh` script.

The goal is to make the `deploy` command smarter, so it not only deploys the cluster but also waits for the critical components to be ready before applying the final configuration layer.

### The Approach

We will modify the `deploy_or_resync` function in your `manage-cluster.sh` script to perform the following actions in sequence:

1.  Run the `omnictl cluster template sync` command as it does now.
2.  Wait for the Kubernetes API server to become available.
3.  Wait specifically for the Cilium Operator deployment to be ready, as this is the component that manages the Cilium CRDs.
4.  Once the Cilium Operator is ready, automatically apply the `ip-pool.yaml` and `l2-announcement-policy.yaml` files.

This turns your deployment into a single, idempotent command that handles the necessary ordering and waiting.

### Modified `manage-cluster.sh`

Here is the updated script. You can replace the content of your `manage-cluster.sh` with the following:

```bash
#!/bin/bash

# ==============================================================================
# SideroLabs Omni Example Cluster Management Script
#
# This script provides commands to deploy, resync, or destroy the Talos
# Kubernetes cluster managed by SideroLabs Omni. It now includes a command
# to install bash completion for its options.
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
CLUSTER_NAME="Talos" #
# The main template file for cluster definition.
TEMPLATE_FILE="infra/cluster-template.yaml" #

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
    ) #
    # === FIX END ===
    
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

    # Wait for the Cilium operator to be ready. This ensures the CRDs are registered.
    echo "--> Waiting for Cilium Operator to be ready (this can take a few minutes)..."
    kubectl wait --for=condition=available deployment/cilium-operator -n kube-system --timeout=5m
    echo "✔️  Cilium Operator is ready."

    # Apply the L2 networking configuration
    echo "--> Applying Cilium L2 networking configuration..."
    kubectl apply -f apps/kube-system/cilium/ip-pool.yaml
    kubectl apply -f apps/kube-system/cilium/l2-announcement-policy.yaml
    echo "✔️  Cilium L2 configuration applied."

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
```