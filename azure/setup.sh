#!/bin/bash

# ===================================================================
# Production JupyterHub on Azure AKS
# Complete setup with domain and HTTPS support
# ===================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load environment variables
if [ ! -f ".env" ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please create .env file from .env.template"
    exit 1
fi

source .env

# Validate required variables
REQUIRED_VARS=(
    "RESOURCE_GROUP"
    "CLUSTER_NAME"
    "LOCATION"
    "DOMAIN"
    "EMAIL"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: $var is not set in .env${NC}"
        exit 1
    fi
done

# -------------------------------------------------------------------
# Step 1: Create Resource Group
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 1: Create Resource Group"
echo -e "==========================================${NC}"

if az group show --name $RESOURCE_GROUP &>/dev/null; then
    echo -e "${YELLOW}Resource group '$RESOURCE_GROUP' already exists${NC}"
else
    echo "Creating resource group..."
    az group create --name $RESOURCE_GROUP --location $LOCATION
    echo -e "${GREEN}✓ Resource group created${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 2: Create AKS Cluster
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 2: Create AKS Cluster"
echo -e "==========================================${NC}"
echo "Cluster: $CLUSTER_NAME"
echo "Location: $LOCATION"
echo ""

if az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME &>/dev/null; then
    echo -e "${YELLOW}Cluster already exists${NC}"
else
    echo "Creating AKS cluster (takes ~10 minutes)..."
    az aks create \
      --resource-group $RESOURCE_GROUP \
      --name $CLUSTER_NAME \
      --location $LOCATION \
      --nodepool-name hubpool \
      --node-count 1 \
      --node-vm-size ${HUB_VM_SIZE:-Standard_D2s_v3} \
      --network-plugin azure \
      --enable-managed-identity \
      --generate-ssh-keys

    echo -e "${GREEN}✓ Cluster created${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 3: Add User Node Pool
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 3: Add User Node Pool"
echo -e "==========================================${NC}"

if az aks nodepool show --cluster-name $CLUSTER_NAME --resource-group $RESOURCE_GROUP --name userpool &>/dev/null; then
    echo -e "${YELLOW}User pool already exists${NC}"
else
    echo "Creating autoscaling user pool..."
    az aks nodepool add \
      --cluster-name $CLUSTER_NAME \
      --resource-group $RESOURCE_GROUP \
      --name userpool \
      --node-vm-size ${USER_VM_SIZE:-Standard_D4s_v3} \
      --enable-cluster-autoscaler \
      --min-count ${MIN_NODES:-0} \
      --max-count ${MAX_NODES:-5} \
      --node-count 0 \
      --mode User

    echo -e "${GREEN}✓ User pool created${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 4: Configure kubectl
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 4: Configure kubectl"
echo -e "==========================================${NC}"

az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --overwrite-existing

echo -e "${GREEN}✓ kubectl configured${NC}"
echo ""

# -------------------------------------------------------------------
# Step 5: Install cert-manager for SSL
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 5: Install cert-manager"
echo -e "==========================================${NC}"

if kubectl get namespace cert-manager &>/dev/null; then
    echo -e "${YELLOW}cert-manager already installed${NC}"
else
    echo "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

    echo "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager

    echo -e "${GREEN}✓ cert-manager installed${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 6: Create ClusterIssuer for Let's Encrypt
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 6: Configure Let's Encrypt"
echo -e "==========================================${NC}"

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

echo -e "${GREEN}✓ ClusterIssuer created${NC}"
echo ""

# -------------------------------------------------------------------
# Step 7: Install NGINX Ingress Controller
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 7: Install NGINX Ingress"
echo -e "==========================================${NC}"

if kubectl get namespace ingress-nginx &>/dev/null; then
    echo -e "${YELLOW}NGINX ingress already installed${NC}"
else
    echo "Installing NGINX ingress controller..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update

    helm install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx \
      --create-namespace \
      --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

    echo "Waiting for ingress controller..."
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=300s

    echo -e "${GREEN}✓ NGINX ingress installed${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 8: Get Ingress IP and Configure DNS
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 8: Get Ingress IP for DNS"
echo -e "==========================================${NC}"

echo "Waiting for LoadBalancer IP..."
INGRESS_IP=""
TIMEOUT=300
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

    if [ -n "$INGRESS_IP" ]; then
        break
    fi

    echo -n "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo ""

if [ -z "$INGRESS_IP" ]; then
    echo -e "${RED}Failed to get ingress IP${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Ingress IP: $INGRESS_IP${NC}"
echo ""
echo -e "${YELLOW}=========================================="
echo "DNS CONFIGURATION REQUIRED"
echo -e "==========================================${NC}"
echo ""
echo "Please create an A record in your DNS provider:"
echo "  Domain: $DOMAIN"
echo "  Type: A"
echo "  Value: $INGRESS_IP"
echo ""
echo -e "${YELLOW}Press Enter after configuring DNS...${NC}"
read

# -------------------------------------------------------------------
# Step 9: Setup Helm
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 9: Setup Helm"
echo -e "==========================================${NC}"

if ! command -v helm &>/dev/null; then
    echo "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update

echo -e "${GREEN}✓ Helm configured${NC}"
echo ""

# -------------------------------------------------------------------
# Step 10: Deploy JupyterHub
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 10: Deploy JupyterHub"
echo -e "==========================================${NC}"

# Generate secure random token for proxy
if [ -z "$PROXY_SECRET_TOKEN" ]; then
    PROXY_SECRET_TOKEN=$(openssl rand -hex 32)
    echo "PROXY_SECRET_TOKEN=$PROXY_SECRET_TOKEN" >> .env
fi

# Create namespace
kubectl create namespace jupyterhub --dry-run=client -o yaml | kubectl apply -f -

# Deploy JupyterHub
echo "Deploying JupyterHub..."
helm upgrade --install jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --values config.yaml \
  --set proxy.secretToken=$PROXY_SECRET_TOKEN \
  --set ingress.hosts[0]=$DOMAIN \
  --set ingress.tls[0].hosts[0]=$DOMAIN \
  --set ingress.tls[0].secretName=jupyterhub-tls \
  --version=4.3.1 \
  --timeout 10m

echo ""
echo "Waiting for deployment..."
kubectl wait --for=condition=available --timeout=300s deployment/hub -n jupyterhub
kubectl wait --for=condition=available --timeout=300s deployment/proxy -n jupyterhub

echo -e "${GREEN}✓ JupyterHub deployed${NC}"
echo ""

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "✅ DEPLOYMENT COMPLETE"
echo -e "==========================================${NC}"
echo ""
echo -e "${BLUE}JupyterHub URL:${NC}"
echo -e "${GREEN}  https://$DOMAIN${NC}"
echo ""
echo "Cluster Info:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Cluster: $CLUSTER_NAME"
echo "  Location: $LOCATION"
echo "  Ingress IP: $INGRESS_IP"
echo ""
echo "Node Pools:"
echo "  hubpool: ${HUB_VM_SIZE:-Standard_D2s_v3} (1 node)"
echo "  userpool: ${USER_VM_SIZE:-Standard_D4s_v3} (${MIN_NODES:-0}-${MAX_NODES:-5} nodes)"
echo ""
echo "Next Steps:"
echo "  1. Visit https://$DOMAIN"
echo "  2. Login as admin (check config.yaml for credentials)"
echo "  3. Configure users and notebooks"
echo ""
echo "Useful Commands:"
echo "  kubectl get pods -n jupyterhub"
echo "  kubectl get svc -n jupyterhub"
echo "  kubectl logs -n jupyterhub deployment/hub"
echo ""
echo -e "${GREEN}=========================================="
echo ""
