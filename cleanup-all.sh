#!/bin/bash

# ===================================================================
# Cleanup/Destroy AKS Cluster and JupyterHub Resources
# WARNING: This will delete all resources and data!
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
RESOURCE_GROUP="DDA-Resources-AKS"
CLUSTER_NAME="jhub-test-cluster"
NAMESPACE="jupyterhub"

# -------------------------------------------------------------------
# Warning and Confirmation
# -------------------------------------------------------------------
echo -e "${RED}=========================================="
echo "⚠️  DANGER: RESOURCE DELETION"
echo -e "==========================================${NC}"
echo ""
echo "This script will DELETE the following resources:"
echo ""
echo -e "${YELLOW}1. JupyterHub deployment (Helm release)${NC}"
echo -e "${YELLOW}2. Namespace: $NAMESPACE${NC}"
echo -e "${YELLOW}3. All user data and notebooks${NC}"
echo -e "${YELLOW}4. All Persistent Volume Claims${NC}"
echo -e "${YELLOW}5. AKS Cluster: $CLUSTER_NAME${NC}"
echo -e "${YELLOW}6. Node pools: hubpool, userpool${NC}"
echo -e "${YELLOW}7. All associated Azure resources (Load Balancers, Disks, etc.)${NC}"
echo ""
echo -e "${RED}⚠️  ALL DATA WILL BE PERMANENTLY DELETED!${NC}"
echo ""
echo "Resource Group: $RESOURCE_GROUP"
echo "Cluster Name: $CLUSTER_NAME"
echo ""

# Ask for confirmation
read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo ""
    echo -e "${GREEN}Cancelled. No resources were deleted.${NC}"
    exit 0
fi

echo ""
echo -e "${RED}Final confirmation required!${NC}"
read -p "Type the cluster name '$CLUSTER_NAME' to proceed: " CONFIRM_NAME

if [ "$CONFIRM_NAME" != "$CLUSTER_NAME" ]; then
    echo ""
    echo -e "${GREEN}Cancelled. No resources were deleted.${NC}"
    exit 0
fi

echo ""
echo -e "${RED}Starting deletion process...${NC}"
echo ""

# -------------------------------------------------------------------
# Step 1: Check if cluster exists
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 1: Checking if cluster exists"
echo -e "==========================================${NC}"
echo ""

if ! az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME &>/dev/null; then
    echo -e "${YELLOW}⚠ Cluster '$CLUSTER_NAME' does not exist${NC}"
    echo "Nothing to delete."
    exit 0
fi

echo -e "${GREEN}✓ Cluster found${NC}"
echo ""

# -------------------------------------------------------------------
# Step 2: Get cluster credentials (needed for helm/kubectl)
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 2: Connecting to cluster"
echo -e "==========================================${NC}"
echo ""

az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --overwrite-existing \
  2>/dev/null || true

echo -e "${GREEN}✓ Connected to cluster${NC}"
echo ""

# -------------------------------------------------------------------
# Step 3: Delete JupyterHub Helm release
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 3: Deleting JupyterHub (Helm release)"
echo -e "==========================================${NC}"
echo ""

if helm list -n $NAMESPACE 2>/dev/null | grep -q jupyterhub; then
    echo "Uninstalling JupyterHub Helm release..."
    helm uninstall jupyterhub -n $NAMESPACE --wait --timeout 5m
    echo -e "${GREEN}✓ JupyterHub uninstalled${NC}"
else
    echo -e "${YELLOW}⚠ JupyterHub Helm release not found (may already be deleted)${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 4: Delete namespace (and all resources in it)
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 4: Deleting namespace and resources"
echo -e "==========================================${NC}"
echo ""

if kubectl get namespace $NAMESPACE &>/dev/null; then
    echo "Listing resources to be deleted:"
    echo "-------------------------------------------"
    kubectl get all,pvc,pv,secrets,configmaps -n $NAMESPACE 2>/dev/null || true
    echo ""
    
    echo "Deleting namespace '$NAMESPACE'..."
    echo "(This may take 1-2 minutes)"
    kubectl delete namespace $NAMESPACE --timeout=3m 2>/dev/null || true
    echo -e "${GREEN}✓ Namespace deleted${NC}"
else
    echo -e "${YELLOW}⚠ Namespace '$NAMESPACE' not found (may already be deleted)${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 5: Delete orphaned PVs (if any)
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 5: Checking for orphaned Persistent Volumes"
echo -e "==========================================${NC}"
echo ""

ORPHANED_PVS=$(kubectl get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.claimRef.namespace=="'$NAMESPACE'") | .metadata.name' 2>/dev/null || echo "")

if [ -n "$ORPHANED_PVS" ]; then
    echo "Found orphaned Persistent Volumes:"
    echo "$ORPHANED_PVS"
    echo ""
    for PV in $ORPHANED_PVS; do
        echo "Deleting PV: $PV"
        kubectl delete pv $PV --timeout=30s 2>/dev/null || true
    done
    echo -e "${GREEN}✓ Orphaned PVs deleted${NC}"
else
    echo -e "${GREEN}✓ No orphaned PVs found${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 6: List cluster resources before deletion
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 6: Cluster resources to be deleted"
echo -e "==========================================${NC}"
echo ""

echo "Node Pools:"
echo "-------------------------------------------"
az aks nodepool list \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --output table 2>/dev/null || echo "Unable to list node pools"
echo ""

echo "Cluster Details:"
echo "-------------------------------------------"
az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --query "{Name:name, Location:location, KubernetesVersion:kubernetesVersion, Fqdn:fqdn}" \
  --output table 2>/dev/null || echo "Unable to get cluster details"
echo ""

# -------------------------------------------------------------------
# Step 7: Delete AKS Cluster
# -------------------------------------------------------------------
echo -e "${RED}=========================================="
echo "Step 7: Deleting AKS Cluster"
echo -e "==========================================${NC}"
echo ""
echo -e "${RED}This is the final step!${NC}"
echo "This will delete:"
echo "  - The cluster control plane"
echo "  - All node pools (hubpool, userpool)"
echo "  - All associated Azure resources (VMs, Disks, Load Balancers, NICs, etc.)"
echo ""

read -p "Proceed with cluster deletion? (type 'DELETE' to confirm): " FINAL_CONFIRM

if [ "$FINAL_CONFIRM" != "DELETE" ]; then
    echo ""
    echo -e "${GREEN}Cluster deletion cancelled.${NC}"
    echo "Helm release and namespace have been deleted, but cluster remains."
    exit 0
fi

echo ""
echo "Deleting AKS cluster..."
echo "(This takes 5-10 minutes)"
echo ""

az aks delete \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --yes \
  --no-wait

echo ""
echo -e "${GREEN}✓ Cluster deletion initiated${NC}"
echo ""
echo "The cluster is being deleted in the background."
echo "You can check the status with:"
echo "  az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME"
echo ""

# -------------------------------------------------------------------
# Step 8: Wait for deletion (optional)
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 8: Monitoring deletion progress"
echo -e "==========================================${NC}"
echo ""

read -p "Wait for deletion to complete? (y/n): " WAIT_CONFIRM

if [ "$WAIT_CONFIRM" == "y" ] || [ "$WAIT_CONFIRM" == "Y" ]; then
    echo ""
    echo "Waiting for cluster deletion to complete..."
    echo "(Press Ctrl+C to stop waiting - deletion will continue in background)"
    echo ""
    
    TIMEOUT=600  # 10 minutes
    ELAPSED=0
    
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if ! az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME &>/dev/null; then
            echo ""
            echo -e "${GREEN}✓ Cluster successfully deleted!${NC}"
            break
        fi
        
        echo -n "."
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo ""
        echo -e "${YELLOW}⚠ Timeout reached. Deletion is still in progress.${NC}"
        echo "Check status with: az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME"
    fi
fi

echo ""

# -------------------------------------------------------------------
# Step 9: Clean up local kubectl context
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 9: Cleaning up local configuration"
echo -e "==========================================${NC}"
echo ""

echo "Removing kubectl context..."
kubectl config delete-context $CLUSTER_NAME &>/dev/null || true
kubectl config delete-cluster $CLUSTER_NAME &>/dev/null || true
echo -e "${GREEN}✓ Local kubectl context cleaned${NC}"
echo ""

# -------------------------------------------------------------------
# Step 10: Check for remaining resources
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 10: Checking for remaining resources"
echo -e "==========================================${NC}"
echo ""

echo "Checking for managed resource group..."
MC_RG="MC_${RESOURCE_GROUP}_${CLUSTER_NAME}_*"

MC_RESOURCE_GROUPS=$(az group list --query "[?starts_with(name, 'MC_${RESOURCE_GROUP}_${CLUSTER_NAME}')].name" -o tsv 2>/dev/null || echo "")

if [ -n "$MC_RESOURCE_GROUPS" ]; then
    echo -e "${YELLOW}⚠ Found managed resource group(s):${NC}"
    echo "$MC_RESOURCE_GROUPS"
    echo ""
    echo "These will be automatically deleted by Azure when cluster deletion completes."
else
    echo -e "${GREEN}✓ No managed resource groups found${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "✅ Cleanup Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Summary of deleted resources:"
echo "  ✓ JupyterHub Helm release"
echo "  ✓ Namespace: $NAMESPACE"
echo "  ✓ All Persistent Volume Claims"
echo "  ✓ All user data"
echo "  ✓ AKS Cluster: $CLUSTER_NAME (deletion in progress)"
echo "  ✓ Node pools: hubpool, userpool"
echo "  ✓ Local kubectl context"
echo ""

if [ "$WAIT_CONFIRM" != "y" ] && [ "$WAIT_CONFIRM" != "Y" ]; then
    echo "Cluster deletion is running in the background."
    echo ""
    echo "To check deletion status:"
    echo "  az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME"
    echo ""
    echo "To verify all resources are gone:"
    echo "  az aks list --resource-group $RESOURCE_GROUP --output table"
fi

echo "Estimated time for complete deletion: 5-10 minutes"
echo ""
echo -e "${GREEN}=========================================="
echo ""
