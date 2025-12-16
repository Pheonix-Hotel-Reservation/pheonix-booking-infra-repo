#!/bin/bash
#
# Vault Kubernetes Auth Recovery Script
# This script reconfigures Vault's Kubernetes auth after a restart/upgrade
#
# Usage: ./fix-vault-k8s-auth.sh <VAULT_ROOT_TOKEN>
#

set -e

if [ -z "$1" ]; then
    echo "Error: Vault root token required"
    echo "Usage: $0 <VAULT_ROOT_TOKEN>"
    exit 1
fi

VAULT_TOKEN="$1"
MASTER_IP="98.84.34.188"

echo "========================================="
echo "Vault Kubernetes Auth Recovery Script"
echo "========================================="
echo ""

# Get Kubernetes cluster information
echo "[1/6] Getting Kubernetes cluster information..."
K8S_HOST=$(ssh -i ~/.ssh/id_rsa ubuntu@${MASTER_IP} "kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.server}'")
K8S_CA_CERT=$(ssh -i ~/.ssh/id_rsa ubuntu@${MASTER_IP} "kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d")

echo "  Kubernetes API: $K8S_HOST"
echo ""

# Get service account token
echo "[2/6] Getting service account JWT token..."
SA_JWT_TOKEN=$(ssh -i ~/.ssh/id_rsa ubuntu@${MASTER_IP} "kubectl create token eso-vault-auth -n platform-system --duration=87600h")

if [ -z "$SA_JWT_TOKEN" ]; then
    echo "  Error: Failed to get service account token"
    exit 1
fi
echo "  Token retrieved successfully"
echo ""

# Configure Kubernetes auth in Vault
echo "[3/6] Enabling Kubernetes auth method in Vault..."
ssh -i ~/.ssh/id_rsa ubuntu@${MASTER_IP} "kubectl exec -n vault platform-vault-0 -- env VAULT_TOKEN=${VAULT_TOKEN} vault auth enable -path=kubernetes kubernetes 2>/dev/null || echo '  Auth method already enabled'"
echo ""

echo "[4/6] Configuring Kubernetes auth backend..."
ssh -i ~/.ssh/id_rsa ubuntu@${MASTER_IP} bash << EOF
kubectl exec -n vault platform-vault-0 -- env VAULT_TOKEN=${VAULT_TOKEN} vault write auth/kubernetes/config \
    kubernetes_host="${K8S_HOST}" \
    kubernetes_ca_cert="\$(echo '${K8S_CA_CERT}' | tr -d '\n')" \
    token_reviewer_jwt="${SA_JWT_TOKEN}"
EOF
echo "  Kubernetes auth configured"
echo ""

# Create policy for external-secrets
echo "[5/6] Creating external-secrets policy..."
ssh -i ~/.ssh/id_rsa ubuntu@${MASTER_IP} bash << 'EOF'
kubectl exec -n vault platform-vault-0 -- env VAULT_TOKEN=${VAULT_TOKEN} vault policy write external-secrets-policy - << 'POLICY'
# Allow reading all secrets under kv/
path "kv/data/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/*" {
  capabilities = ["read", "list"]
}

# Allow reading all secrets under secret/
path "secret/data/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
POLICY
EOF
echo "  Policy created"
echo ""

# Create Kubernetes auth role for external-secrets
echo "[6/6] Creating Kubernetes auth role for external-secrets..."
ssh -i ~/.ssh/id_rsa ubuntu@${MASTER_IP} "kubectl exec -n vault platform-vault-0 -- env VAULT_TOKEN=${VAULT_TOKEN} vault write auth/kubernetes/role/eso-role \
    bound_service_account_names=eso-vault-auth \
    bound_service_account_namespaces=platform-system \
    policies=external-secrets-policy \
    ttl=24h"
echo "  Role created"
echo ""

echo "========================================="
echo "Configuration Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Restart external-secrets operator:"
echo "   ssh -i ~/.ssh/id_rsa ubuntu@${MASTER_IP} \"kubectl rollout restart deployment external-secrets -n platform-system\""
echo ""
echo "2. Check ClusterSecretStore status:"
echo "   ssh -i ~/.ssh/id_rsa ubuntu@${MASTER_IP} \"kubectl get clustersecretstore vault-cluster-store\""
echo ""
echo "3. Verify secrets are syncing:"
echo "   ssh -i ~/.ssh/id_rsa ubuntu@${MASTER_IP} \"kubectl get externalsecrets -A\""
echo ""
echo "4. Check OpenSearch pods:"
echo "   ssh -i ~/.ssh/id_rsa ubuntu@${MASTER_IP} \"kubectl get pods -n opensearch\""
echo ""
