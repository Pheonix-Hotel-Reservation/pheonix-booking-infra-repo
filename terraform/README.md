# Terraform Infrastructure for Phoenix Kubernetes Cluster

## Overview
This Terraform configuration creates a production-ready AWS infrastructure for a Kubeadm-based Kubernetes cluster with full support for:
- **AWS Load Balancer Controller** (for Application/Network Load Balancers)
- **EBS CSI Driver** (for persistent volume storage)
- **AWS Cloud Controller Manager** (for native AWS integration)

## Architecture

### Networking
- **VPC**: 10.0.0.0/16 with DNS support enabled
- **Public Subnets**: 3 subnets across AZs (tagged for external load balancers)
- **Private Subnets**: 3 subnets across AZs (tagged for internal load balancers)
- **Internet Gateway**: For public subnet internet access
- **NAT Gateway**: For private subnet outbound traffic

### Critical Kubernetes Tags
All resources are tagged appropriately for Kubernetes cloud controller discovery:
- VPC & Subnets: `kubernetes.io/cluster/phoenix-cluster = shared`
- Public Subnets: `kubernetes.io/role/elb = 1`
- Private Subnets: `kubernetes.io/role/internal-elb = 1`
- EC2 Instances: `kubernetes.io/cluster/phoenix-cluster = owned`

### IAM Configuration
The `k8s-node-role` includes permissions for:
1. **EC2 Full Access** - Required for CCM operations
2. **ELB Full Access** - Required for Load Balancer Controller
3. **EBS CSI Driver Policy** - For volume management
4. **AWS Load Balancer Controller Policy** - For ALB/NLB creation

### Compute
- **3 EC2 Instances** (t3.large, Ubuntu 22.04)
  - 1 Master node
  - 2 Worker nodes
- **50GB GP3 root volumes**
- **Instance Profile** attached with all required policies

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0
3. **SSH Key Pair**: Public key at `~/.ssh/id_rsa.pub`

## Usage

### Initialize Terraform
```bash
cd infra/terraform
terraform init
```

### Plan Infrastructure
```bash
terraform plan
```

### Deploy Infrastructure
```bash
terraform apply
```

This will:
1. Create VPC, subnets, and networking components
2. Set up IAM roles and policies
3. Launch 3 EC2 instances
4. Generate `../ansible/inventory.ini` for Ansible automation

### Destroy Infrastructure
```bash
terraform destroy
```

## Outputs

After successful deployment:
- `master_public_ip`: SSH access to master node
- `worker_public_ips`: SSH access to worker nodes
- `vpc_id`: VPC identifier
- `cluster_name`: Kubernetes cluster name

## Important Notes

1. **Cloud Provider Mode**: This infrastructure is designed for `--cloud-provider=external` mode
2. **Hostname Configuration**: Instances are configured with EC2 Private DNS as hostname (required for CCM)
3. **Security Groups**: Configured for all Kubernetes control plane and data plane traffic
4. **Tags**: All tags are critical for AWS cloud controller discovery - do not modify

## Next Steps

After Terraform deployment, use Ansible to:
1. Install Kubernetes components
2. Initialize the cluster with CCM support
3. Install AWS Load Balancer Controller
4. Install EBS CSI Driver

See `../ansible/README.md` for cluster provisioning instructions.
