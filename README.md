# Multi-Cloud JupyterHub Deployment

Production-grade JupyterHub deployments for multiple cloud providers with custom domains, HTTPS, and autoscaling.

## Supported Platforms

### ✅ Azure (AKS)
**Status**: Production-ready

Full production deployment with:
- Custom domain and HTTPS (Let's Encrypt)
- Auto-scaling node pools
- Cost optimization with culling
- Persistent user storage
- Native authentication

**[→ Go to Azure Setup](azure/)**

### ✅ Google Cloud (GKE)
**Status**: Production-ready

Full production deployment with:
- Custom domain and HTTPS (Let's Encrypt)
- Auto-scaling node pools
- Cost optimization with culling
- Persistent user storage
- Native authentication
- Cloud DNS support (optional)

**[→ Go to GCP Setup](gcp/)**

## Quick Start

Choose your cloud provider:

### Azure
```bash
cd azure
cp .env.template .env
# Edit .env with your configuration
./setup.sh
```

See detailed instructions in [azure/README.md](azure/)

### Google Cloud
```bash
cd gcp
cp .env.template .env
# Edit .env with your configuration
./setup.sh
```

See detailed instructions in [gcp/README.md](gcp/)

## Architecture Overview

Both platforms follow the same design:

```
┌──────────────────────────────────────────┐
│ Kubernetes Cluster                       │
├──────────────────────────────────────────┤
│                                          │
│ Hub Pool (1 node)                        │
│ ├─ JupyterHub Hub                       │
│ ├─ Proxy                                │
│ ├─ Ingress Controller                   │
│ └─ cert-manager (SSL)                   │
│                                          │
│ User Pool (auto-scaling 0-N nodes)      │
│ └─ User Jupyter notebooks               │
│                                          │
└──────────────────────────────────────────┘
         ↓
    HTTPS (Let's Encrypt)
         ↓
    https://jupyter.yourdomain.com
```

## Features

- **🔒 Secure**: HTTPS with automatic SSL certificate management
- **🌐 Custom Domain**: Use your own domain name
- **📈 Auto-scaling**: Scales based on demand (0 to N nodes)
- **💰 Cost-optimized**: Automatically culls idle notebooks
- **💾 Persistent**: User data persists across sessions
- **🎯 Production-ready**: Tested configurations for production use

## Project Structure

```
.
├── README.md                 # This file
├── azure/                    # Azure AKS deployment
│   ├── README.md            # Azure-specific instructions
│   ├── .env.template        # Configuration template
│   ├── config.yaml          # JupyterHub configuration
│   ├── setup.sh            # Setup script
│   └── cleanup.sh          # Cleanup script
├── gcp/                     # Google Cloud deployment
│   ├── README.md            # GCP-specific instructions
│   ├── .env.template        # Configuration template
│   ├── config.yaml          # JupyterHub configuration
│   ├── setup.sh            # Setup script
│   └── cleanup.sh          # Cleanup script
└── archive/                 # Old/backup files
```

## Prerequisites

- Cloud provider account (Azure or GCP)
- Domain name with DNS access
- Basic command line knowledge
- `kubectl` and cloud CLI installed

## Support

- **Azure Issues**: See [azure/README.md](azure/)
- **General Questions**: Create an issue
- **Documentation**: Each platform has detailed README

## License

Provided as-is for educational and production use.
