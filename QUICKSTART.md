# Quick Start Guide - Phoenix Kubernetes Cluster

## Prerequisites Checklist

- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] Terraform >= 1.0 installed
- [ ] Ansible >= 2.10 installed
- [ ] SSH key pair at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`
- [ ] AWS account with permissions to create VPC, EC2, IAM resources

## One-Command Deployment

```bash
cd infra
./deploy.sh
```

This automated script will:
1. Deploy infrastructure with Terraform (10-15 min)
2. Configure Kubernetes with Ansible (20-25 min)
3. Display master node IP for access

## Manual Step-by-Step

### Step 1: Deploy Infrastructure (10-15 minutes)

```bash
cd infra/terraform

# Initialize and deploy
terraform init
terraform apply

# Note the master IP
terraform output master_public_ip
```

### Step 2: Deploy Kubernetes Cluster (20-25 minutes)

```bash
cd ../ansible

# Verify connectivity
ansible all -m ping

# Deploy cluster
ansible-playbook site.yml
```

### Step 3: Access Your Cluster

```bash
# SSH to master
ssh ubuntu@<MASTER_IP>

# Verify cluster
kubectl get nodes
# All nodes should show "Ready"

# Check cloud controller
kubectl get pods -n kube-system -l k8s-app=aws-cloud-controller-manager
```

### Step 4: Install AWS Controllers (10 minutes)

```bash
# Still on master node

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install AWS Load Balancer Controller
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=phoenix-cluster \
  --set serviceAccount.create=true

# Install EBS CSI Driver
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  -n kube-system

# Create default StorageClass
kubectl apply -f - <<EOF
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

### Step 5: Test Your Cluster

#### Test LoadBalancer Service
```bash
# Create nginx deployment
kubectl create deployment nginx --image=nginx --replicas=2

# Expose as LoadBalancer
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Wait for ALB to be created (2-3 minutes)
kubectl get svc nginx -w

# Access your application
curl http://<EXTERNAL-IP>
```

#### Test Persistent Volume
```bash
# Create PVC
kubectl apply -f - <<EOF
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
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-pvc
EOF

# Verify volume is bound
kubectl get pvc test-pvc

# Verify pod is running
kubectl get pod test-pod
```

## Verification Checklist

- [ ] All 3 nodes show `Ready` status: `kubectl get nodes`
- [ ] AWS CCM pod is running: `kubectl get pods -n kube-system -l k8s-app=aws-cloud-controller-manager`
- [ ] Calico pods running (3 total): `kubectl get pods -n kube-system -l k8s-app=calico-node`
- [ ] Nodes have providerID: `kubectl get nodes -o yaml | grep providerID`
- [ ] ALB controller running: `kubectl get deployment -n kube-system aws-load-balancer-controller`
- [ ] EBS CSI running: `kubectl get pods -n kube-system | grep ebs-csi`
- [ ] LoadBalancer service gets external IP
- [ ] PVC gets bound to EBS volume

## Common Issues

### Nodes Stuck in NotReady
```bash
# Check CCM logs
kubectl logs -n kube-system -l k8s-app=aws-cloud-controller-manager

# Check kubelet logs
journalctl -u kubelet -f
```

**Solution**: Wait 5 minutes for CCM to initialize nodes. If still NotReady, verify IAM permissions.

### LoadBalancer Service Pending
```bash
# Check ALB controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

**Solution**: Verify subnet tags are correct in AWS Console.

### PVC Stuck Pending
```bash
# Check EBS CSI logs
kubectl logs -n kube-system deployment/ebs-csi-controller
```

**Solution**: Create a pod that uses the PVC (CSI uses late binding).

## Cleanup

```bash
# Delete all LoadBalancer services first
kubectl delete svc --all --all-namespaces --field-selector spec.type=LoadBalancer
kubectl delete ingress --all --all-namespaces

# Wait 3 minutes for ALBs to be deleted
sleep 180

# Destroy infrastructure
cd infra/terraform
terraform destroy
```

Or use the automated script:
```bash
cd infra
./destroy.sh
```

## Next Steps

1. **Set up monitoring**: Install Prometheus + Grafana
2. **Configure RBAC**: Create service accounts and roles
3. **Deploy your application**: Use LoadBalancer or Ingress
4. **Set up CI/CD**: Integrate with GitHub Actions or Jenkins
5. **Enable autoscaling**: Install cluster autoscaler

## Support

For detailed documentation, see:
- `infra/README.md` - Complete infrastructure guide
- `infra/ARCHITECTURE.md` - Architecture deep dive
- `infra/terraform/README.md` - Terraform specifics
- `infra/ansible/README.md` - Ansible details

## Estimated Costs

- **Base infrastructure**: ~$243/month
- **Per ALB**: ~$16/month
- **Per NLB**: ~$16/month
- **Per EBS volume (50GB)**: ~$4/month
- **Data transfer**: Varies by usage

**Development tip**: Stop EC2 instances when not in use to save ~60% on compute costs.

## Architecture Summary

```
AWS VPC (10.0.0.0/16)
├─ 3 Public Subnets (tagged for external LB)
├─ 3 Private Subnets (tagged for internal LB)
├─ Master Node (t3.large)
│  ├─ Kubernetes Control Plane
│  ├─ AWS Cloud Controller Manager
│  ├─ Calico CNI
│  └─ containerd
└─ 2 Worker Nodes (t3.large)
   ├─ Calico CNI
   ├─ containerd
   └─ Application Pods

Post-Install Controllers:
├─ AWS Load Balancer Controller (creates ALB/NLB)
└─ EBS CSI Driver (creates EBS volumes)
```

## Key Features

✅ **Native AWS Integration** - Cloud Controller Manager for AWS-specific features
✅ **Automatic Load Balancing** - Create ALBs/NLBs with simple Service/Ingress resources
✅ **Persistent Storage** - EBS volumes automatically provisioned for PVCs
✅ **Production Ready** - HA-capable architecture with proper networking
✅ **Fully Automated** - Infrastructure as Code with Terraform + Ansible
✅ **Cost Optimized** - Can scale down or use spot instances

---

**Ready to deploy?** Run `./deploy.sh` and grab a coffee! ☕
