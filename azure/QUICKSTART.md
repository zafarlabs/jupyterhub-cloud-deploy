# Quick Start - Azure JupyterHub

Get JupyterHub running on Azure in ~20 minutes.

## Prerequisites Checklist

- [ ] Azure subscription with access
- [ ] Domain name (e.g., jupyter.yourdomain.com)
- [ ] Can create DNS A records
- [ ] Azure CLI installed and logged in

## Step-by-Step Setup

### 1. Login to Azure (2 min)

```bash
az login
az account set --subscription "YOUR_SUBSCRIPTION_NAME"
```

### 2. Configure Environment (3 min)

```bash
cd azure
cp .env.template .env
nano .env  # or use any editor
```

Fill in these values:
```bash
RESOURCE_GROUP="jupyterhub-prod"           # Your resource group name
CLUSTER_NAME="jupyterhub-cluster"          # Your cluster name
LOCATION="eastus"                          # Azure region
DOMAIN="jupyter.yourdomain.com"            # Your domain
EMAIL="admin@yourdomain.com"               # Your email for SSL
```

Save and exit.

### 3. Run Setup Script (10 min)

```bash
chmod +x setup.sh
./setup.sh
```

The script will:
- ✅ Create Azure resources
- ✅ Install Kubernetes cluster
- ✅ Configure SSL/HTTPS
- ✅ Install JupyterHub
- ⏸️  **Pause for DNS configuration**

### 4. Configure DNS (2 min)

When the script pauses, it will show:

```
DNS CONFIGURATION REQUIRED
==========================================

Please create an A record in your DNS provider:
  Domain: jupyter.yourdomain.com
  Type: A
  Value: 20.123.45.67

Press Enter after configuring DNS...
```

Go to your DNS provider and create this A record, then press Enter.

### 5. Wait for SSL Certificate (3 min)

The script will continue and deploy JupyterHub. SSL certificate from Let's Encrypt will be automatically issued.

### 6. Access JupyterHub

When complete, you'll see:

```
✅ DEPLOYMENT COMPLETE
==========================================

JupyterHub URL:
  https://jupyter.yourdomain.com
```

Visit the URL and login:
- Username: `admin`
- Password: Create one (min 12 characters)

## That's It! 🎉

You now have a production JupyterHub running with:
- ✅ HTTPS with valid SSL certificate
- ✅ Custom domain
- ✅ Auto-scaling
- ✅ Cost optimization

## Next Steps

### Add Users

Edit [config.yaml](config.yaml):

```yaml
Authenticator:
  allowed_users:
    - admin
    - alice
    - bob
    - charlie
```

Then update:

```bash
helm upgrade jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --values config.yaml \
  --reuse-values
```

### Check Status

```bash
# See all resources
kubectl get all -n jupyterhub

# Check nodes (see auto-scaling)
kubectl get nodes -L agentpool

# View hub logs
kubectl logs -n jupyterhub deployment/hub
```

### Customize Resources

Edit [config.yaml](config.yaml) to change:
- User CPU/memory limits
- Storage size
- Cull timeout
- Jupyter image

## Troubleshooting

### "DNS not configured"
Wait 5-10 minutes for DNS to propagate globally.

### "SSL certificate pending"
Check status:
```bash
kubectl get certificate -n jupyterhub
kubectl describe certificate jupyterhub-tls -n jupyterhub
```

### "Can't access domain"
Verify DNS:
```bash
nslookup jupyter.yourdomain.com
# Should return the ingress IP
```

## Cleanup

To delete everything:

```bash
./cleanup.sh
# Choose option 3 (delete everything)
```

## Cost

- **Minimal load**: ~$70-100/month
- **Active users**: ~$180-250/month
- **Scales with usage**

The cluster scales down to minimal cost when not in use!

## Need Help?

See full documentation: [README.md](README.md)
