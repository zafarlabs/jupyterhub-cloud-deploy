#!/bin/bash

# ===================================================================
# Deploy JupyterHub on AKS
# Step 6: Deploy JupyterHub using Helm
# ===================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -------------------------------------------------------------------
# Check Prerequisites
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Checking Prerequisites"
echo -e "==========================================${NC}"

# Check if config.yaml exists
if [ ! -f "config.yaml" ]; then
    echo -e "${RED}✗ config.yaml not found!${NC}"
    echo "Please create config.yaml in the current directory"
    exit 1
fi
echo -e "${GREEN}✓ config.yaml found${NC}"

# Check if kubectl is configured
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}✗ kubectl is not configured${NC}"
    echo "Please run setup-aks-cluster.sh first"
    exit 1
fi
echo -e "${GREEN}✓ kubectl is configured${NC}"

# Check if helm is installed
if ! command -v helm &>/dev/null; then
    echo -e "${RED}✗ Helm is not installed${NC}"
    echo "Please install Helm first"
    exit 1
fi
echo -e "${GREEN}✓ Helm is installed${NC}"
echo ""

# -------------------------------------------------------------------
# Deploy JupyterHub
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Deploying JupyterHub"
echo -e "==========================================${NC}"
echo ""

# Create namespace if it doesn't exist
echo "Creating namespace 'jupyterhub'..."
kubectl create namespace jupyterhub --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespace ready${NC}"
echo ""

# Deploy JupyterHub
echo "Deploying JupyterHub via Helm..."
echo "This takes 3-5 minutes..."
echo ""

helm upgrade --install jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --values config.yaml \
  --version=4.3.1 \
  --timeout 10m

echo ""
echo -e "${GREEN}✓ JupyterHub deployment initiated${NC}"
echo ""

# -------------------------------------------------------------------
# Wait for Deployment
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Waiting for Pods to be Ready"
echo -e "==========================================${NC}"
echo ""

echo "Waiting for Hub deployment..."
kubectl wait --for=condition=available --timeout=300s deployment/hub -n jupyterhub
echo -e "${GREEN}✓ Hub is ready${NC}"

echo "Waiting for Proxy deployment..."
kubectl wait --for=condition=available --timeout=300s deployment/proxy -n jupyterhub
echo -e "${GREEN}✓ Proxy is ready${NC}"
echo ""

# -------------------------------------------------------------------
# Get External IP
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Getting External IP Address"
echo -e "==========================================${NC}"
echo ""

echo "Waiting for LoadBalancer to assign external IP..."
echo "(This can take 2-5 minutes)"
echo ""

# Wait for external IP with timeout
TIMEOUT=300
ELAPSED=0
EXTERNAL_IP=""

while [ $ELAPSED -lt $TIMEOUT ]; do
    EXTERNAL_IP=$(kubectl get svc proxy-public -n jupyterhub -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    
    if [ -n "$EXTERNAL_IP" ]; then
        break
    fi
    
    echo -n "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo ""
echo ""

if [ -z "$EXTERNAL_IP" ]; then
    echo -e "${YELLOW}⚠ External IP not assigned yet${NC}"
    echo "Check status with: kubectl get svc proxy-public -n jupyterhub"
else
    echo -e "${GREEN}✓ External IP assigned: $EXTERNAL_IP${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Display Status
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "Deployment Status"
echo -e "==========================================${NC}"
echo ""

echo "Pods:"
echo "-------------------------------------------"
kubectl get pods -n jupyterhub
echo ""

echo "Services:"
echo "-------------------------------------------"
kubectl get svc -n jupyterhub
echo ""

echo "Persistent Volume Claims:"
echo "-------------------------------------------"
kubectl get pvc -n jupyterhub
echo ""

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "✅ JupyterHub Deployment Complete!"
echo -e "==========================================${NC}"
echo ""

if [ -n "$EXTERNAL_IP" ]; then
    echo -e "${BLUE}Access JupyterHub at:${NC}"
    echo -e "${GREEN}  http://$EXTERNAL_IP${NC}"
    echo ""
    echo "Initial Setup:"
    echo "  1. Open the URL in your browser"
    echo "  2. Login with username: ${YELLOW}sysadmin${NC}"
    echo "  3. Create a password (minimum 8 characters)"
    echo "  4. Go to: http://$EXTERNAL_IP/hub/admin"
    echo "  5. Authorize and set passwords for:"
    echo "     - user01"
    echo "     - user02"
    echo "     - user03"
else
    echo "To get the external IP, run:"
    echo "  kubectl get svc proxy-public -n jupyterhub"
    echo ""
    echo "Or watch for it:"
    echo "  kubectl get svc proxy-public -n jupyterhub --watch"
fi
echo ""

echo "Useful Commands:"
echo "-------------------------------------------"
echo "Check pods:       kubectl get pods -n jupyterhub"
echo "Check services:   kubectl get svc -n jupyterhub"
echo "Check logs (hub): kubectl logs -n jupyterhub deployment/hub"
echo "Get access URL:   kubectl get svc proxy-public -n jupyterhub"
echo ""

echo -e "${GREEN}=========================================="
echo ""
