#!/bin/bash
set -e

echo "========================================="
echo "Phoenix Kubernetes Cluster Destruction"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning "This will destroy ALL infrastructure including:"
print_warning "  - 3 EC2 instances"
print_warning "  - VPC and networking"
print_warning "  - IAM roles and policies"
print_warning "  - All Kubernetes resources"
echo ""

read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Destruction cancelled"
    exit 0
fi

echo ""
print_warning "IMPORTANT: Cleaning up LoadBalancers first..."
echo "If you have any LoadBalancer services or Ingresses, delete them now."
echo ""

read -p "Have you deleted all LoadBalancer services and Ingresses? (yes/no): " lb_confirm
if [ "$lb_confirm" != "yes" ]; then
    print_error "Please delete LoadBalancer services first to avoid orphaned resources"
    echo ""
    echo "On master node, run:"
    echo "  kubectl delete svc --all --all-namespaces --field-selector spec.type=LoadBalancer"
    echo "  kubectl delete ingress --all --all-namespaces"
    echo ""
    echo "Then wait 2-3 minutes for ALBs to be deleted before running this script again."
    exit 1
fi

cd terraform

echo ""
print_warning "Destroying infrastructure..."
terraform destroy -auto-approve

echo ""
echo "========================================="
echo "Destruction Complete"
echo "========================================="
echo ""
echo "All resources have been destroyed."
echo ""
