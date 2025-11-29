# JupyterHub Deployment on AKS - Test Guide

This guide will help you deploy JupyterHub on Azure Kubernetes Service (AKS) following the document's architecture.

## Files Included

- `setup-aks-cluster.sh` - Creates AKS cluster and node pools (Steps 1-5)
- `config.yaml` - JupyterHub configuration for AKS
- `deploy-jupyterhub.sh` - Deploys JupyterHub using Helm (Step 6)
- `cleanup-jupyterhub-only.sh` - Removes JupyterHub but keeps cluster
- `cleanup-all.sh` - Destroys cluster and all resources
- `README.md` - This file

## Prerequisites

1. Azure CLI installed and logged in
   ```bash
   az login
   az account set --subscription "YOUR_SUBSCRIPTION"
   ```

2. kubectl installed
   ```bash
   az aks install-cli
   ```

3. Helm 3 installed (script will install if missing)

## Architecture

```
┌──────────────────────────────────────────────┐
│ AKS Cluster: jhub-test-cluster              │
├──────────────────────────────────────────────┤
│                                              │
│ Node Pool 1: hubpool                         │
│ ├─ VM Size: Standard_D2s_v3 (2 vCPU, 8GB)  │
│ ├─ Count: 1 node (always on)                │
│ ├─ Purpose: Hub + Proxy pods                │
│ └─ Label: agentpool=hubpool                 │
│                                              │
│ Node Pool 2: userpool                        │
│ ├─ VM Size: Standard_D4s_v3 (4 vCPU, 16GB) │
│ ├─ Count: 0-3 nodes (autoscaling)           │
│ ├─ Purpose: User JupyterLab pods            │
│ └─ Label: agentpool=userpool                │
│                                              │
└──────────────────────────────────────────────┘
```

## Deployment Steps

### Step 1: Make Scripts Executable

```bash
chmod +x setup-aks-cluster.sh
chmod +x deploy-jupyterhub.sh
```

### Step 2: Create AKS Cluster (Steps 1-5)

This creates the cluster and node pools (takes ~10-15 minutes):

```bash
./setup-aks-cluster.sh
```

**What it does:**
- Creates AKS cluster named `jhub-test-cluster`
- Creates `hubpool` node pool (1 node for Hub/Proxy)
- Creates `userpool` node pool (0-3 autoscaling nodes for users)
- Configures kubectl
- Adds Helm repository

**Expected output:**
```
✅ AKS Cluster Setup Complete!

Node Pools:
  1. hubpool (Standard_D2s_v3, 1 node) - For Hub/Proxy
  2. userpool (Standard_D4s_v3, 0-3 nodes) - For Users
```

### Step 3: Deploy JupyterHub (Step 6)

This deploys JupyterHub using the config.yaml (takes ~5-10 minutes):

```bash
./deploy-jupyterhub.sh
```

**What it does:**
- Creates `jupyterhub` namespace
- Deploys JupyterHub via Helm
- Waits for pods to be ready
- Gets external IP address

**Expected output:**
```
✅ JupyterHub Deployment Complete!

Access JupyterHub at:
  http://20.123.45.67
```

### Step 4: Initial Setup

1. **Open the URL in your browser**
   ```
   http://<EXTERNAL-IP>
   ```

2. **Login as admin**
   - Username: `sysadmin`
   - Password: Create one (minimum 8 characters)

3. **Go to Admin Panel**
   ```
   http://<EXTERNAL-IP>/hub/admin
   ```

4. **Authorize users**
   - Click "Add Users"
   - Add: `user01`, `user02`, `user03`
   - Or authorize them as they first login

5. **Test user login**
   - Logout
   - Login as `user01`
   - Create password
   - Click "Start My Server"

## Verification

### Check Node Scaling

```bash
# Check nodes (should see 1 hubpool node)
kubectl get nodes -L agentpool

# Login as a user and start server
# Then check nodes again (should see userpool node appear)
kubectl get nodes -L agentpool

# Check pods
kubectl get pods -n jupyterhub
```

### Check Services

```bash
# Get external IP
kubectl get svc proxy-public -n jupyterhub

# Check all resources
kubectl get all -n jupyterhub
```

### Check Logs

```bash
# Hub logs
kubectl logs -n jupyterhub deployment/hub

# Proxy logs
kubectl logs -n jupyterhub deployment/proxy

# User pod logs (when user starts server)
kubectl logs -n jupyterhub <jupyter-username-pod>
```

## Testing the Document's Features

### 1. Static Authentication ✅
- Login with `user01`, `user02`, `user03`
- Only these users can login (no self-signup)

### 2. Node Pool Separation ✅
```bash
# Check which nodes pods are running on
kubectl get pods -n jupyterhub -o wide

# Hub/Proxy should be on hubpool
# User pods should be on userpool
```

### 3. Autoscaling ✅
```bash
# Before users login
kubectl get nodes -L agentpool
# Should show: hubpool=1, userpool=0

# Login 1 user
kubectl get nodes -L agentpool
# Should show: hubpool=1, userpool=1

# Login 3 users
kubectl get nodes -L agentpool
# Should show: hubpool=1, userpool=3
```

### 4. User Persistence ✅
```bash
# Check PVCs created for users
kubectl get pvc -n jupyterhub

# Should see one PVC per user
```

### 5. Culling (Cost Saving) ✅
- Leave a user idle for 1 hour
- Pod should be culled (deleted)
- Node should scale down to 0 if no users

```bash
# Check after 1 hour of inactivity
kubectl get pods -n jupyterhub
# User pods should be gone

kubectl get nodes -L agentpool
# userpool should scale to 0
```

## Costs

| Component | Size | Running Time | Est. Cost/Month |
|-----------|------|--------------|-----------------|
| hubpool | Standard_D2s_v3 | 24/7 | ~$70 |
| userpool (3 users, 4h/day) | Standard_D4s_v3 | 264 hrs | ~$30 |
| Storage (3x50GB) | Managed Disk | 24/7 | ~$15 |
| **Total** | | | **~$115/month** |

## Cleanup

### Option 1: Delete Only JupyterHub (Keep Cluster)

Use this if you want to test redeployment without recreating the cluster:

```bash
chmod +x cleanup-jupyterhub-only.sh
./cleanup-jupyterhub-only.sh
```

**What it does:**
- ✅ Deletes JupyterHub Helm release
- ✅ Deletes namespace and all user data
- ✅ Deletes PVCs
- ✅ Keeps cluster and node pools (ready for redeployment)

**Cost after cleanup:** ~$70/month (only hubpool running)

### Option 2: Delete Everything (Cluster + All Resources)

Use this to completely remove all resources and stop all costs:

```bash
chmod +x cleanup-all.sh
./cleanup-all.sh
```

**What it does:**
- ✅ Deletes JupyterHub deployment
- ✅ Deletes namespace and all data
- ✅ Deletes AKS cluster
- ✅ Deletes all node pools
- ✅ Deletes all associated Azure resources (Load Balancers, Disks, NICs, etc.)
- ✅ Cleans up local kubectl context

**Cost after cleanup:** $0

**Safety features:**
- Multiple confirmation prompts
- Shows resources before deletion
- Requires typing cluster name to confirm
- Optional: Wait for deletion to complete

### Manual Cleanup (Alternative)

```bash
# Delete just JupyterHub
helm uninstall jupyterhub -n jupyterhub
kubectl delete namespace jupyterhub

# Delete the entire cluster
az aks delete \
  --resource-group DDA-Resources-AKS \
  --name jhub-test-cluster \
  --yes --no-wait
```

## Troubleshooting

### External IP stuck on <pending>

```bash
# Check service
kubectl describe svc proxy-public -n jupyterhub

# Check Azure load balancer
az network lb list --resource-group MC_DDA-Resources-AKS_jhub-test-cluster_uaenorth
```

### Pods not starting

```bash
# Check pod status
kubectl get pods -n jupyterhub

# Check pod events
kubectl describe pod <pod-name> -n jupyterhub

# Check logs
kubectl logs <pod-name> -n jupyterhub
```

### User pod stuck pending

```bash
# Check if userpool is scaling
kubectl get nodes -L agentpool

# Check pod events
kubectl describe pod jupyter-<username> -n jupyterhub

# Check autoscaler logs
kubectl logs -n kube-system deployment/cluster-autoscaler
```

### Can't login

```bash
# Check hub logs
kubectl logs -n jupyterhub deployment/hub

# Check if database PVC is bound
kubectl get pvc -n jupyterhub
```

## Useful Commands

```bash
# Get access URL
kubectl get svc proxy-public -n jupyterhub -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Watch pods
kubectl get pods -n jupyterhub -w

# Watch nodes scaling
kubectl get nodes -L agentpool -w

# Check resource usage
kubectl top nodes
kubectl top pods -n jupyterhub

# Port forward (alternative access)
kubectl port-forward -n jupyterhub svc/proxy-public 8080:80
# Then access: http://localhost:8080
```

## Document Comparison

| Document (GKE) | This Implementation (AKS) |
|----------------|---------------------------|
| `gcloud container clusters create` | `az aks create` |
| `--node-pool-name` | `--nodepool-name` |
| `gcloud container node-pools create` | `az aks nodepool add` |
| `cloud.google.com/gke-nodepool` | `agentpool` |
| `default-pool` | `hubpool` |
| `user-pool` | `userpool` |
| `e2-standard-2` | `Standard_D2s_v3` |
| `e2-standard-4` | `Standard_D4s_v3` |
| `standard` StorageClass | `managed-csi` StorageClass |

## Success Criteria

✅ Cluster created with 2 node pools
✅ Hub and Proxy running on hubpool
✅ Users can login (sysadmin, user01, user02, user03)
✅ User pods spawn on userpool
✅ userpool autoscales (0-3 nodes)
✅ User persistence works (files saved)
✅ Master notebooks mounted read-only
✅ Pods culled after 1 hour inactivity
✅ Nodes scale down when no users

## Next Steps

After successful testing:
1. Add custom domain
2. Enable HTTPS (Let's Encrypt)
3. Configure actual Git repository for master notebooks
4. Adjust resource limits based on actual usage
5. Set up monitoring and alerts
6. Configure backup for user data

---

**Questions or Issues?**
Check the logs and run the verification commands above.
