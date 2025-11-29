#!/bin/bash

# ===================================================================
# AKS Cluster Setup for JupyterHub
# Steps 1-5: Create cluster and node pools
# ===================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# -------------------------------------------------------------------
# Step 1: Set Variables
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 1: Setting Variables"
echo -e "==========================================${NC}"

RESOURCE_GROUP="DDA-Resources-AKS"
CLUSTER_NAME="jhub-cluster"
LOCATION="uaenorth"

echo "Resource Group: $RESOURCE_GROUP"
echo "Cluster Name: $CLUSTER_NAME"
echo "Location: $LOCATION"
echo ""

# Check if resource group exists
echo "Checking if resource group exists..."
if az group show --name $RESOURCE_GROUP &>/dev/null; then
    echo -e "${GREEN}✓ Resource group '$RESOURCE_GROUP' exists${NC}"
else
    echo -e "${RED}✗ Resource group '$RESOURCE_GROUP' does not exist${NC}"
    echo "Creating resource group..."
    az group create --name $RESOURCE_GROUP --location $LOCATION
    echo -e "${GREEN}✓ Resource group created${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 2: Create AKS Cluster with Hub Node Pool
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 2: Creating AKS Cluster"
echo -e "==========================================${NC}"
echo "This will create a cluster with 1 node pool (hubpool)"
echo "VM Size: Standard_D2s_v3 (2 vCPU, 8GB RAM)"
echo ""

# Check if cluster already exists
if az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME &>/dev/null; then
    echo -e "${YELLOW}⚠ Cluster '$CLUSTER_NAME' already exists${NC}"
    echo "Skipping cluster creation..."
else
    echo "Creating cluster... (this takes 5-10 minutes)"
    az aks create \
      --resource-group $RESOURCE_GROUP \
      --name $CLUSTER_NAME \
      --location $LOCATION \
      --nodepool-name hubpool \
      --node-count 1 \
      --node-vm-size Standard_D2s_v3 \
      --network-plugin azure \
      --generate-ssh-keys \
      --enable-managed-identity
    
    echo -e "${GREEN}✓ Cluster created successfully${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 3: Add Autoscaling User Node Pool
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 3: Adding Autoscaling User Pool"
echo -e "==========================================${NC}"
echo "This will create an autoscaling node pool (userpool)"
echo "VM Size: Standard_D4s_v3 (4 vCPU, 16GB RAM)"
echo "Autoscaling: 0-3 nodes"
echo ""

# Check if userpool already exists
if az aks nodepool show --cluster-name $CLUSTER_NAME --resource-group $RESOURCE_GROUP --name userpool &>/dev/null; then
    echo -e "${YELLOW}⚠ Node pool 'userpool' already exists${NC}"
    echo "Skipping node pool creation..."
else
    echo "Creating user pool... (this takes 3-5 minutes)"
    az aks nodepool add \
      --cluster-name $CLUSTER_NAME \
      --resource-group $RESOURCE_GROUP \
      --name userpool \
      --node-vm-size Standard_D4s_v3 \
      --enable-cluster-autoscaler \
      --min-count 0 \
      --max-count 3 \
      --node-count 0 \
      --mode User
    
    echo -e "${GREEN}✓ User pool created successfully${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 4: Get Cluster Credentials
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 4: Getting Cluster Credentials"
echo -e "==========================================${NC}"
echo "Configuring kubectl to connect to the cluster..."
echo ""

az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --overwrite-existing

echo -e "${GREEN}✓ Credentials configured${NC}"
echo ""

# -------------------------------------------------------------------
# Step 5: Verify Node Pools and Setup
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 5: Verifying Setup"
echo -e "==========================================${NC}"
echo ""

echo "Node Pools:"
echo "-------------------------------------------"
az aks nodepool list \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --output table
echo ""

echo "Kubernetes Nodes:"
echo "-------------------------------------------"
kubectl get nodes -L agentpool
echo ""

echo "Checking node pool autoscaling settings:"
echo "-------------------------------------------"
az aks nodepool show \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --name userpool \
  --query "{name:name, vmSize:vmSize, count:count, minCount:minCount, maxCount:maxCount, enableAutoScaling:enableAutoScaling}" \
  --output table
echo ""

# -------------------------------------------------------------------
# Step 6: Install/Verify Helm
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 6: Checking Helm Installation"
echo -e "==========================================${NC}"
echo ""

if command -v helm &>/dev/null; then
    HELM_VERSION=$(helm version --short)
    echo -e "${GREEN}✓ Helm is installed: $HELM_VERSION${NC}"
else
    echo -e "${YELLOW}⚠ Helm is not installed${NC}"
    echo "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo -e "${GREEN}✓ Helm installed${NC}"
fi
echo ""

echo "Adding JupyterHub Helm repository..."
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/ 2>/dev/null || echo "Repository already exists"
helm repo update
echo -e "${GREEN}✓ Helm repository updated${NC}"
echo ""

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "✅ AKS Cluster Setup Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Cluster Information:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Location: $LOCATION"
echo ""
echo "Node Pools:"
echo "  1. hubpool (Standard_D2s_v3, 1 node) - For Hub/Proxy"
echo "  2. userpool (Standard_D4s_v3, 0-3 nodes) - For Users"
echo ""
echo "Next Steps:"
echo "  1. Create config.yaml file"
echo "  2. Run: helm upgrade --install jupyterhub jupyterhub/jupyterhub \\"
echo "          --namespace jupyterhub \\"
echo "          --create-namespace \\"
echo "          --values config.yaml \\"
echo "          --version=4.3.1"
echo ""
echo -e "${GREEN}=========================================="
echo ""
