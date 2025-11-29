# Production JupyterHub on Google Cloud GKE

Production-grade JupyterHub deployment on Google Kubernetes Engine (GKE) with custom domain, HTTPS, and autoscaling.

## Features

- **Production-ready**: HTTPS with Let's Encrypt SSL certificates
- **Custom domain**: Your own domain name (e.g., jupyter.yourdomain.com)
- **Auto-scaling**: Scales from 0 to multiple nodes based on demand
- **Cost-optimized**: Automatically culls idle notebooks and scales down nodes
- **Secure**: Native authentication with strong password requirements
- **Persistent storage**: User data persists across sessions
- **Separated workloads**: Hub and user notebooks run on different node pools

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Google Cloud GKE Cluster                            │
├─────────────────────────────────────────────────────┤
│                                                     │
│ Default Pool (hubpool)                              │
│ ├─ 1x e2-standard-2 (2 vCPU, 8GB)                 │
│ ├─ JupyterHub Hub                                  │
│ ├─ Proxy                                           │
│ ├─ NGINX Ingress Controller                        │
│ └─ cert-manager                                    │
│                                                     │
│ User Pool (userpool)                               │
│ ├─ 0-5x e2-standard-4 (4 vCPU, 16GB)             │
│ ├─ Auto-scales based on demand                    │
│ └─ User Jupyter notebooks                         │
│                                                     │
└─────────────────────────────────────────────────────┘
         ↓
    NGINX Ingress
         ↓
    Let's Encrypt SSL
         ↓
    https://jupyter.yourdomain.com
```

## Prerequisites

1. **Google Cloud SDK** installed and logged in
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **kubectl** installed
   ```bash
   gcloud components install kubectl
   ```

3. **Helm 3** installed (or script will install it)
   ```bash
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```

4. **Domain name** with ability to create DNS A records

5. **GCP APIs enabled** (script will enable automatically):
   - Kubernetes Engine API
   - Compute Engine API
   - Cloud DNS API (optional)

## Quick Start

### 1. Configure Environment

Copy the template and fill in your values:

```bash
cd gcp
cp .env.template .env
nano .env
```

Required values:
```bash
PROJECT_ID="my-gcp-project"              # Your GCP project ID
CLUSTER_NAME="jupyterhub-cluster"        # Cluster name
REGION="us-central1"                     # GCP region
ZONE="us-central1-a"                     # GCP zone
DOMAIN="jupyter.yourdomain.com"          # Your domain
EMAIL="admin@yourdomain.com"             # For SSL certificates
```

### 2. Run Setup

```bash
chmod +x setup.sh
./setup.sh
```

The script will:
1. Configure GCP project and enable APIs
2. Create GKE cluster with node pools
3. Install cert-manager for SSL
4. Install NGINX ingress controller
5. Configure Let's Encrypt
6. Deploy JupyterHub
7. Wait for you to configure DNS

**Important**: When prompted, create a DNS A record pointing your domain to the displayed IP address.

### 3. Access JupyterHub

Once DNS is configured and SSL certificate is issued (takes 2-5 minutes):

```
https://jupyter.yourdomain.com
```

**First login:**
- Username: `admin`
- Password: Create one (minimum 12 characters)

### 4. Add Users

Edit [config.yaml](config.yaml#L16-L21):

```yaml
Authenticator:
  admin_users:
    - admin
  allowed_users:
    - admin
    - user01
    - user02
    - yourteam
```

Then update the deployment:

```bash
helm upgrade jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --values config.yaml \
  --reuse-values
```

## File Structure

```
gcp/
├── README.md           # This file
├── .env.template       # Environment configuration template
├── config.yaml         # JupyterHub configuration
├── setup.sh           # Complete deployment script
└── cleanup.sh         # Resource cleanup script
```

## Configuration

### Node Pools

Customize machine types and scaling in `.env`:

```bash
# Hub pool (always-on, runs core services)
HUB_MACHINE_TYPE="e2-standard-2"

# User pool (auto-scales, runs user notebooks)
USER_MACHINE_TYPE="e2-standard-4"
MIN_NODES=0
MAX_NODES=5
```

### GCP Machine Types

Common machine types:
- `e2-standard-2`: 2 vCPU, 8 GB RAM (~$50/month)
- `e2-standard-4`: 4 vCPU, 16 GB RAM (~$100/month)
- `n2-standard-2`: 2 vCPU, 8 GB RAM (~$70/month, better performance)
- `n2-standard-4`: 4 vCPU, 16 GB RAM (~$140/month, better performance)

### Resource Limits

Per-user resources in [config.yaml](config.yaml#L113-L120):

```yaml
singleuser:
  cpu:
    limit: 4
    guarantee: 1
  memory:
    limit: 8G
    guarantee: 2G
```

### Culling (Cost Optimization)

Auto-shutdown idle notebooks in [config.yaml](config.yaml#L154-L161):

```yaml
cull:
  enabled: true
  timeout: 3600        # Shutdown after 1 hour of inactivity
  every: 600           # Check every 10 minutes
```

### Authentication

Configure users in [config.yaml](config.yaml#L13-L21):

```yaml
Authenticator:
  admin_users:
    - admin
  allowed_users:
    - admin
    - user01
    - user02
```

Password requirements:
- Minimum 12 characters
- Checks against common passwords
- Max 3 failed attempts
- 10-minute lockout after failures

## Operations

### Check Status

```bash
# All resources
kubectl get all -n jupyterhub

# Pods
kubectl get pods -n jupyterhub

# Nodes (see scaling)
kubectl get nodes -L agentpool

# Ingress IP
kubectl get svc -n ingress-nginx

# SSL certificate status
kubectl get certificate -n jupyterhub

# Cluster info
gcloud container clusters describe $CLUSTER_NAME --region=$REGION
```

### View Logs

```bash
# Hub logs
kubectl logs -n jupyterhub deployment/hub

# Proxy logs
kubectl logs -n jupyterhub deployment/proxy

# Ingress logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# User notebook logs
kubectl logs -n jupyterhub jupyter-<username>

# GKE cluster events
gcloud logging read "resource.type=k8s_cluster" --limit 50
```

### Update Configuration

After modifying `config.yaml`:

```bash
helm upgrade jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --values config.yaml \
  --reuse-values
```

### Scale User Pool

Manually adjust scaling:

```bash
gcloud container clusters update $CLUSTER_NAME \
  --enable-autoscaling \
  --min-nodes 0 \
  --max-nodes 10 \
  --node-pool userpool \
  --region $REGION
```

## Costs

Estimated monthly costs (US Central):

| Component | Type | Hours | Cost/Month |
|-----------|------|-------|------------|
| Hub Pool | e2-standard-2 (1 node) | 730 | ~$50 |
| User Pool | e2-standard-4 (avg 2 nodes, 8h/day) | 480 | ~$100 |
| Storage | 50GB per user (3 users) | 730 | ~$15 |
| Ingress | Load Balancer | 730 | ~$18 |
| Network | Egress (estimated) | - | ~$10 |
| **Total** | | | **~$193/month** |

**Cost optimization tips:**
- Culling reduces user pool to 0 nodes when idle
- Use preemptible VMs for user pool (50-80% cheaper)
- Adjust `MAX_NODES` based on actual usage
- Use Cloud DNS for automatic domain management
- Set aggressive cull timeout for dev environments
- Use committed use discounts for long-term deployments

### Use Preemptible Nodes (Save 50-80%)

Add to user pool in setup.sh:
```bash
gcloud container node-pools create userpool \
  --preemptible \
  # ... other flags
```

## Cleanup

Two cleanup levels:

### 1. Delete Only JupyterHub
Keeps cluster, removes application:
```bash
./cleanup.sh
# Choose option 1
```
Cost: ~$50/month (hub pool still running)

### 2. Delete Cluster
Removes everything:
```bash
./cleanup.sh
# Choose option 2
```
Cost: $0

## Troubleshooting

### SSL Certificate Not Issued

Check certificate status:
```bash
kubectl describe certificate jupyterhub-tls -n jupyterhub
kubectl get challenges -n jupyterhub
```

Common issues:
- DNS not propagated yet (wait 5-10 minutes)
- DNS pointing to wrong IP
- Firewall blocking HTTP validation

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n jupyterhub

# Describe pod
kubectl describe pod <pod-name> -n jupyterhub

# Check events
kubectl get events -n jupyterhub --sort-by='.lastTimestamp'
```

### User Pods Pending

```bash
# Check if nodes are scaling
kubectl get nodes -L agentpool -w

# Check node pool status
gcloud container node-pools describe userpool \
  --cluster=$CLUSTER_NAME \
  --region=$REGION

# Check pod events
kubectl describe pod jupyter-<username> -n jupyterhub
```

### Cannot Access Domain

1. Verify DNS:
   ```bash
   nslookup jupyter.yourdomain.com
   ```

2. Check ingress IP:
   ```bash
   kubectl get svc -n ingress-nginx
   ```

3. Verify ingress:
   ```bash
   kubectl get ingress -n jupyterhub
   ```

4. Check NGINX logs:
   ```bash
   kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
   ```

### Quota Errors

If you hit GCP quotas:
```bash
# Check quotas
gcloud compute project-info describe --project=$PROJECT_ID

# Request quota increase
# Go to: https://console.cloud.google.com/iam-admin/quotas
```

## Security Best Practices

1. **Use strong passwords**: Minimum 12 characters enforced
2. **Keep images updated**: Regularly update Jupyter image tags in config.yaml
3. **Limit user access**: Only add necessary users to `allowed_users`
4. **Monitor access**: Review hub logs regularly
5. **Backup data**: Use persistent disk snapshots
6. **Network policies**: Consider adding Kubernetes network policies
7. **Private cluster**: For sensitive workloads, use private GKE cluster
8. **Workload Identity**: Use GCP Workload Identity for secure service access
9. **VPC-native**: Use VPC-native cluster (enabled by default)

## Advanced Configuration

### Cloud DNS Integration

Automatically manage DNS:

```bash
# Create DNS zone
gcloud dns managed-zones create jupyterhub-zone \
  --dns-name="yourdomain.com." \
  --description="JupyterHub DNS"

# Add A record
gcloud dns record-sets create jupyter.yourdomain.com. \
  --rrdatas=$INGRESS_IP \
  --type=A \
  --zone=jupyterhub-zone
```

### Custom Jupyter Images

In [config.yaml](config.yaml#L104-L106):

```yaml
singleuser:
  image:
    name: gcr.io/YOUR_PROJECT/custom-jupyter
    tag: "latest"
```

Build and push:
```bash
docker build -t gcr.io/YOUR_PROJECT/custom-jupyter:latest .
docker push gcr.io/YOUR_PROJECT/custom-jupyter:latest
```

### Multiple User Profiles

Allow users to choose resources:

```yaml
singleuser:
  profileList:
    - display_name: "Small (2 CPU, 4GB RAM)"
      description: "For light workloads"
      kubespawner_override:
        cpu_limit: 2
        cpu_guarantee: 1
        mem_limit: "4G"
        mem_guarantee: "2G"

    - display_name: "Large (8 CPU, 16GB RAM)"
      description: "For heavy workloads"
      kubespawner_override:
        cpu_limit: 8
        cpu_guarantee: 4
        mem_limit: "16G"
        mem_guarantee: "8G"
```

### Shared Notebooks Repository

Mount read-only notebooks:

```yaml
singleuser:
  extraVolumes:
    - name: shared-notebooks
      persistentVolumeClaim:
        claimName: shared-notebooks-pvc
  extraVolumeMounts:
    - name: shared-notebooks
      mountPath: /home/jovyan/shared
      readOnly: true
```

### Google Workspace Authentication

Switch to Google OAuth for SSO:

```yaml
hub:
  config:
    JupyterHub:
      authenticator_class: oauthenticator.google.GoogleOAuthenticator
    GoogleOAuthenticator:
      client_id: "your-client-id.apps.googleusercontent.com"
      client_secret: "your-client-secret"
      oauth_callback_url: "https://jupyter.yourdomain.com/hub/oauth_callback"
      hosted_domain:
        - "yourdomain.com"
      login_service: "Google Workspace"
```

### GPU Support

For ML workloads, add GPU node pool:

```bash
gcloud container node-pools create gpu-pool \
  --cluster=$CLUSTER_NAME \
  --region=$REGION \
  --accelerator type=nvidia-tesla-t4,count=1 \
  --machine-type=n1-standard-4 \
  --num-nodes=0 \
  --min-nodes=0 \
  --max-nodes=3 \
  --enable-autoscaling
```

Update config.yaml:
```yaml
singleuser:
  extraResource:
    limits:
      nvidia.com/gpu: "1"
```

## Support

- **JupyterHub Docs**: https://jupyterhub.readthedocs.io
- **Zero to JupyterHub**: https://zero-to-jupyterhub.readthedocs.io
- **GKE Docs**: https://cloud.google.com/kubernetes-engine/docs
- **GCP Support**: https://cloud.google.com/support

## License

This configuration is provided as-is for educational and production use.
