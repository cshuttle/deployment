#!/bin/bash

# ==============================================================================
# SideroLabs Omni Example Cluster Management Script
#
# This script provides commands to deploy, re-deploy, or destroy the Talos
# Kubernetes cluster managed by SideroLabs Omni. It has been updated to
# bootstrap the Bitwarden Secrets Manager Operator authentication token at deploy
# time by sourcing all credentials securely from the 'pass' password store.
#
# Prerequisites:
# 1. An Omni account with registered machines.
# 2. `omnictl` CLI tool installed and configured.
# 3. `kubectl` configured for your cluster.
# 4. `pass` password manager CLI installed and configured with the following entries:
#    - Kubernetes/read-only-token (for bws/omnictl authentication)
#    - Kubernetes/read-only-token-kubernetes (for the in-cluster Bitwarden Operator)
# 5. Machine Classes 'omni-contrib-controlplane' and 'omni-contrib-workers'
#    configured in your Omni instance.
# ==============================================================================

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
# The cluster name is derived from the 'name' field in the cluster template.
CLUSTER_NAME="Talos"
# The main template file for cluster definition.
TEMPLATE_FILE="infra/cluster-template.yaml"
# The Omni Service Account secret ID from Bitwarden Secrets Manager.
# Note: The 'omnictl' command will use the BWS_ACCESS_TOKEN exported in the deploy function.
export OMNI_SERVICEACCOUNT_SECRET_ID="459a62b0-31fb-4f07-9976-b30800cbe5d8"

# --- Bitwarden Operator Bootstrap Configuration ---
# These values define the Kubernetes secret that will be created to hold the operator's token.
BW_K8S_SECRET_NAMESPACE="kube-system"
BW_K8S_SECRET_NAME="bw-auth-token"


# --- Functions ---

# Function to display usage information
usage() {
    echo "Usage: $0 {deploy|re-deploy|destroy}"
    echo
    echo "This script manages the lifecycle of the SideroLabs Omni example cluster."
    echo
    echo "Commands:"
    echo "  deploy              : Creates or updates the cluster based on the template file."
    echo "  re-deploy           : Re-applies the cluster template. Equivalent to 'deploy'."
    echo "  destroy             : Deletes the '$CLUSTER_NAME' cluster from Omni."
    echo
    exit 1
}

# Function to create the Kubernetes secret for the Bitwarden Operator using 'pass'
create_bitwarden_auth_secret() {
    echo "--> [Extra Step] Creating Bitwarden Operator authentication secret..."

    # Check for prerequisites
    if ! command -v pass &> /dev/null; then
        echo "    Error: 'pass' CLI not found. Please install it to proceed." >&2
        exit 1
    fi

    echo "    Fetching Bitwarden Operator's token from 'pass'..."
    local operator_token
    operator_token=$(pass show Kubernetes/read-only-token-kubernetes)

    if [ -z "$operator_token" ]; then
        echo "    Error: Failed to retrieve token from 'pass show Kubernetes/read-only-token-kubernetes'." >&2
        exit 1
    fi
    echo "    Successfully fetched operator's token."

    echo "    Creating Kubernetes secret '$BW_K8S_SECRET_NAME' in namespace '$BW_K8S_SECRET_NAMESPACE'..."
    kubectl get ns "$BW_K8S_SECRET_NAMESPACE" > /dev/null 2>&1 || kubectl create ns "$BW_K8S_SECRET_NAMESPACE"

    # Use --dry-run and patch to create or update the secret idempotently
    kubectl create secret generic "$BW_K8S_SECRET_NAME" \
        --from-literal=token="$operator_token" \
        --namespace "$BW_K8S_SECRET_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo "✔️  [Extra Step] Bitwarden Operator secret is configured."
}

# Function to deploy or re-deploy the cluster
deploy_or_redeploy() {
    echo "🚀 Starting cluster deployment/re-deployment process..."

    echo "--> [Pre-flight] Fetching BWS_ACCESS_TOKEN from 'pass' for omnictl authentication..."
    if ! command -v pass &> /dev/null; then
        echo "    Error: 'pass' CLI not found. Please install it to proceed." >&2
        exit 1
    fi
    export BWS_ACCESS_TOKEN=$(pass show Kubernetes/read-only-token)
    if [ -z "$BWS_ACCESS_TOKEN" ]; then
        echo "    Error: Failed to retrieve token from 'pass show Kubernetes/read-only-token'." >&2
        exit 1
    fi
    echo "✔️  [Pre-flight] BWS_ACCESS_TOKEN is set for omnictl."


    echo "--> [1/4] Syncing cluster template '$TEMPLATE_FILE' with Omni..."
    echo "    This will create the '$CLUSTER_NAME' cluster if it doesn't exist, or update it if it does."
    echo

    (
        cd "$(dirname "$TEMPLATE_FILE")" && \
        omnictl cluster template sync --file "$(basename "$TEMPLATE_FILE")"
    )

    echo
    echo "✔️  [1/4] Sync command executed successfully."
    echo "    Omni will now begin to allocate machines and bootstrap the cluster."
    echo "--> [2/4] Waiting for Kubernetes API server to be ready..."
    while ! kubectl get nodes > /dev/null 2>&1; do
        echo "    ... Kubernetes API not available yet. Retrying in 10 seconds..."
        sleep 10
    done
    echo "✔️  [2/4] Kubernetes API is ready."

    # Bootstrap the Bitwarden authentication secret for the in-cluster operator
    create_bitwarden_auth_secret

    echo "--> [3/4] Waiting for Cilium Operator to be deployed..."
    echo "    (a) Waiting for deployment to be created..."
    until kubectl get deployment cilium-operator -n kube-system > /dev/null 2>&1; do
        echo "        ... Cilium Operator deployment not found yet. Retrying in 10 seconds..."
        sleep 10
    done
    echo "    ✔️  (a) Cilium Operator deployment found."

    echo "    (b) Waiting for rollout to complete..."
    kubectl rollout status deployment/cilium-operator -n kube-system --timeout=5m
    echo "✔️  [3/4] Cilium Operator is ready."

    echo "--> [4/4] Finalizing deployment..."
    echo
    echo "✅ Deployment complete. The cilium-ingress service should now receive an external IP."
}


# Function to destroy the cluster
destroy() {
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!! WARNING: This is a destructive action that cannot be undone. !!"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
    echo "You are about to permanently delete the '$CLUSTER_NAME' cluster from Omni."

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