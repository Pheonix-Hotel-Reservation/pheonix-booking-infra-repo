#!/bin/bash
set -e

echo "========================================="
echo "Phoenix Kubernetes Cluster Deployment"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed"
    exit 1
fi
print_status "Terraform found"

if ! command -v ansible &> /dev/null; then
    print_error "Ansible is not installed"
    exit 1
fi
print_status "Ansible found"

if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed"
    exit 1
fi
print_status "AWS CLI found"

if [ ! -f ~/.ssh/id_rsa.pub ]; then
    print_error "SSH public key not found at ~/.ssh/id_rsa.pub"
    print_warning "Generate one with: ssh-keygen -t rsa -b 4096"
    exit 1
fi
print_status "SSH key found"

echo ""
echo "========================================="
echo "Step 1: Deploy Infrastructure (Terraform)"
echo "========================================="
echo ""

cd terraform

# Initialize Terraform
print_status "Initializing Terraform..."
terraform init

# Plan
print_status "Creating execution plan..."
terraform plan -out=tfplan

# Apply
echo ""
read -p "Deploy infrastructure? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    print_warning "Deployment cancelled"
    exit 0
fi

print_status "Deploying infrastructure..."
terraform apply tfplan

print_status "Infrastructure deployed successfully"
echo ""

# Get outputs
MASTER_IP=$(terraform output -raw master_public_ip)
print_status "Master IP: $MASTER_IP"

echo ""
echo "========================================="
echo "Step 2: Configure Kubernetes (Ansible)"
echo "========================================="
echo ""

cd ../ansible

# Wait for instances to be ready
print_status "Waiting for instances to be ready (60 seconds)..."
sleep 60

# Test connectivity
print_status "Testing SSH connectivity..."
if ! ansible all -m ping > /dev/null 2>&1; then
    print_error "Cannot connect to instances"
    print_warning "Trying again in 30 seconds..."
    sleep 30
    if ! ansible all -m ping; then
        print_error "Still cannot connect. Check security groups and SSH key"
        exit 1
    fi
fi
print_status "All instances are reachable"

# Deploy cluster
print_status "Deploying Kubernetes cluster (this will take 20-25 minutes)..."
ansible-playbook site.yml

print_status "Kubernetes cluster deployed successfully"
echo ""

echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Master Node IP: $MASTER_IP"
echo ""
echo "Next steps:"
echo "1. SSH to master: ssh ubuntu@$MASTER_IP"
echo "2. Verify cluster: kubectl get nodes"
echo "3. Install controllers: helm install ..."
echo ""
echo "See infra/README.md for detailed post-installation steps."
echo ""
