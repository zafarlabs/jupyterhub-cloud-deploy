#!/bin/bash

# ===================================================================
# Cleanup JupyterHub Only (Keep AKS Cluster)
# Use this to remove JupyterHub but keep the cluster for redeployment
# ===================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -------------------------------------------------------------------
# Variables
# -------------------------------------------------------------------
NAMESPACE="jupyterhub"

# -------------------------------------------------------------------
# Warning and Confirmation
# -------------------------------------------------------------------
echo -e "${YELLOW}=========================================="
echo "Cleanup JupyterHub (Keep Cluster)"
echo -e "==========================================${NC}"
echo ""
echo "This script will DELETE:"
echo "  - JupyterHub Helm release"
echo "  - Namespace: $NAMESPACE"
echo "  - All user notebooks and data"
echo "  - All Persistent Volume Claims"
echo ""
echo "This script will KEEP:"
echo "  - AKS Cluster"
echo "  - Node pools (hubpool, userpool)"
echo ""
echo -e "${YELLOW}⚠️  User data will be permanently deleted!${NC}"
echo ""

read -p "Continue? (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo ""
    echo -e "${GREEN}Cancelled. No resources were deleted.${NC}"
    exit 0
fi

echo ""

# -------------------------------------------------------------------
# Step 1: Check kubectl connection
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 1: Checking cluster connection"
echo -e "==========================================${NC}"
echo ""

if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}✗ Not connected to any cluster${NC}"
    echo "Run: az aks get-credentials --resource-group <rg> --name <cluster>"
    exit 1
fi

CURRENT_CONTEXT=$(kubectl config current-context)
echo -e "${GREEN}✓ Connected to: $CURRENT_CONTEXT${NC}"
echo ""

# -------------------------------------------------------------------
# Step 2: List resources to be deleted
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 2: Resources to be deleted"
echo -e "==========================================${NC}"
echo ""

if kubectl get namespace $NAMESPACE &>/dev/null; then
    echo "Pods:"
    echo "-------------------------------------------"
    kubectl get pods -n $NAMESPACE 2>/dev/null || echo "No pods found"
    echo ""
    
    echo "Services:"
    echo "-------------------------------------------"
    kubectl get svc -n $NAMESPACE 2>/dev/null || echo "No services found"
    echo ""
    
    echo "Persistent Volume Claims:"
    echo "-------------------------------------------"
    kubectl get pvc -n $NAMESPACE 2>/dev/null || echo "No PVCs found"
    echo ""
    
    echo "Persistent Volumes (will be released):"
    echo "-------------------------------------------"
    kubectl get pv | grep $NAMESPACE 2>/dev/null || echo "No PVs found"
    echo ""
else
    echo -e "${YELLOW}⚠ Namespace '$NAMESPACE' not found${NC}"
    echo "JupyterHub may already be deleted."
    exit 0
fi

# -------------------------------------------------------------------
# Step 3: Delete Helm release
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 3: Deleting JupyterHub Helm release"
echo -e "==========================================${NC}"
echo ""

if helm list -n $NAMESPACE 2>/dev/null | grep -q jupyterhub; then
    echo "Uninstalling JupyterHub..."
    helm uninstall jupyterhub -n $NAMESPACE --wait --timeout 5m
    echo -e "${GREEN}✓ Helm release deleted${NC}"
else
    echo -e "${YELLOW}⚠ Helm release not found${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 4: Delete namespace
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 4: Deleting namespace"
echo -e "==========================================${NC}"
echo ""

echo "Deleting namespace '$NAMESPACE'..."
echo "(This may take 1-2 minutes)"
kubectl delete namespace $NAMESPACE --timeout=3m

echo -e "${GREEN}✓ Namespace deleted${NC}"
echo ""

# -------------------------------------------------------------------
# Step 5: Verify cleanup
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 5: Verifying cleanup"
echo -e "==========================================${NC}"
echo ""

echo "Checking for remaining resources..."

if kubectl get namespace $NAMESPACE &>/dev/null; then
    echo -e "${YELLOW}⚠ Namespace still exists (may be terminating)${NC}"
else
    echo -e "${GREEN}✓ Namespace successfully deleted${NC}"
fi

REMAINING_PVS=$(kubectl get pv 2>/dev/null | grep $NAMESPACE || echo "")
if [ -n "$REMAINING_PVS" ]; then
    echo -e "${YELLOW}⚠ Some Persistent Volumes still exist:${NC}"
    echo "$REMAINING_PVS"
    echo ""
    echo "These PVs may be in 'Released' state and can be manually deleted with:"
    echo "  kubectl delete pv <pv-name>"
else
    echo -e "${GREEN}✓ No remaining Persistent Volumes${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 6: Check cluster status
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 6: Cluster status"
echo -e "==========================================${NC}"
echo ""

echo "Current cluster nodes:"
echo "-------------------------------------------"
kubectl get nodes -L agentpool
echo ""

echo "Note: userpool nodes may take a few minutes to scale down to 0"
echo ""

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "✅ JupyterHub Cleanup Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Summary:"
echo "  ✓ JupyterHub Helm release deleted"
echo "  ✓ Namespace deleted"
echo "  ✓ User data removed"
echo "  ✓ PVCs deleted"
echo ""
echo "Cluster Status:"
echo "  ✓ AKS cluster still running"
echo "  ✓ Node pools intact (hubpool, userpool)"
echo "  ✓ Ready for redeployment"
echo ""
echo "To redeploy JupyterHub:"
echo "  ./deploy-jupyterhub.sh"
echo ""
echo "To delete the entire cluster:"
echo "  ./cleanup-all.sh"
echo ""
echo -e "${GREEN}=========================================="
echo ""
