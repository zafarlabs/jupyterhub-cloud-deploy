# Quick Start - Google Cloud JupyterHub

Get JupyterHub running on GKE in ~20 minutes.

## Prerequisites Checklist

- [ ] Google Cloud account with billing enabled
- [ ] Domain name (e.g., jupyter.yourdomain.com)
- [ ] Can create DNS A records
- [ ] gcloud CLI installed and logged in

## Step-by-Step Setup

### 1. Login to Google Cloud (2 min)

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

If you don't have a project:
```bash
gcloud projects create my-jupyterhub-project
gcloud config set project my-jupyterhub-project

# Link billing account
gcloud billing accounts list
gcloud billing projects link my-jupyterhub-project \
  --billing-account=BILLING_ACCOUNT_ID
```

### 2. Configure Environment (3 min)

```bash
cd gcp
cp .env.template .env
nano .env  # or use any editor
```

Fill in these values:
```bash
PROJECT_ID="my-gcp-project"                # Your project ID
CLUSTER_NAME="jupyterhub-cluster"          # Cluster name
REGION="us-central1"                       # GCP region
ZONE="us-central1-a"                       # GCP zone
DOMAIN="jupyter.yourdomain.com"            # Your domain
EMAIL="admin@yourdomain.com"               # Your email for SSL
```

Save and exit.

### 3. Run Setup Script (12 min)

```bash
chmod +x setup.sh
./setup.sh
```

The script will:
- ✅ Enable GCP APIs
- ✅ Create GKE cluster
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
  Value: 34.123.45.67

Press Enter after configuring DNS...
```

Go to your DNS provider and create this A record, then press Enter.

**Optional - Use Cloud DNS:**
```bash
# Create managed zone (one time)
gcloud dns managed-zones create jupyterhub \
  --dns-name="yourdomain.com." \
  --description="JupyterHub"

# Add A record
gcloud dns record-sets create jupyter.yourdomain.com. \
  --rrdatas=34.123.45.67 \
  --type=A \
  --zone=jupyterhub
```

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

# Check cluster info
gcloud container clusters describe jupyterhub-cluster --region=us-central1
```

### Customize Resources

Edit [config.yaml](config.yaml) to change:
- User CPU/memory limits
- Storage size
- Cull timeout
- Jupyter image

## Troubleshooting

### "API not enabled"
The script enables APIs automatically. If manual enable needed:
```bash
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
```

### "Insufficient quota"
Request quota increase at:
https://console.cloud.google.com/iam-admin/quotas

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

Check firewall:
```bash
gcloud compute firewall-rules list
```

## Cleanup

To delete everything:

```bash
./cleanup.sh
# Choose option 2 (delete cluster)
```

This removes all resources and stops billing.

## Cost Optimization

### Use Preemptible Nodes (Save 50-80%)

Edit `setup.sh` user pool creation to add:
```bash
--preemptible \
```

**Note**: Preemptible nodes can be interrupted, but JupyterHub will reschedule user pods automatically.

### Adjust Auto-scaling

For dev/testing, reduce max nodes in `.env`:
```bash
MAX_NODES=2
```

### Aggressive Culling

For cost savings, edit [config.yaml](config.yaml):
```yaml
cull:
  timeout: 1800  # 30 minutes instead of 1 hour
```

## Cost Estimate

With default settings:

- **Minimal load** (no active users): ~$50/month
- **Light usage** (1-2 users, 4h/day): ~$120/month
- **Active usage** (3-5 users, 8h/day): ~$193/month

With preemptible nodes:
- **Light usage**: ~$70/month
- **Active usage**: ~$100/month

The cluster scales to near-zero cost when not in use!

## Regional Pricing

Costs vary by region. Cheaper regions:
- `us-central1` (Iowa) - Standard pricing
- `us-east1` (South Carolina) - Standard pricing
- `europe-west4` (Netherlands) - +10%
- `asia-northeast1` (Tokyo) - +20%

## Need Help?

See full documentation: [README.md](README.md)

## Useful GCP Commands

```bash
# List clusters
gcloud container clusters list

# Get cluster credentials
gcloud container clusters get-credentials jupyterhub-cluster --region=us-central1

# View cluster details
gcloud container clusters describe jupyterhub-cluster --region=us-central1

# SSH to node
gcloud compute ssh NODE_NAME --zone=us-central1-a

# View logs in Cloud Console
gcloud console https://console.cloud.google.com/logs

# Check billing
gcloud billing accounts list
gcloud billing projects describe PROJECT_ID
```
