# Production JupyterHub on Azure AKS

Production-grade JupyterHub deployment on Azure Kubernetes Service (AKS) with custom domain, HTTPS, and autoscaling.

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
│ Azure AKS Cluster                                   │
├─────────────────────────────────────────────────────┤
│                                                     │
│ Hub Pool (hubpool)                                  │
│ ├─ 1x Standard_D2s_v3 (2 vCPU, 8GB)               │
│ ├─ JupyterHub Hub                                  │
│ ├─ Proxy                                           │
│ ├─ NGINX Ingress Controller                        │
│ └─ cert-manager                                    │
│                                                     │
│ User Pool (userpool)                               │
│ ├─ 0-5x Standard_D4s_v3 (4 vCPU, 16GB)           │
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

1. **Azure CLI** installed and logged in
   ```bash
   az login
   az account set --subscription "YOUR_SUBSCRIPTION"
   ```

2. **kubectl** installed
   ```bash
   az aks install-cli
   ```

3. **Helm 3** installed (or script will install it)
   ```bash
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```

4. **Domain name** with ability to create DNS A records

## Quick Start

### 1. Configure Environment

Copy the template and fill in your values:

```bash
cd azure
cp .env.template .env
nano .env
```

Required values:
```bash
RESOURCE_GROUP="jupyterhub-prod"
CLUSTER_NAME="jupyterhub-cluster"
LOCATION="eastus"                    # Or your preferred region
DOMAIN="jupyter.yourdomain.com"      # Your domain
EMAIL="admin@yourdomain.com"         # For SSL certificates
```

### 2. Run Setup

```bash
chmod +x setup.sh
./setup.sh
```

The script will:
1. Create Azure resource group
2. Create AKS cluster with node pools
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
azure/
├── README.md           # This file
├── .env.template       # Environment configuration template
├── config.yaml         # JupyterHub configuration
├── setup.sh           # Complete deployment script
└── cleanup.sh         # Resource cleanup script
```

## Configuration

### Node Pools

Customize VM sizes and scaling in `.env`:

```bash
# Hub pool (always-on, runs core services)
HUB_VM_SIZE="Standard_D2s_v3"

# User pool (auto-scales, runs user notebooks)
USER_VM_SIZE="Standard_D4s_v3"
MIN_NODES=0
MAX_NODES=5
```

### Azure VM Sizes

Common VM sizes:
- `Standard_D2s_v3`: 2 vCPU, 8 GB RAM (~$70/month)
- `Standard_D4s_v3`: 4 vCPU, 16 GB RAM (~$140/month)
- `Standard_E2s_v3`: 2 vCPU, 16 GB RAM (~$100/month, memory-optimized)
- `Standard_E4s_v3`: 4 vCPU, 32 GB RAM (~$200/month, memory-optimized)

### Resource Limits

Per-user resources in [config.yaml](config.yaml#L96-L103):

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

Auto-shutdown idle notebooks in [config.yaml](config.yaml#L134-L141):

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
az aks nodepool update \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --name userpool \
  --min-count 0 \
  --max-count 10
```

## Costs

Estimated monthly costs (US East):

| Component | Type | Hours | Cost/Month |
|-----------|------|-------|------------|
| Hub Pool | Standard_D2s_v3 (1 node) | 730 | ~$70 |
| User Pool | Standard_D4s_v3 (avg 2 nodes, 8h/day) | 480 | ~$70 |
| Storage | 50GB per user (3 users) | 730 | ~$15 |
| Ingress | Load Balancer | 730 | ~$25 |
| **Total** | | | **~$180/month** |

**Cost optimization tips:**
- Culling reduces user pool to 0 nodes when idle
- Adjust `MAX_NODES` based on actual usage
- Use smaller VM sizes for lighter workloads
- Set aggressive cull timeout for dev environments

## Cleanup

Three cleanup levels:

### 1. Delete Only JupyterHub
Keeps cluster, removes application:
```bash
./cleanup.sh
# Choose option 1
```
Cost: ~$70/month (hub pool still running)

### 2. Delete Cluster
Removes cluster, keeps resource group:
```bash
./cleanup.sh
# Choose option 2
```
Cost: $0

### 3. Delete Everything
Removes all Azure resources:
```bash
./cleanup.sh
# Choose option 3
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

# Check autoscaler logs
kubectl logs -n kube-system -l app=cluster-autoscaler

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

### Resource Quota Issues

If you hit Azure resource limits:
```bash
# Check current quotas
az vm list-usage --location $LOCATION --output table

# Request quota increase via Azure Portal:
# Portal > Subscriptions > Usage + quotas > Request increase
```

## Security Best Practices

1. **Use strong passwords**: Minimum 12 characters enforced
2. **Keep images updated**: Regularly update Jupyter image tags in config.yaml
3. **Limit user access**: Only add necessary users to `allowed_users`
4. **Monitor access**: Review hub logs regularly
5. **Backup data**: Set up persistent volume snapshots
6. **Network policies**: Consider adding Kubernetes network policies
7. **Private cluster**: For sensitive workloads, use private AKS cluster

## Advanced Configuration

### Custom Jupyter Images

In [config.yaml](config.yaml#L87-L89):

```yaml
singleuser:
  image:
    name: your-registry.azurecr.io/custom-jupyter
    tag: "latest"
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

### Azure AD Authentication

Switch to Azure AD for enterprise SSO:

```yaml
hub:
  config:
    JupyterHub:
      authenticator_class: oauthenticator.azuread.AzureAdOAuthenticator
    AzureAdOAuthenticator:
      client_id: "your-client-id"
      client_secret: "your-client-secret"
      oauth_callback_url: "https://jupyter.yourdomain.com/hub/oauth_callback"
      tenant_id: "your-tenant-id"
```

### Azure DNS Integration

Automatically manage DNS with Azure DNS:

```bash
# Create DNS zone
az network dns zone create \
  --resource-group $RESOURCE_GROUP \
  --name yourdomain.com

# Add A record
az network dns record-set a add-record \
  --resource-group $RESOURCE_GROUP \
  --zone-name yourdomain.com \
  --record-set-name jupyter \
  --ipv4-address $INGRESS_IP
```

### GPU Support

For ML workloads, add GPU node pool:

```bash
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --name gpupool \
  --node-count 0 \
  --min-count 0 \
  --max-count 3 \
  --enable-cluster-autoscaler \
  --node-vm-size Standard_NC6s_v3 \
  --node-taints sku=gpu:NoSchedule \
  --labels agentpool=gpupool
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
- **Azure AKS Docs**: https://docs.microsoft.com/en-us/azure/aks/

## License

This configuration is provided as-is for educational and production use.
