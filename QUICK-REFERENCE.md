# Quick Reference Guide - JupyterHub on AKS

## 📦 All Scripts

| Script | Purpose | Time | Cost Impact |
|--------|---------|------|-------------|
| `setup-aks-cluster.sh` | Create cluster + node pools | 10-15 min | Starts ~$70/month |
| `deploy-jupyterhub.sh` | Deploy JupyterHub | 5-10 min | No change |
| `cleanup-jupyterhub-only.sh` | Remove JupyterHub only | 2-3 min | Keeps ~$70/month |
| `cleanup-all.sh` | Destroy everything | 5-10 min | Stops all costs |

## 🚀 Quick Start (3 Commands)

```bash
# 1. Setup (once)
chmod +x *.sh

# 2. Create cluster
./setup-aks-cluster.sh

# 3. Deploy JupyterHub
./deploy-jupyterhub.sh
```

## 🔄 Common Workflows

### First Time Deployment
```bash
./setup-aks-cluster.sh    # Create cluster
./deploy-jupyterhub.sh    # Deploy JupyterHub
# Open browser to http://<EXTERNAL-IP>
```

### Test and Redeploy
```bash
./cleanup-jupyterhub-only.sh    # Remove JupyterHub
# Make changes to config.yaml
./deploy-jupyterhub.sh          # Deploy again
```

### Complete Cleanup
```bash
./cleanup-all.sh    # Delete everything
```

## 📋 Manual Commands Reference

### Cluster Management

```bash
# List clusters
az aks list --output table

# List node pools
az aks nodepool list \
  --cluster-name jhub-test-cluster \
  --resource-group DDA-Resources-AKS \
  --output table

# Get cluster credentials
az aks get-credentials \
  --resource-group DDA-Resources-AKS \
  --name jhub-test-cluster

# Delete cluster
az aks delete \
  --resource-group DDA-Resources-AKS \
  --name jhub-test-cluster \
  --yes --no-wait
```

### JupyterHub Management

```bash
# Deploy JupyterHub
helm upgrade --install jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --create-namespace \
  --values config.yaml \
  --version=4.3.1

# Uninstall JupyterHub
helm uninstall jupyterhub -n jupyterhub

# List Helm releases
helm list -n jupyterhub

# Update configuration
helm upgrade jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --values config.yaml \
  --version=4.3.1
```

### Kubernetes Commands

```bash
# Get all resources
kubectl get all -n jupyterhub

# Get pods
kubectl get pods -n jupyterhub

# Get services and external IP
kubectl get svc -n jupyterhub
kubectl get svc proxy-public -n jupyterhub

# Get nodes and their pools
kubectl get nodes -L agentpool

# Get PVCs
kubectl get pvc -n jupyterhub

# Check logs
kubectl logs -n jupyterhub deployment/hub
kubectl logs -n jupyterhub deployment/proxy
kubectl logs -n jupyterhub <pod-name>

# Describe resources
kubectl describe pod <pod-name> -n jupyterhub
kubectl describe svc proxy-public -n jupyterhub

# Delete namespace
kubectl delete namespace jupyterhub

# Port forward (local access)
kubectl port-forward -n jupyterhub svc/proxy-public 8080:80
# Then access: http://localhost:8080
```

### Monitoring

```bash
# Watch pods
kubectl get pods -n jupyterhub -w

# Watch nodes
kubectl get nodes -L agentpool -w

# Watch services
kubectl get svc -n jupyterhub -w

# Resource usage
kubectl top nodes
kubectl top pods -n jupyterhub

# Events
kubectl get events -n jupyterhub --sort-by='.lastTimestamp'
```

## 🔍 Troubleshooting Commands

### Check External IP

```bash
# Get external IP
kubectl get svc proxy-public -n jupyterhub -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Or with full output
kubectl get svc proxy-public -n jupyterhub

# Describe service (shows events)
kubectl describe svc proxy-public -n jupyterhub
```

### Check Pod Status

```bash
# List all pods
kubectl get pods -n jupyterhub

# Check specific pod
kubectl describe pod <pod-name> -n jupyterhub

# Get pod logs
kubectl logs <pod-name> -n jupyterhub

# Get previous logs (if pod restarted)
kubectl logs <pod-name> -n jupyterhub --previous

# Follow logs
kubectl logs -f <pod-name> -n jupyterhub
```

### Check Autoscaling

```bash
# Check node count
kubectl get nodes -L agentpool

# Check node pool details
az aks nodepool show \
  --cluster-name jhub-test-cluster \
  --resource-group DDA-Resources-AKS \
  --name userpool

# Check cluster autoscaler logs (if issues)
kubectl logs -n kube-system -l app=cluster-autoscaler
```

### Check Storage

```bash
# List PVCs
kubectl get pvc -n jupyterhub

# List PVs
kubectl get pv

# Describe PVC
kubectl describe pvc <pvc-name> -n jupyterhub

# Check storage class
kubectl get storageclass
```

## 🎯 Testing Checklist

```bash
# 1. Cluster created
az aks show --resource-group DDA-Resources-AKS --name jhub-test-cluster

# 2. Node pools exist
az aks nodepool list --cluster-name jhub-test-cluster --resource-group DDA-Resources-AKS --output table

# 3. Nodes have correct labels
kubectl get nodes -L agentpool

# 4. JupyterHub pods running
kubectl get pods -n jupyterhub

# 5. External IP assigned
kubectl get svc proxy-public -n jupyterhub

# 6. Can access login page
curl -I http://<EXTERNAL-IP>

# 7. User can login and start server
# (Manual test in browser)

# 8. User pod on correct node pool
kubectl get pods -n jupyterhub -o wide

# 9. Autoscaling works
# Login 1 user → check nodes
# Login 3 users → check nodes
# Wait 1 hour → check nodes (should scale down)

# 10. Storage persists
# Create file in notebook → restart server → check file exists
```

## 💰 Cost Management

```bash
# Check current node count
kubectl get nodes

# Check resource usage
kubectl top nodes

# Manually scale user pool to 0 (testing)
az aks nodepool scale \
  --cluster-name jhub-test-cluster \
  --resource-group DDA-Resources-AKS \
  --name userpool \
  --node-count 0

# Check costs (Azure Portal)
# Go to: Cost Management + Billing → Cost Analysis
# Filter by: Resource Group = DDA-Resources-AKS
```

## 🔐 Access Methods

### Method 1: Direct IP (Default)
```bash
# Get IP
kubectl get svc proxy-public -n jupyterhub -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Access
http://<EXTERNAL-IP>
```

### Method 2: Port Forward (Local Testing)
```bash
kubectl port-forward -n jupyterhub svc/proxy-public 8080:80
# Access: http://localhost:8080
```

### Method 3: kubectl proxy (Alternative)
```bash
kubectl proxy
# Access: http://localhost:8001/api/v1/namespaces/jupyterhub/services/http:proxy-public:/proxy/
```

## 📊 Architecture Verification

```bash
# 1. Verify node pools
az aks nodepool list \
  --cluster-name jhub-test-cluster \
  --resource-group DDA-Resources-AKS \
  --query "[].{Name:name, VmSize:vmSize, Count:count, Min:minCount, Max:maxCount}" \
  --output table

# 2. Verify pod placement
kubectl get pods -n jupyterhub -o wide

# Expected:
# hub-xxx       → hubpool
# proxy-xxx     → hubpool
# jupyter-user01 → userpool

# 3. Verify autoscaling enabled
az aks nodepool show \
  --cluster-name jhub-test-cluster \
  --resource-group DDA-Resources-AKS \
  --name userpool \
  --query "{Name:name, AutoScaling:enableAutoScaling, Min:minCount, Max:maxCount}"
```

## 📝 User Management

```bash
# Access admin panel
# http://<EXTERNAL-IP>/hub/admin

# Or via API (example)
kubectl exec -n jupyterhub deployment/hub -- \
  jupyterhub token --help
```

## 🛠️ Configuration Updates

```bash
# Update config.yaml, then:
helm upgrade jupyterhub jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --values config.yaml \
  --version=4.3.1

# Check rollout status
kubectl rollout status deployment/hub -n jupyterhub
kubectl rollout status deployment/proxy -n jupyterhub
```

## 🆘 Emergency Commands

```bash
# Restart Hub
kubectl rollout restart deployment/hub -n jupyterhub

# Restart Proxy
kubectl rollout restart deployment/proxy -n jupyterhub

# Delete stuck pod
kubectl delete pod <pod-name> -n jupyterhub --force --grace-period=0

# Reset everything (keep cluster)
./cleanup-jupyterhub-only.sh
./deploy-jupyterhub.sh

# Nuclear option (delete everything)
./cleanup-all.sh
```

## 📞 Support Resources

- **JupyterHub Docs:** https://z2jh.jupyter.org/
- **Azure AKS Docs:** https://docs.microsoft.com/en-us/azure/aks/
- **Helm Docs:** https://helm.sh/docs/
- **Kubernetes Docs:** https://kubernetes.io/docs/

## 💡 Tips

1. **Always check logs first**: `kubectl logs -n jupyterhub deployment/hub`
2. **Use watch mode**: `kubectl get pods -n jupyterhub -w`
3. **Test locally first**: Use port-forward before exposing externally
4. **Monitor costs**: Check Azure Cost Management daily
5. **Backup config**: Keep your config.yaml in version control
6. **Test autoscaling**: Login/logout multiple users to verify
7. **Document changes**: Keep notes of any config modifications
8. **Set budget alerts**: In Azure portal, set up cost alerts

## ⚡ One-Liners

```bash
# Get access URL
echo "http://$(kubectl get svc proxy-public -n jupyterhub -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"

# Count running user pods
kubectl get pods -n jupyterhub | grep jupyter- | wc -l

# Check if autoscaling is working
watch -n 5 'kubectl get nodes -L agentpool'

# Get all external IPs in cluster
kubectl get svc --all-namespaces -o wide | grep LoadBalancer

# Quick health check
kubectl get pods -n jupyterhub | grep -v Running || echo "All pods running"
```
