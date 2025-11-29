#!/bin/bash

# ===================================================================
# Production JupyterHub on Google Cloud GKE
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
    "PROJECT_ID"
    "CLUSTER_NAME"
    "REGION"
    "ZONE"
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
# Step 1: Set GCP Project
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 1: Configure GCP Project"
echo -e "==========================================${NC}"

gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE

echo -e "${GREEN}✓ Project configured${NC}"
echo "  Project: $PROJECT_ID"
echo "  Region: $REGION"
echo "  Zone: $ZONE"
echo ""

# -------------------------------------------------------------------
# Step 2: Enable Required APIs
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 2: Enable GCP APIs"
echo -e "==========================================${NC}"

echo "Enabling required APIs..."
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable dns.googleapis.com

echo -e "${GREEN}✓ APIs enabled${NC}"
echo ""

# -------------------------------------------------------------------
# Step 3: Create GKE Cluster
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 3: Create GKE Cluster"
echo -e "==========================================${NC}"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""

if gcloud container clusters describe $CLUSTER_NAME --region=$REGION &>/dev/null; then
    echo -e "${YELLOW}Cluster already exists${NC}"
else
    echo "Creating GKE cluster (takes ~10 minutes)..."
    gcloud container clusters create $CLUSTER_NAME \
      --region $REGION \
      --node-locations $ZONE \
      --machine-type ${HUB_MACHINE_TYPE:-e2-standard-2} \
      --num-nodes 1 \
      --enable-autoscaling \
      --min-nodes 1 \
      --max-nodes 1 \
      --disk-size 50 \
      --enable-autorepair \
      --enable-autoupgrade \
      --workload-pool=${PROJECT_ID}.svc.id.goog \
      --addons HorizontalPodAutoscaling,HttpLoadBalancing \
      --node-labels agentpool=hubpool

    echo -e "${GREEN}✓ Cluster created${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 4: Add User Node Pool
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 4: Add User Node Pool"
echo -e "==========================================${NC}"

if gcloud container node-pools describe userpool --cluster=$CLUSTER_NAME --region=$REGION &>/dev/null; then
    echo -e "${YELLOW}User pool already exists${NC}"
else
    echo "Creating autoscaling user pool..."
    gcloud container node-pools create userpool \
      --cluster $CLUSTER_NAME \
      --region $REGION \
      --machine-type ${USER_MACHINE_TYPE:-e2-standard-4} \
      --enable-autoscaling \
      --min-nodes ${MIN_NODES:-0} \
      --max-nodes ${MAX_NODES:-5} \
      --num-nodes 0 \
      --disk-size 50 \
      --enable-autorepair \
      --enable-autoupgrade \
      --node-labels agentpool=userpool

    echo -e "${GREEN}✓ User pool created${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 5: Configure kubectl
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 5: Configure kubectl"
echo -e "==========================================${NC}"

gcloud container clusters get-credentials $CLUSTER_NAME \
  --region $REGION \
  --project $PROJECT_ID

echo -e "${GREEN}✓ kubectl configured${NC}"
echo ""

# -------------------------------------------------------------------
# Step 6: Install cert-manager for SSL
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 6: Install cert-manager"
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
# Step 7: Create ClusterIssuer for Let's Encrypt
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 7: Configure Let's Encrypt"
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
# Step 8: Install NGINX Ingress Controller
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 8: Install NGINX Ingress"
echo -e "==========================================${NC}"

if kubectl get namespace ingress-nginx &>/dev/null; then
    echo -e "${YELLOW}NGINX ingress already installed${NC}"
else
    echo "Installing NGINX ingress controller..."

    # Install Helm if not present
    if ! command -v helm &>/dev/null; then
        echo "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update

    helm install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx \
      --create-namespace \
      --set controller.service.type=LoadBalancer

    echo "Waiting for ingress controller..."
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=300s

    echo -e "${GREEN}✓ NGINX ingress installed${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 9: Get Ingress IP and Configure DNS
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 9: Get Ingress IP for DNS"
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
echo "Optional: Use Cloud DNS for automatic management"
echo "  gcloud dns record-sets create $DOMAIN. \\"
echo "    --rrdatas=$INGRESS_IP \\"
echo "    --type=A \\"
echo "    --zone=YOUR_ZONE_NAME"
echo ""
echo -e "${YELLOW}Press Enter after configuring DNS...${NC}"
read

# -------------------------------------------------------------------
# Step 10: Setup Helm
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 10: Setup Helm"
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
# Step 11: Deploy JupyterHub
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Step 11: Deploy JupyterHub"
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
echo "  Project: $PROJECT_ID"
echo "  Cluster: $CLUSTER_NAME"
echo "  Region: $REGION"
echo "  Zone: $ZONE"
echo "  Ingress IP: $INGRESS_IP"
echo ""
echo "Node Pools:"
echo "  default: ${HUB_MACHINE_TYPE:-e2-standard-2} (1 node)"
echo "  userpool: ${USER_MACHINE_TYPE:-e2-standard-4} (${MIN_NODES:-0}-${MAX_NODES:-5} nodes)"
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
echo "  gcloud container clusters list"
echo ""
echo -e "${GREEN}=========================================="
echo ""
