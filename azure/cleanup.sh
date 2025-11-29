#!/bin/bash

# ===================================================================
# Cleanup Script for JupyterHub on Azure AKS
# Safely removes all resources
# ===================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Load environment
if [ -f ".env" ]; then
    source .env
else
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Running cleanup with manual inputs..."
    read -p "Resource Group: " RESOURCE_GROUP
    read -p "Cluster Name: " CLUSTER_NAME
fi

echo -e "${YELLOW}=========================================="
echo "CLEANUP WARNING"
echo -e "==========================================${NC}"
echo ""
echo "This will delete:"
echo "  - JupyterHub deployment and all user data"
echo "  - AKS cluster: $CLUSTER_NAME"
echo "  - All node pools and VMs"
echo "  - All persistent volumes and data"
echo "  - Resource group: $RESOURCE_GROUP (optional)"
echo ""
echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
echo ""
read -p "Type the cluster name to confirm: " CONFIRM

if [ "$CONFIRM" != "$CLUSTER_NAME" ]; then
    echo -e "${RED}Cluster name doesn't match. Aborting.${NC}"
    exit 1
fi

# -------------------------------------------------------------------
# Option 1: Delete only JupyterHub
# -------------------------------------------------------------------
echo ""
echo "Choose cleanup level:"
echo "  1) Delete only JupyterHub (keep cluster)"
echo "  2) Delete cluster (recommended)"
echo "  3) Delete everything including resource group"
echo ""
read -p "Enter choice [1-3]: " CHOICE

case $CHOICE in
    1)
        echo -e "${YELLOW}Deleting JupyterHub only...${NC}"

        helm uninstall jupyterhub -n jupyterhub || true
        kubectl delete namespace jupyterhub || true
        kubectl delete namespace cert-manager || true
        kubectl delete namespace ingress-nginx || true

        echo -e "${GREEN}✓ JupyterHub deleted${NC}"
        echo "Cluster is still running. Cost: ~$70/month"
        ;;

    2)
        echo -e "${YELLOW}Deleting cluster...${NC}"

        # First delete JupyterHub to release PVCs
        echo "Cleaning up JupyterHub..."
        helm uninstall jupyterhub -n jupyterhub || true
        kubectl delete namespace jupyterhub --wait=true || true

        # Wait a bit for cleanup
        echo "Waiting for resource cleanup..."
        sleep 30

        # Delete cluster
        echo "Deleting AKS cluster..."
        az aks delete \
          --resource-group $RESOURCE_GROUP \
          --name $CLUSTER_NAME \
          --yes \
          --no-wait

        echo -e "${GREEN}✓ Cluster deletion initiated${NC}"
        echo "Deletion will complete in ~10-15 minutes"
        echo "Resource group '$RESOURCE_GROUP' is preserved"
        ;;

    3)
        echo -e "${YELLOW}Deleting resource group...${NC}"

        # Delete entire resource group
        az group delete \
          --name $RESOURCE_GROUP \
          --yes \
          --no-wait

        echo -e "${GREEN}✓ Resource group deletion initiated${NC}"
        echo "This will delete all resources including:"
        echo "  - AKS cluster"
        echo "  - All node pools"
        echo "  - All storage"
        echo "  - All networking"
        echo ""
        echo "Deletion will complete in ~15-20 minutes"
        ;;

    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}=========================================="
echo "Cleanup initiated"
echo -e "==========================================${NC}"
echo ""
echo "Monitor progress:"
echo "  az aks list --resource-group $RESOURCE_GROUP"
echo "  az group show --name $RESOURCE_GROUP"
echo ""
echo "Clean up kubectl config:"
echo "  kubectl config get-contexts"
echo "  kubectl config delete-context $CLUSTER_NAME"
echo ""
