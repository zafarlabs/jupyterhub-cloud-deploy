#!/bin/bash

# ===================================================================
# Cleanup Script for JupyterHub on Google Cloud GKE
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
    read -p "Project ID: " PROJECT_ID
    read -p "Cluster Name: " CLUSTER_NAME
    read -p "Region: " REGION
fi

echo -e "${YELLOW}=========================================="
echo "CLEANUP WARNING"
echo -e "==========================================${NC}"
echo ""
echo "This will delete:"
echo "  - JupyterHub deployment and all user data"
echo "  - GKE cluster: $CLUSTER_NAME"
echo "  - All node pools and VMs"
echo "  - All persistent volumes and data"
echo "  - Load balancers and networking"
echo ""
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo ""
echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
echo ""
read -p "Type the cluster name to confirm: " CONFIRM

if [ "$CONFIRM" != "$CLUSTER_NAME" ]; then
    echo -e "${RED}Cluster name doesn't match. Aborting.${NC}"
    exit 1
fi

# Set project
gcloud config set project $PROJECT_ID

# -------------------------------------------------------------------
# Option selection
# -------------------------------------------------------------------
echo ""
echo "Choose cleanup level:"
echo "  1) Delete only JupyterHub (keep cluster)"
echo "  2) Delete cluster (recommended)"
echo ""
read -p "Enter choice [1-2]: " CHOICE

case $CHOICE in
    1)
        echo -e "${YELLOW}Deleting JupyterHub only...${NC}"

        # Get cluster credentials first
        gcloud container clusters get-credentials $CLUSTER_NAME \
          --region $REGION \
          --project $PROJECT_ID

        helm uninstall jupyterhub -n jupyterhub || true
        kubectl delete namespace jupyterhub || true
        kubectl delete namespace cert-manager || true
        kubectl delete namespace ingress-nginx || true

        echo -e "${GREEN}✓ JupyterHub deleted${NC}"
        echo ""
        echo "Cluster is still running."
        echo "Estimated cost: ~$50-70/month"
        echo ""
        echo "To delete the cluster later, run:"
        echo "  gcloud container clusters delete $CLUSTER_NAME --region $REGION"
        ;;

    2)
        echo -e "${YELLOW}Deleting cluster...${NC}"

        # First delete JupyterHub to release PVCs cleanly
        echo "Cleaning up JupyterHub resources..."
        gcloud container clusters get-credentials $CLUSTER_NAME \
          --region $REGION \
          --project $PROJECT_ID 2>/dev/null || true

        helm uninstall jupyterhub -n jupyterhub 2>/dev/null || true
        kubectl delete namespace jupyterhub --wait=true 2>/dev/null || true

        # Wait a bit for cleanup
        echo "Waiting for resource cleanup..."
        sleep 30

        # Delete cluster
        echo "Deleting GKE cluster..."
        gcloud container clusters delete $CLUSTER_NAME \
          --region $REGION \
          --project $PROJECT_ID \
          --quiet

        echo -e "${GREEN}✓ Cluster deleted${NC}"
        echo ""
        echo "All resources have been removed."
        echo "Estimated cost: $0"
        ;;

    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}=========================================="
echo "Cleanup complete"
echo -e "==========================================${NC}"
echo ""
echo "Verify deletion:"
echo "  gcloud container clusters list --project $PROJECT_ID"
echo ""
echo "Clean up kubectl config:"
echo "  kubectl config get-contexts"
echo "  kubectl config delete-context gke_${PROJECT_ID}_${REGION}_${CLUSTER_NAME}"
echo ""
echo "Check for remaining resources:"
echo "  gcloud compute disks list --project $PROJECT_ID"
echo "  gcloud compute addresses list --project $PROJECT_ID"
echo ""
