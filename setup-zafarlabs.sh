#!/bin/bash

# ===================================================================
# Setup JupyterHub for notebook-fmagf.zafarlabs.com
# ===================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo "JupyterHub Setup for ZafarLabs"
echo "Domain: notebook-fmagf.zafarlabs.com"
echo -e "==========================================${NC}"
echo ""

# Fixed variables
FULL_DOMAIN="notebook-fmagf.zafarlabs.com"
PARENT_DOMAIN="zafarlabs.com"
SUBDOMAIN="notebook-fmagf"
EMAIL="dda@zafarlabs.com"
RESOURCE_GROUP="DDA-Resources-AKS"

echo "Configuration:"
echo "  Full Domain: $FULL_DOMAIN"
echo "  Email: $EMAIL"
echo ""

# Check email
if [ "$EMAIL" == "your-email@zafarlabs.com" ]; then
    echo -e "${RED}Please edit this script and change the EMAIL variable!${NC}"
    exit 1
fi

# -------------------------------------------------------------------
# Step 1: Install cert-manager
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 1: Installing cert-manager"
echo -e "==========================================${NC}"

if kubectl get deployment cert-manager -n cert-manager &>/dev/null; then
    echo -e "${GREEN}✓ cert-manager already installed${NC}"
else
    echo "Installing cert-manager..."
    helm repo add jetstack https://charts.jetstack.io &>/dev/null || true
    helm repo update
    
    kubectl create namespace cert-manager 2>/dev/null || true
    
    helm install cert-manager jetstack/cert-manager \
      --namespace cert-manager \
      --version v1.13.3 \
      --set installCRDs=true
    
    echo "Waiting for cert-manager..."
    kubectl wait --for=condition=available --timeout=300s \
      deployment/cert-manager -n cert-manager
    kubectl wait --for=condition=available --timeout=300s \
      deployment/cert-manager-webhook -n cert-manager
fi

echo -e "${GREEN}✓ cert-manager ready${NC}"
echo ""

# -------------------------------------------------------------------
# Step 2: DNS Setup
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 2: DNS Configuration"
echo -e "==========================================${NC}"

EXTERNAL_IP=$(kubectl get svc proxy-public -n jupyterhub -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -z "$EXTERNAL_IP" ]; then
    echo -e "${RED}Error: Could not get external IP${NC}"
    exit 1
fi

echo "JupyterHub External IP: $EXTERNAL_IP"
echo ""

# Check if parent domain is in Azure DNS
if az network dns zone show --resource-group $RESOURCE_GROUP --name $PARENT_DOMAIN &>/dev/null; then
    echo -e "${GREEN}✓ Found zafarlabs.com in Azure DNS${NC}"
    
    # Delete existing record if any
    az network dns record-set a delete \
      --resource-group $RESOURCE_GROUP \
      --zone-name $PARENT_DOMAIN \
      --name $SUBDOMAIN \
      --yes &>/dev/null || true
    
    # Create A record
    echo "Creating A record: $FULL_DOMAIN → $EXTERNAL_IP"
    az network dns record-set a add-record \
      --resource-group $RESOURCE_GROUP \
      --zone-name $PARENT_DOMAIN \
      --record-set-name $SUBDOMAIN \
      --ipv4-address $EXTERNAL_IP
    
    echo -e "${GREEN}✓ DNS A record created in Azure${NC}"
else
    echo -e "${YELLOW}⚠ zafarlabs.com not found in Azure DNS${NC}"
    echo ""
    echo "Please add this DNS record manually at your DNS provider:"
    echo ""
    echo "  Type: A"
    echo "  Name: $SUBDOMAIN"
    echo "  Value: $EXTERNAL_IP"
    echo "  TTL: 300"
    echo ""
    read -p "Have you added the DNS record? (y/n): " DNS_ADDED
    if [ "$DNS_ADDED" != "y" ]; then
        echo "Please add the DNS record and run this script again."
        exit 1
    fi
fi

echo ""

# -------------------------------------------------------------------
# Step 3: Wait for DNS Propagation
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 3: Verifying DNS"
echo -e "==========================================${NC}"

echo "Testing: $FULL_DOMAIN → $EXTERNAL_IP"

RESOLVED_IP=$(nslookup $FULL_DOMAIN 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')

if [ "$RESOLVED_IP" == "$EXTERNAL_IP" ]; then
    echo -e "${GREEN}✓ DNS is working!${NC}"
else
    echo -e "${YELLOW}⚠ DNS not fully propagated yet${NC}"
    echo "Expected: $EXTERNAL_IP"
    echo "Got: $RESOLVED_IP"
    echo ""
    echo "This is normal and can take 5-60 minutes."
    read -p "Continue anyway? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        exit 0
    fi
fi

echo ""

# -------------------------------------------------------------------
# Step 4: Deploy JupyterHub
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 4: Deploying JupyterHub with HTTPS"
echo -e "==========================================${NC}"

if [ ! -f "config-zafarlabs.yaml" ]; then
    echo -e "${RED}Error: config-zafarlabs.yaml not found!${NC}"
    exit 1
fi

# Update email in config
cp config-zafarlabs.yaml config-zafarlabs.yaml.bak
sed -i.tmp "s|your-email@zafarlabs.com|$EMAIL|g" config-zafarlabs.yaml
rm -f config-zafarlabs.yaml.tmp

echo "Deploying JupyterHub..."
helm upgrade jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --values config-zafarlabs.yaml \
  --version=4.3.1

echo -e "${GREEN}✓ Deployment updated${NC}"
echo ""

# -------------------------------------------------------------------
# Step 5: Wait for Certificate
# -------------------------------------------------------------------
echo -e "${BLUE}=========================================="
echo "Step 5: Waiting for SSL Certificate"
echo -e "==========================================${NC}"

echo "Requesting Let's Encrypt certificate (2-5 minutes)..."
sleep 30

TIMEOUT=300
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    CERT_READY=$(kubectl get certificate -n jupyterhub -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    
    if [ "$CERT_READY" == "True" ]; then
        echo ""
        echo -e "${GREEN}✓ SSL Certificate ready!${NC}"
        break
    fi
    
    echo -n "."
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ "$CERT_READY" != "True" ]; then
    echo ""
    echo -e "${YELLOW}⚠ Certificate still pending${NC}"
    echo "Check: kubectl describe certificate -n jupyterhub"
fi

echo ""

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo -e "${GREEN}=========================================="
echo "✅ Setup Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Access JupyterHub:"
echo -e "  ${GREEN}https://notebook-fmagf.zafarlabs.com${NC}"
echo ""
echo "Login Credentials:"
echo -e "  Username: ${YELLOW}sysadmin${NC}, ${YELLOW}user01${NC}, ${YELLOW}user02${NC}, or ${YELLOW}user03${NC}"
echo -e "  Password: ${YELLOW}test123${NC}"
echo ""
echo "Admin Panel:"
echo -e "  ${GREEN}https://notebook-fmagf.zafarlabs.com/hub/admin${NC}"
echo -e "  (Login as ${YELLOW}sysadmin${NC})"
echo ""
echo "Useful Commands:"
echo "  kubectl get certificate -n jupyterhub"
echo "  kubectl get pods -n jupyterhub"
echo "  nslookup notebook-fmagf.zafarlabs.com"
echo ""
echo -e "${GREEN}=========================================="
