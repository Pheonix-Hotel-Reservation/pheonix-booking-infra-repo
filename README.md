# Phoenix Kubernetes Cluster Infrastructure

## Overview
Complete infrastructure-as-code solution for deploying a production-ready Kubernetes cluster on AWS with full support for:
- **AWS Load Balancer Controller** - Manages ALB/NLB for Ingress and LoadBalancer services
- **EBS CSI Driver** - Provides persistent volume storage
- **AWS Cloud Controller Manager** - Native AWS integration (node lifecycle, metadata, zones)

## Architecture

### Infrastructure Components
- **VPC**: 10.0.0.0/16 with public/private subnets across 3 AZs
- **IAM**: Comprehensive policies for cloud controllers (EC2, ELB, EBS)
- **EC2**: 3 instances (t3.large, Ubuntu 22.04)
  - 1 Master (control plane)
  - 2 Workers (compute nodes)
- **Security**: Security groups for all Kubernetes traffic

### Kubernetes Stack
- **Kubernetes**: v1.28 (kubeadm)
- **Container Runtime**: containerd with systemd cgroup
- **CNI**: Calico (192.168.0.0/16)
- **Cloud Provider**: External mode (required for AWS controllers)

## Critical Design Decisions

### 1. Cloud Provider External Mode
Instead of legacy in-tree cloud provider (`--cloud-provider=aws`), this setup uses:
- `--cloud-provider=external` on kubelet
- Separate AWS Cloud Controller Manager (CCM) as a DaemonSet

**Why?** The in-tree provider is deprecated and doesn't support modern features like ALB Ingress.

### 2. Subnet Tagging
All subnets are tagged for automatic discovery:
```
kubernetes.io/cluster/phoenix-cluster = shared
kubernetes.io/role/elb = 1                    # Public subnets
kubernetes.io/role/internal-elb = 1           # Private subnets
```

**Why?** AWS Load Balancer Controller uses these tags to select subnets for load balancers.

### 3. Instance Tagging
EC2 instances tagged with:
```
kubernetes.io/cluster/phoenix-cluster = owned
```

**Why?** The CCM needs this to identify which instances belong to the cluster.

### 4. IAM Instance Profile
All instances use the same IAM role with policies for:
- EC2 (node lifecycle, metadata)
- ELB (load balancer management)
- EBS (volume operations)

**Why?** Controllers running on nodes need AWS API permissions.

### 5. Hostname = EC2 Private DNS
Nodes are configured with their EC2 Private DNS as hostname (e.g., `ip-10-0-1-50.ec2.internal`).

**Why?** The CCM matches Kubernetes nodes to EC2 instances by hostname.

## Directory Structure

```
infra/
├── terraform/              # Infrastructure provisioning
│   ├── provider.tf         # AWS provider configuration
│   ├── variables.tf        # Input variables
│   ├── vpc.tf              # VPC with Kubernetes tags
│   ├── iam.tf              # IAM roles and policies
│   ├── security.tf         # Security groups
│   ├── ec2.tf              # EC2 instances
│   ├── outputs.tf          # Outputs and inventory generation
│   └── templates/
│       └── inventory.tpl   # Ansible inventory template
│
├── ansible/                # Cluster configuration
│   ├── ansible.cfg         # Ansible settings
│   ├── site.yml            # Main playbook
│   ├── install-controllers.yml  # Post-install controllers
│   └── roles/
│       ├── common/         # Base setup (all nodes)
│       ├── master/         # Control plane + CCM
│       └── worker/         # Worker join logic
│
└── README.md               # This file
```

## Deployment Guide

### Prerequisites

1. **AWS CLI** configured with credentials
   ```bash
   aws configure
   ```

2. **SSH Key Pair**
   ```bash
   # Generate if needed
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
   ```

3. **Tools Installed**
   - Terraform >= 1.0
   - Ansible >= 2.10

### Step 1: Deploy Infrastructure (Terraform)

```bash
cd infra/terraform

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure (10-15 minutes)
terraform apply

# Save outputs
terraform output
```

**What gets created:**
- VPC with 6 subnets (3 public, 3 private)
- Internet Gateway + NAT Gateway
- IAM role with 4 policies
- 3 EC2 instances with security group
- Ansible inventory file at `../ansible/inventory.ini`

### Step 2: Deploy Kubernetes (Ansible)

```bash
cd ../ansible

# Verify connectivity
ansible all -m ping

# Deploy cluster (20-25 minutes)
ansible-playbook site.yml
```

**What gets configured:**
1. **All nodes**: containerd, kubelet, kubeadm, kubectl
2. **Master**: kubeadm init, Calico CNI, AWS CCM
3. **Workers**: Join cluster, wait for Ready state

### Step 3: Install AWS Controllers

```bash
# SSH to master node
ssh ubuntu@$(cd ../terraform && terraform output -raw master_public_ip)

# Verify cluster is healthy
kubectl get nodes
# All nodes should be Ready

# Check CCM is running
kubectl get pods -n kube-system -l k8s-app=aws-cloud-controller-manager

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install AWS Load Balancer Controller
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=phoenix-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller

# Install EBS CSI Driver
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  -n kube-system \
  --set enableVolumeScheduling=true \
  --set enableVolumeResizing=true \
  --set enableVolumeSnapshot=true

# Create default StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
```

### Step 4: Verification

```bash
# Check all pods are running
kubectl get pods -A

# Verify nodes have providerID
kubectl get nodes -o custom-columns=NAME:.metadata.name,PROVIDER:.spec.providerID

# Test LoadBalancer service
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Wait for ALB to be created
kubectl get svc nginx -w

# Test persistent volume
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-sc
  resources:
    requests:
      storage: 10Gi
EOF

# Verify EBS volume is created
kubectl get pvc test-pvc
```

## Validation Checklist

After deployment, verify:

- [x] **Nodes Ready**: All 3 nodes show `Ready` status
- [x] **CCM Running**: `aws-cloud-controller-manager` pod in kube-system
- [x] **Provider ID**: Nodes have AWS provider ID (e.g., `aws:///us-east-1a/i-xxxxx`)
- [x] **Calico**: One calico-node pod per node
- [x] **ALB Controller**: Deployment running in kube-system
- [x] **EBS CSI**: Controller and node daemonset running
- [x] **LoadBalancer**: Test service creates ALB with public DNS
- [x] **Persistent Volume**: Test PVC creates EBS volume

## Common Issues & Solutions

### Nodes Stuck in NotReady
**Symptom**: Nodes remain NotReady for >5 minutes

**Causes**:
1. CCM not running
2. Hostname mismatch
3. IAM permissions missing

**Solution**:
```bash
# Check CCM logs
kubectl logs -n kube-system -l k8s-app=aws-cloud-controller-manager

# Verify hostname matches
aws ec2 describe-instances --instance-ids i-xxxxx --query 'Reservations[0].Instances[0].PrivateDnsName'
kubectl get nodes -o custom-columns=NAME:.metadata.name

# Check kubelet
journalctl -u kubelet -f
```

### LoadBalancer Service Stuck Pending
**Symptom**: Service stays in `<pending>` state

**Causes**:
1. ALB Controller not running
2. Subnet tags missing
3. Security group issues

**Solution**:
```bash
# Check ALB controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Verify subnet tags
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'Subnets[*].[SubnetId,Tags]'

# Check events
kubectl describe svc <service-name>
```

### PVC Stuck Pending
**Symptom**: PersistentVolumeClaim not bound

**Causes**:
1. EBS CSI driver not running
2. No pod using the PVC (WaitForFirstConsumer)
3. IAM permissions missing

**Solution**:
```bash
# Check EBS CSI driver
kubectl get pods -n kube-system | grep ebs-csi

# Create a pod to use the PVC
kubectl run test-pod --image=nginx --overrides='
{
  "spec": {
    "containers": [{
      "name": "nginx",
      "image": "nginx",
      "volumeMounts": [{
        "name": "data",
        "mountPath": "/data"
      }]
    }],
    "volumes": [{
      "name": "data",
      "persistentVolumeClaim": {
        "claimName": "test-pvc"
      }
    }]
  }
}'
```

## Cost Optimization

### Development Environment
For testing, reduce costs:
- Change instance type to `t3.medium` in `terraform/variables.tf`
- Use 1 worker instead of 2 (set `node_count = 2`)
- Stop instances when not in use:
  ```bash
  aws ec2 stop-instances --instance-ids $(terraform output -json | jq -r '.instances.value[]')
  ```

### Production Environment
- Use Auto Scaling Groups for workers
- Add monitoring (CloudWatch, Prometheus)
- Enable cluster autoscaler
- Use spot instances for non-critical workloads

## Cleanup

```bash
# Delete Kubernetes resources with LoadBalancers first
kubectl delete svc --all --all-namespaces
kubectl delete ingress --all --all-namespaces

# Wait for ALBs to be deleted (2-3 minutes)
sleep 180

# Destroy infrastructure
cd terraform
terraform destroy
```

**Important**: Delete LoadBalancer services before running `terraform destroy` to avoid orphaned ALBs.

## Advanced Configuration

### Enable Encryption at Rest
Edit `infra/terraform/ec2.tf`:
```hcl
root_block_device {
  volume_size = 50
  volume_type = "gp3"
  encrypted   = true
  kms_key_id  = aws_kms_key.k8s_key.arn
}
```

### Use Private Master
For better security, place master in private subnet:
1. Change `subnet_id` in `ec2.tf` to use `aws_subnet.private[0].id`
2. Use bastion host for SSH access
3. Update security groups to allow API access from workers only

### Add More Workers
```bash
# Edit variables.tf
node_count = 5

# Apply changes
terraform apply

# Run Ansible on new nodes only
ansible-playbook site.yml --limit workers
```

## Security Considerations

1. **SSH Access**: Restrict security group to your IP only
2. **API Access**: Consider using private API endpoint
3. **RBAC**: Configure Role-Based Access Control
4. **Network Policies**: Use Calico policies to restrict pod communication
5. **Secrets Encryption**: Enable encryption at rest for Kubernetes secrets
6. **IAM**: Follow principle of least privilege

## Monitoring & Logging

### Recommended Stack
- **Metrics**: Prometheus + Grafana
- **Logging**: EFK (Elasticsearch, Fluentd, Kibana)
- **Tracing**: Jaeger
- **APM**: Datadog or New Relic

### Quick Setup
```bash
# Install metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Install Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

## References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS Cloud Provider](https://github.com/kubernetes/cloud-provider-aws)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [EBS CSI Driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [Calico Documentation](https://docs.projectcalico.org/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Support & Contributing

For issues or improvements:
1. Check logs (kubelet, CCM, controllers)
2. Verify AWS permissions and tags
3. Review Terraform/Ansible output
4. Test connectivity and DNS resolution

## License

This infrastructure code is provided as-is for educational and production use.
