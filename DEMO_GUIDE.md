# Phoenix Infrastructure - 15-Minute Demo Guide

## Quick Demo Script for Examiners

This is your cheat sheet for demonstrating the complete infrastructure in 15 minutes.

---

## Setup (Before Demo)

```bash
# 1. Have these tabs open in browser:
- ArgoCD: https://argocd.phoenix-project.online
- Grafana: https://grafana.phoenix-project.online
- Harbor: https://harbor.phoenix-project.online
- GitHub Config Repo

# 2. Have terminal ready with kubectl configured
kubectl config current-context
# Should show: phoenix-cluster

# 3. Optional: Start screen recording
```

---

## PART 1: Infrastructure Overview (3 minutes)

### Show the Code Structure

```bash
# Show repository organization
tree -L 2 -I 'node_modules|.git'

# Highlight key files
cat terraform/variables.tf | head -20
cat ansible/group_vars/all.yml
```

**Say:** "This infrastructure uses Terraform for AWS resources and Ansible for Kubernetes configuration. Everything is parameterized and version-controlled."

### Show Running Infrastructure

```bash
# AWS Resources
terraform state list | grep aws

# Count resources
terraform state list | wc -l
```

**Say:** "We have 26 AWS resources managed by Terraform - VPC, subnets, security groups, and 4 EC2 instances."

---

## PART 2: Kubernetes Cluster (3 minutes)

### Cluster Health

```bash
# Show all nodes
kubectl get nodes -o wide

# Show resource usage
kubectl top nodes
```

**Say:** "We have a 4-node cluster: 1 master (t3.large) and 3 workers (t3.xlarge). All nodes are healthy and running Kubernetes 1.29."

### Show All Namespaces

```bash
# List namespaces
kubectl get ns

# Count total pods
kubectl get pods -A --no-headers | wc -l
```

**Say:** "We're running about 60 pods across multiple namespaces - applications, platform tools, and system components."

---

## PART 3: Platform Components (3 minutes)

### ArgoCD (GitOps)

**Browser:** Open ArgoCD UI

```bash
# Show applications
kubectl get applications -n argocd

# Or via CLI
argocd app list
```

**Say:** "ArgoCD manages all our deployments via GitOps. Every application syncs from Git automatically. Notice all apps are 'Synced' and 'Healthy'."

**Click on one application** to show the resource tree.

### Monitoring Stack

**Browser:** Open Grafana

```bash
# Show monitoring pods
kubectl get pods -n monitoring
```

**Say:** "Prometheus collects metrics from all pods. Grafana provides pre-built dashboards."

**Show dashboards:**
1. Kubernetes / Compute Resources / Cluster
2. Kubernetes / Compute Resources / Namespace (Pods)

### Istio Service Mesh

```bash
# Show Istio components
kubectl get pods -n istio-system

# Show gateway
kubectl get gateway -A
```

**Say:** "Istio provides service mesh capabilities - traffic management, mTLS between services, and observability."

---

## PART 4: Application Demo (4 minutes)

### Show Microservices

```bash
# Show deployments (adjust namespace if different)
kubectl get deployments -A | grep -E 'booking|room|payment|notification'

# Show one in detail
kubectl describe deployment <booking-service> -n <namespace>
```

**Say:** "Our hotel booking system runs as microservices: booking service, room service, payment service, and notification service."

### Make a Live API Call

```bash
# Health check endpoint
curl https://api.phoenix-project.online/health

# Or test booking endpoint (if available)
curl -X POST https://api.phoenix-project.online/api/v1/bookings \
  -H "Content-Type: application/json" \
  -d '{
    "roomId": "101",
    "guestName": "Demo User",
    "checkIn": "2025-12-20",
    "checkOut": "2025-12-22"
  }'
```

**Say:** "This API call goes through AWS ALB -> Istio Ingress -> Service Mesh -> Booking Service -> Database. All traffic is encrypted with TLS and mTLS."

### Watch Logs in Real-Time

```bash
# Stream logs from booking service
kubectl logs -f deployment/<booking-service> -n <namespace> | tail -20
```

**Say:** "We can see the request flowing through the system in real-time. All logs are centralized in OpenSearch."

---

## PART 5: GitOps Workflow (2 minutes)

### Show Config Repository

**Browser:** Open GitHub config repo

**Say:** "All application configurations live in Git. When we commit changes, ArgoCD automatically deploys them."

### Live Change Demo (if time permits)

**Browser:** Edit a file on GitHub

```yaml
# Example: Change replicas in values.yaml
replicas: 3  →  replicas: 5
```

**Commit directly via GitHub UI**

**Terminal:** Watch the change

```bash
# Watch pods being created
kubectl get pods -n <namespace> -w

# Or watch in ArgoCD
argocd app get <app-name> --refresh
```

**Say:** "Within 3 minutes, ArgoCD detected the change and scaled the deployment automatically. No manual kubectl apply needed."

---

## PART 6: Resilience & Auto-Healing (Optional, if time)

### Kill a Pod

```bash
# Delete a pod
kubectl delete pod <pod-name> -n <namespace>

# Watch it recreate
kubectl get pods -n <namespace> -w
```

**Say:** "Kubernetes automatically recreates failed pods. The deployment maintains the desired state."

### Show Auto-Scaling

```bash
# Show HPA configuration
kubectl get hpa -A

# Describe one
kubectl describe hpa <hpa-name> -n <namespace>
```

**Say:** "We have horizontal pod autoscalers configured. When CPU exceeds 70%, new pods are automatically created."

---

## BONUS: Advanced Features (If Asked)

### Security - Vault & Secrets

```bash
# Show Vault status
kubectl exec -n vault platform-vault-0 -- vault status

# Show external secrets
kubectl get externalsecrets -A
```

**Say:** "We use HashiCorp Vault for secrets management. Application secrets are never stored in Git or Kubernetes directly."

### Service Mesh - Istio

```bash
# Show virtual services
kubectl get virtualservices -A

# Show destination rules
kubectl get destinationrules -A
```

**Say:** "Istio manages traffic routing, retries, circuit breakers, and A/B testing capabilities."

### Container Registry - Harbor

**Browser:** Open Harbor UI

**Say:** "We run our own private container registry with vulnerability scanning. All images are scanned before deployment."

---

## Common Examiner Questions & Answers

### Q: "Why Kubernetes instead of ECS/EKS?"

**A:** "This demonstrates deeper infrastructure knowledge. We manage the control plane, understand how kubeadm works, and have full control over cluster configuration. It's more complex but shows architectural understanding."

### Q: "How do you handle disaster recovery?"

**A:** "We have:
- Terraform state allows recreating infrastructure
- Ansible playbooks can rebuild cluster
- ArgoCD syncs all apps from Git
- Velero (planned) for cluster backups
- Multi-AZ deployment for availability"

### Q: "What about security?"

**A:** "Multiple layers:
- Network policies between namespaces
- Istio mTLS between all services
- Vault for secrets (never in Git)
- RBAC for cluster access
- Security groups at AWS level
- Container scanning in Harbor"

### Q: "How do you monitor this?"

**A:** "Complete observability:
- Prometheus scrapes metrics from all pods
- Grafana dashboards for visualization
- OpenSearch for centralized logging
- Istio for distributed tracing
- Alerts configured for critical issues"

### Q: "What if a node fails?"

**A:** "Kubernetes reschedules pods to healthy nodes automatically. We have:
- 3 worker nodes for redundancy
- Pod anti-affinity rules
- Health checks (liveness & readiness)
- Auto-recovery within minutes"

### Q: "How do you deploy new versions?"

**A:** "GitOps workflow:
1. Developer commits code
2. CI builds Docker image
3. CI updates config repo
4. ArgoCD detects change
5. Rolling update deployed
6. Istio can do canary (10% → 100%)"

### Q: "What's the total cost?"

**A:** "Approximately $450/month:
- 1x t3.large: ~$60
- 3x t3.xlarge: ~$300
- EBS volumes: ~$50
- Data transfer: ~$40
- This is development cluster - production would use reserved instances"

---

## Emergency Commands (If Something Fails During Demo)

### Pod Not Running

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
```

### Service Not Accessible

```bash
kubectl get svc -A
kubectl get ingress -A
kubectl get gateway -A
```

### Node Issues

```bash
kubectl describe node <node-name>
ssh -i ~/.ssh/id_rsa ubuntu@<node-ip>
sudo systemctl status kubelet
```

### ArgoCD Sync Issues

```bash
argocd app get <app-name>
argocd app sync <app-name> --force
```

---

## Closing Statement

**Say:** "This infrastructure demonstrates:
- ✅ Infrastructure as Code (Terraform)
- ✅ Configuration Management (Ansible)
- ✅ Container Orchestration (Kubernetes)
- ✅ GitOps (ArgoCD)
- ✅ Service Mesh (Istio)
- ✅ Observability (Prometheus/Grafana/OpenSearch)
- ✅ Security (Vault, mTLS, RBAC)
- ✅ CI/CD Integration

It's production-ready with room for enhancements like multi-region deployment and automated backups."

---

## Quick Reference

| What | Command |
|------|---------|
| All nodes | `kubectl get nodes -o wide` |
| All pods | `kubectl get pods -A` |
| Pod logs | `kubectl logs -f <pod> -n <ns>` |
| ArgoCD apps | `argocd app list` |
| Sync app | `argocd app sync <app>` |
| Grafana port-forward | `kubectl port-forward -n monitoring svc/grafana 3000:80` |
| Resource usage | `kubectl top nodes` |
| Describe anything | `kubectl describe <resource> <name> -n <ns>` |

---

**Good luck with your demonstration!**
