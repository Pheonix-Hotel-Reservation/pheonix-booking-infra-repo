# Phoenix Kubernetes Cluster - Architecture Documentation

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud (us-east-1)                        │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                    VPC (10.0.0.0/16)                                 ││
│  │  Tags: kubernetes.io/cluster/phoenix-cluster=shared                 ││
│  │                                                                       ││
│  │  ┌──────────────────────────────────────────────────────────┐       ││
│  │  │              Internet Gateway                             │       ││
│  │  └──────────────────────────────────────────────────────────┘       ││
│  │                           │                                           ││
│  │  ┌────────────────────────┴───────────────────────────┐             ││
│  │  │         Public Subnets (3 AZs)                      │             ││
│  │  │  Tags: kubernetes.io/role/elb=1                     │             ││
│  │  │  10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24             │             ││
│  │  │                                                      │             ││
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐   │             ││
│  │  │  │   Master   │  │  Worker-1  │  │  Worker-2  │   │             ││
│  │  │  │ t3.large   │  │  t3.large  │  │  t3.large  │   │             ││
│  │  │  │ Public IP  │  │ Public IP  │  │ Public IP  │   │             ││
│  │  │  └────────────┘  └────────────┘  └────────────┘   │             ││
│  │  │         │                │              │           │             ││
│  │  └─────────┼────────────────┼──────────────┼──────────┘             ││
│  │            │                │              │                         ││
│  │  ┌─────────┼────────────────┼──────────────┼──────────┐             ││
│  │  │  NAT Gateway (in public subnet)         │           │             ││
│  │  └─────────┼────────────────┼──────────────┼──────────┘             ││
│  │            │                │              │                         ││
│  │  ┌─────────┴────────────────┴──────────────┴──────────┐             ││
│  │  │         Private Subnets (3 AZs)                     │             ││
│  │  │  Tags: kubernetes.io/role/internal-elb=1           │             ││
│  │  │  10.0.100.0/24, 10.0.101.0/24, 10.0.102.0/24      │             ││
│  │  │  (Reserved for internal load balancers)            │             ││
│  │  └─────────────────────────────────────────────────────┘             ││
│  │                                                                       ││
│  └───────────────────────────────────────────────────────────────────── ││
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                         IAM Configuration                            ││
│  │                                                                       ││
│  │  ┌──────────────────────────────────────────────────────────┐       ││
│  │  │  IAM Role: k8s-node-role                                 │       ││
│  │  │  Attached to: All EC2 instances via instance profile     │       ││
│  │  │                                                            │       ││
│  │  │  Policies:                                                │       ││
│  │  │  ✓ AmazonEC2FullAccess                                   │       ││
│  │  │  ✓ ElasticLoadBalancingFullAccess                        │       ││
│  │  │  ✓ AmazonEBSCSIDriverPolicy (custom)                     │       ││
│  │  │  ✓ AWSLoadBalancerControllerIAMPolicy (custom)           │       ││
│  │  └──────────────────────────────────────────────────────────┘       ││
│  └───────────────────────────────────────────────────────────────────── ││
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

## Kubernetes Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Master Node (Control Plane)                       │
│                   ip-10-0-0-X.ec2.internal                               │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  Kubernetes Control Plane Components                                ││
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             ││
│  │  │ kube-apiserver│  │kube-scheduler│  │kube-controller│             ││
│  │  │   :6443      │  │   :10259     │  │  -manager     │             ││
│  │  └──────────────┘  └──────────────┘  │   :10257      │             ││
│  │                                        └──────────────┘             ││
│  │  ┌──────────────┐                                                   ││
│  │  │    etcd      │                                                   ││
│  │  │  :2379-2380  │                                                   ││
│  │  └──────────────┘                                                   ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  AWS Cloud Controller Manager (DaemonSet)                           ││
│  │  - Removes node.cloudprovider.kubernetes.io/uninitialized taint     ││
│  │  - Sets node providerID (aws:///us-east-1a/i-xxxxx)                ││
│  │  - Manages node lifecycle and metadata                              ││
│  │  - Integrates with AWS APIs for zone/instance info                  ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  Calico CNI                                                          ││
│  │  - Pod network: 192.168.0.0/16                                      ││
│  │  - BGP for routing (port 179)                                       ││
│  │  - VXLAN for overlay (port 4789)                                    ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  Container Runtime                                                   ││
│  │  - containerd with systemd cgroup                                   ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  Kubelet                                                             ││
│  │  - Flags: --cloud-provider=external                                 ││
│  │  - Port: 10250                                                       ││
│  └─────────────────────────────────────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                      Worker Nodes (2 replicas)                           │
│           ip-10-0-1-X.ec2.internal, ip-10-0-2-X.ec2.internal            │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  Calico CNI                                                          ││
│  │  Container Runtime (containerd)                                      ││
│  │  Kubelet (--cloud-provider=external)                                ││
│  │  kube-proxy                                                          ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  Application Pods                                                    ││
│  │  (Your workloads run here)                                          ││
│  └─────────────────────────────────────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────────────────┘
```

## Post-Installation Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                  AWS Load Balancer Controller                            │
│                        (Installed via Helm)                               │
│                                                                           │
│  Deployment in kube-system namespace                                     │
│  - Watches: Service (type: LoadBalancer), Ingress resources             │
│  - Creates: ALB (Ingress), NLB (LoadBalancer service)                   │
│  - Uses: Subnet tags to select subnets                                  │
│  - Manages: Security groups, target groups, listeners                   │
│                                                                           │
│  When you create:                                                        │
│  ┌──────────────────────┐      Creates       ┌──────────────────────┐  │
│  │ Service              │  ─────────────────> │ AWS Network Load     │  │
│  │ type: LoadBalancer   │                     │ Balancer (NLB)       │  │
│  └──────────────────────┘                     └──────────────────────┘  │
│                                                                           │
│  ┌──────────────────────┐      Creates       ┌──────────────────────┐  │
│  │ Ingress              │  ─────────────────> │ AWS Application Load │  │
│  │ with annotations     │                     │ Balancer (ALB)       │  │
│  └──────────────────────┘                     └──────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                      EBS CSI Driver                                       │
│                    (Installed via Helm)                                   │
│                                                                           │
│  Components:                                                              │
│  - Controller: Deployment (creates/deletes/attaches volumes)             │
│  - Node Plugin: DaemonSet (mounts volumes on nodes)                      │
│                                                                           │
│  When you create:                                                        │
│  ┌──────────────────────┐      Creates       ┌──────────────────────┐  │
│  │ PersistentVolumeClaim│  ─────────────────> │ AWS EBS Volume       │  │
│  │ storageClass: ebs-sc │                     │ (GP3, encrypted)     │  │
│  └──────────────────────┘                     └──────────────────────┘  │
│                                                                           │
│  StorageClass: ebs-sc (default)                                          │
│  - Provisioner: ebs.csi.aws.com                                          │
│  - Type: GP3                                                              │
│  - Encryption: Enabled                                                   │
│  - Binding: WaitForFirstConsumer (waits for pod scheduling)              │
└───────────────────────────────────────────────────────────────────────────┘
```

## Network Flow

### External Traffic to Application

```
Internet
   │
   ▼
Application Load Balancer (ALB)
Created by AWS Load Balancer Controller
   │
   ▼
Target Group
(Pod IPs registered automatically)
   │
   ▼
Pod in Calico Network (192.168.x.x)
   │
   ▼
Application Container
```

### Pod-to-Pod Communication

```
Pod A (192.168.1.5)
   │
   ▼
Calico vRouter (on Worker-1)
   │
   ▼
BGP Route Advertisement
   │
   ▼
Calico vRouter (on Worker-2)
   │
   ▼
Pod B (192.168.2.10)
```

### Persistent Storage Flow

```
Pod requests PVC
   │
   ▼
EBS CSI Controller
   │
   ▼
AWS EBS API (creates volume via IAM role)
   │
   ▼
EBS Volume attached to EC2 instance
   │
   ▼
EBS CSI Node Plugin mounts volume
   │
   ▼
Pod sees filesystem at /data
```

## Critical Configuration Points

### 1. Cloud Provider Mode
```
┌─────────────────────────────────────────────────────────┐
│                 Legacy (Deprecated)                      │
│  kubeadm init --cloud-provider=aws                      │
│  kubelet --cloud-provider=aws                           │
│  ❌ Limited features, deprecated                         │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│             Modern (External - This Setup)               │
│  kubeadm init (no cloud-provider flag)                  │
│  kubelet --cloud-provider=external                      │
│  + AWS Cloud Controller Manager DaemonSet              │
│  ✅ Full feature support, actively maintained           │
└─────────────────────────────────────────────────────────┘
```

### 2. Hostname Configuration
```
EC2 Instance Metadata:
  Private DNS: ip-10-0-1-50.ec2.internal
               │
               ▼
Set via user-data script at boot:
  hostnamectl set-hostname ip-10-0-1-50.ec2.internal
               │
               ▼
Kubelet registers with this hostname:
  kubectl get nodes
  NAME                          STATUS
  ip-10-0-1-50.ec2.internal    Ready
               │
               ▼
CCM matches to EC2 instance and sets providerID:
  aws:///us-east-1a/i-0abc123def456789
```

### 3. Tag Propagation for Discovery

```
Terraform applies tags to AWS resources
   │
   ▼
┌──────────────────────────────────────────────────────────┐
│ VPC: kubernetes.io/cluster/phoenix-cluster=shared        │
│ Subnets: kubernetes.io/cluster/phoenix-cluster=shared    │
│          kubernetes.io/role/elb=1 (public)               │
│          kubernetes.io/role/internal-elb=1 (private)     │
│ EC2: kubernetes.io/cluster/phoenix-cluster=owned         │
└──────────────────────────────────────────────────────────┘
   │
   ▼
AWS Load Balancer Controller queries AWS API
   │
   ▼
Selects subnets based on tags
   │
   ▼
Creates ALB/NLB in correct subnets
```

## Deployment Timeline

```
Terraform Apply (10-15 min)
   ├─ VPC & Networking (2 min)
   ├─ IAM Roles & Policies (1 min)
   └─ EC2 Instances (5 min)
   └─ Wait for instances ready (5 min)
   │
   ▼
Ansible Common Role (5 min per node = 15 min total)
   ├─ Set hostname to EC2 Private DNS
   ├─ Install containerd
   ├─ Install kubelet, kubeadm, kubectl
   ├─ Configure kubelet with --cloud-provider=external
   └─ Start kubelet (will stay in NotReady until CCM)
   │
   ▼
Ansible Master Role (10 min)
   ├─ kubeadm init with pod network CIDR
   ├─ Install Calico CNI (3 min)
   ├─ Install AWS CCM (2 min)
   │  └─ CCM removes node taints
   │  └─ Master becomes Ready
   ├─ Generate join token
   └─ Wait for master to be Ready
   │
   ▼
Ansible Worker Role (5 min per worker)
   ├─ Execute join command
   ├─ Kubelet starts
   ├─ CCM processes new node
   └─ Worker becomes Ready
   │
   ▼
Manual: Install Controllers (10 min)
   ├─ Install Helm (1 min)
   ├─ Install AWS Load Balancer Controller (5 min)
   └─ Install EBS CSI Driver (4 min)
   │
   ▼
Cluster Ready for Production Workloads
```

## Security Architecture

### IAM Permission Flow
```
Pod needs to create EBS volume
   │
   ▼
EBS CSI Driver Controller (running on node)
   │
   ▼
EC2 Instance Profile credentials
   │
   ▼
IAM Role: k8s-node-role
   │
   ▼
IAM Policy: AmazonEBSCSIDriverPolicy
   │
   ▼
AWS EBS API (ec2:CreateVolume)
   │
   ▼
EBS Volume created
```

### Network Security
```
┌───────────────────────────────────────────────────────┐
│ Security Group: phoenix-cluster-nodes-sg              │
│                                                        │
│ Ingress Rules:                                        │
│  - 22 (SSH): 0.0.0.0/0                               │
│  - 6443 (API): 0.0.0.0/0                             │
│  - 2379-2380 (etcd): Self                            │
│  - 10250 (kubelet): Self                             │
│  - 10257 (controller-manager): Self                  │
│  - 10259 (scheduler): Self                           │
│  - 30000-32767 (NodePort): 0.0.0.0/0                │
│  - 179 (BGP): Self                                   │
│  - 4789 (VXLAN): Self                                │
│  - ALL: Self (for pod-to-pod)                        │
│                                                        │
│ Egress Rules:                                         │
│  - ALL: 0.0.0.0/0                                    │
└───────────────────────────────────────────────────────┘
```

## Disaster Recovery

### Backup Strategy
```
Critical Components to Backup:
1. etcd snapshots (kubeadm etcd snapshot)
2. Terraform state (S3 backend recommended)
3. Application PVCs (EBS snapshots via CSI)
4. Cluster configuration (kubectl export)
```

### Recovery Procedure
```
1. Restore VPC & IAM (terraform apply)
2. Restore etcd from snapshot
3. Rejoin worker nodes
4. Restore PVCs from EBS snapshots
5. Redeploy applications
```

## Monitoring Points

```
Infrastructure Level (AWS CloudWatch):
├─ EC2 CPU/Memory/Disk
├─ VPC Flow Logs
├─ ELB Metrics (request count, latency)
└─ EBS IOPS/Throughput

Kubernetes Level (Prometheus):
├─ Node metrics (kubelet)
├─ Pod metrics (cAdvisor)
├─ API server metrics
├─ etcd metrics
└─ Controller metrics (CCM, ALB, EBS)

Application Level:
├─ Custom metrics (Prometheus exporters)
├─ Logs (Fluentd → CloudWatch/S3)
└─ Traces (Jaeger/X-Ray)
```

## Cost Breakdown (Monthly Estimate)

```
EC2 Instances:
  3 × t3.large (0.0832/hr × 730hr) = $182/month

EBS Volumes:
  3 × 50GB GP3 ($0.08/GB) = $12/month

VPC:
  NAT Gateway ($0.045/hr × 730hr) = $33/month
  Data transfer (varies)

Load Balancers:
  ALB ($0.0225/hr × 730hr) = $16/month (per ALB)
  NLB ($0.0225/hr × 730hr) = $16/month (per NLB)

Total Base Infrastructure: ~$243/month
+ Load Balancers (as created)
+ Data Transfer (as used)
+ Additional EBS volumes (as created)
```

## Conclusion

This architecture provides a production-ready Kubernetes cluster on AWS with:
- **Native AWS integration** via Cloud Controller Manager
- **Load balancing** via AWS Load Balancer Controller
- **Persistent storage** via EBS CSI Driver
- **Network isolation** via VPC and security groups
- **High availability** potential (can expand to multi-master)
- **Cost optimization** options (spot instances, autoscaling)

The key innovation is using **external cloud provider mode** which enables modern AWS integrations that the legacy in-tree provider cannot support.
