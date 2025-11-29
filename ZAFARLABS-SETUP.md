# JupyterHub Setup Guide for ZafarLabs
## Domain: notebook-fmagf.zafarlabs.com

## Quick Start

### Option 1: Automated (Recommended)

```bash
# 1. Download files
# - config-zafarlabs.yaml
# - setup-zafarlabs.sh

# 2. Edit setup-zafarlabs.sh
nano setup-zafarlabs.sh

# Change this line:
EMAIL="your-email@zafarlabs.com"  # Your actual email

# 3. Make executable and run
chmod +x setup-zafarlabs.sh
./setup-zafarlabs.sh
```

### Option 2: Manual Steps

#### Step 1: Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

kubectl create namespace cert-manager

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.13.3 \
  --set installCRDs=true
```

#### Step 2: Setup DNS

**Get your external IP:**
```bash
kubectl get svc proxy-public -n jupyterhub -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# Output: 20.174.211.170
```

**Two scenarios:**

**A. If zafarlabs.com is in Azure DNS:**
```bash
az network dns record-set a add-record \
  --resource-group DDA-Resources-AKS \
  --zone-name zafarlabs.com \
  --record-set-name notebook-fmagf \
  --ipv4-address 20.174.211.170
```

**B. If zafarlabs.com is managed elsewhere:**

Go to your DNS provider and add:
- Type: `A`
- Name: `notebook-fmagf`
- Value: `20.174.211.170`
- TTL: `300`

#### Step 3: Verify DNS

```bash
nslookup notebook-fmagf.zafarlabs.com
# Should return: 20.174.211.170
```

Wait 5-60 minutes if it doesn't resolve yet.

#### Step 4: Update Config

Edit `config-zafarlabs.yaml`:
```yaml
letsencrypt:
  contactEmail: your-email@zafarlabs.com  # Change this
```

#### Step 5: Deploy

```bash
helm upgrade jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --values config-zafarlabs.yaml \
  --version=4.3.1
```

#### Step 6: Wait for Certificate

```bash
kubectl get certificate -n jupyterhub -w
# Wait until READY = True (2-5 minutes)
```

## Access JupyterHub

**URL:** https://notebook-fmagf.zafarlabs.com

**Login:**
- Username: `sysadmin`, `user01`, `user02`, or `user03`
- Password: `test123` (same for all)

**Admin Panel:**
- https://notebook-fmagf.zafarlabs.com/hub/admin
- Login as `sysadmin`

## Verification

```bash
# Check DNS
nslookup notebook-fmagf.zafarlabs.com

# Check certificate
kubectl get certificate -n jupyterhub

# Check pods
kubectl get pods -n jupyterhub

# Test HTTPS
curl -I https://notebook-fmagf.zafarlabs.com
```

## Architecture Summary

```
Domain: notebook-fmagf.zafarlabs.com
   ↓
Load Balancer: 20.174.211.170
   ↓
Proxy (hubpool)
   ↓
Hub (hubpool)
   ↓
User Pods (userpool - autoscaling 0-3)
```

## Features

✅ **Domain:** notebook-fmagf.zafarlabs.com  
✅ **HTTPS:** Let's Encrypt SSL  
✅ **Auth:** Dummy (test123 for all)  
✅ **Users:** sysadmin, user01-03  
✅ **Autoscaling:** 0-3 nodes  
✅ **Storage:** 50GB per user  
✅ **Culling:** 1 hour idle  

## Testing

### Test User Login
```bash
# Window 1: sysadmin
https://notebook-fmagf.zafarlabs.com
Username: sysadmin
Password: test123

# Window 2: user01 (incognito)
Username: user01
Password: test123

# Window 3: user02 (another incognito)
Username: user02
Password: test123
```

### Check Autoscaling
```bash
# Watch nodes scale
kubectl get nodes -L agentpool -w

# Should see:
# hubpool: 1 node (always)
# userpool: 0 → 1 → 2 nodes (as users login)
```

## Troubleshooting

### Certificate Pending
```bash
kubectl describe certificate -n jupyterhub
kubectl logs -n cert-manager deployment/cert-manager
```

**Common issues:**
- DNS not propagated (wait 5-60 min)
- Port 80/443 blocked
- Wrong email format

### DNS Not Resolving
```bash
# Check DNS
nslookup notebook-fmagf.zafarlabs.com

# Check Azure DNS
az network dns record-set a list \
  --resource-group DDA-Resources-AKS \
  --zone-name zafarlabs.com
```

### Can't Login
- Password must be exactly: `test123`
- Username must be one of: sysadmin, user01, user02, user03
- Clear browser cache

## Files

- **config-zafarlabs.yaml** - JupyterHub configuration
- **setup-zafarlabs.sh** - Automated setup script
- **ZAFARLABS-SETUP.md** - This guide

## Support

**Check logs:**
```bash
kubectl logs -n jupyterhub deployment/hub
kubectl logs -n jupyterhub deployment/proxy
kubectl logs -n cert-manager deployment/cert-manager
```

**Get status:**
```bash
kubectl get all -n jupyterhub
kubectl get certificate -n jupyterhub
kubectl get nodes -L agentpool
```
