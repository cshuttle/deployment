#!/bin/bash

# A script to scaffold the directory structure for a new component
# in the Talos/ArgoCD/Helm GitOps monorepo.

# --- Helper function for user feedback ---
log() {
  echo "✅  $1"
}

# --- Check for required tools ---
if ! command -v read &> /dev/null || ! command -v mkdir &> /dev/null; then
    echo "❌ Error: This script requires basic shell commands like 'read' and 'mkdir'."
    exit 1
fi

# --- Main Logic ---
echo "⚙️  This script will scaffold a new component in your GitOps monorepo."

# 1. Get Component Type
PS3="Select the component type: "
select COMPONENT_TYPE in application infrastructure; do
    if [[ -n "$COMPONENT_TYPE" ]]; then
        break
    else
        echo "Invalid selection. Please enter 1 or 2."
    fi
done

# 2. Get Component Name
read -p "Enter the name of the new component (e.g., 'user-service' or 'prometheus'): " COMPONENT_NAME

if [ -z "$COMPONENT_NAME" ]; then
    echo "❌ Error: Component name cannot be empty."
    exit 1
fi

log "Scaffolding for a new '$COMPONENT_TYPE' named '$COMPONENT_NAME'..."
echo "---"

# 3. Create the base monorepo structure (idempotent)
log "Creating base directories..."
mkdir -p clusters/staging
mkdir -p applications/base applications/staging
mkdir -p infrastructure/base infrastructure/staging
mkdir -p argocd/applicationsets argocd/appprojects

# Create placeholder cluster/argo files if they don't exist
touch clusters/omni.yaml
touch clusters/staging/controlplane.yaml
touch clusters/staging/worker.yaml
touch argocd/applicationsets/apps-applicationset.yaml
touch argocd/applicationsets/infra-applicationset.yaml
touch argocd/appprojects/applications-project.yaml
touch argocd/appprojects/infrastructure-project.yaml


# 4. Create the component-specific structure
if [ "$COMPONENT_TYPE" == "application" ]; then
    # --- Application Scaffolding ---
    log "Building 'application' structure..."
    APP_BASE_PATH="applications/base/$COMPONENT_NAME"
    APP_OVERLAY_PATH="applications/staging/$COMPONENT_NAME"

    mkdir -p "$APP_BASE_PATH/templates"
    mkdir -p "$APP_OVERLAY_PATH"

    # Create placeholder Helm Chart files
    touch "$APP_BASE_PATH/Chart.yaml"
    touch "$APP_BASE_PATH/values.yaml"
    touch "$APP_BASE_PATH/templates/deployment.yaml"
    touch "$APP_BASE_PATH/templates/service.yaml"
    touch "$APP_BASE_PATH/templates/_helpers.tpl"

    # Create placeholder staging values
    touch "$APP_OVERLAY_PATH/values.yaml"

elif [ "$COMPONENT_TYPE" == "infrastructure" ]; then
    # --- Infrastructure Scaffolding ---
    log "Building 'infrastructure' structure..."
    INFRA_BASE_PATH="infrastructure/base/$COMPONENT_NAME"
    INFRA_OVERLAY_PATH="infrastructure/staging/$COMPONENT_NAME"

    mkdir -p "$INFRA_BASE_PATH/templates"
    mkdir -p "$INFRA_OVERLAY_PATH"

    # Create placeholder Helm Chart files
    touch "$INFRA_BASE_PATH/Chart.yaml"
    touch "$INFRA_BASE_PATH/values.yaml"
    touch "$INFRA_BASE_PATH/templates/release.yaml"

    # Create placeholder staging values
    touch "$INFRA_OVERLAY_PATH/values.yaml"
fi

echo "---"
log "Scaffolding complete!"
echo "➡️  Next steps: "
echo "   1. Edit the placeholder files in the '/base/$COMPONENT_NAME' directory to define your component."
echo "   2. Configure your staging environment in the '/staging/$COMPONENT_NAME/values.yaml' file."
echo "   3. Commit the new files to your Git repository."

