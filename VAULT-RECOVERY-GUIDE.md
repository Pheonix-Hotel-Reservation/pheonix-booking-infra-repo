# Vault Recovery Guide - Post K8s Upgrade

## Executive Summary

After upgrading Kubernetes from v1.29 to v1.34, Vault's Kubernetes authentication stopped working. This guide documents the issue, what was fixed, and the remaining recovery steps.

## ✅ What Was Successfully Completed

1. **Kubernetes Cluster Upgrade**: Successfully upgraded from v1.29.15 to v1.34.3
   - Control plane: v1.34.3
   - Worker nodes: v1.34.3

2. **AWS IAM Permissions Fixed**: Added `kms:Decrypt` permission to IAM user `secrets-handler`
   - Policy: `arn:aws:iam::787169320414:policy/Secrets-Store-K8s-user` (v3)
   - Permissions added: `kms:Decrypt`, `kms:Encrypt`, `kms:DescribeKey`
   - KMS Key: `arn:aws:kms:us-east-1:787169320414:key/2a6d70ce-261f-4124-b0bf-7a2f6acd5410`

3. **Vault Auto-Unseal Working**: Vault successfully auto-unseals using AWS KMS
   - Vault status: Unsealed ✓
   - Vault version: 1.20.4
   - HA Mode: Enabled with 2 replicas

## ❌ Current Issue

**Vault Kubernetes Auth Not Working**
- Error: `403 - permission denied` when external-secrets tries to authenticate
- Impact: External-secrets cannot fetch secrets from Vault
- Cascading effect: OpenSearch and other apps cannot start (missing secrets)

## 🔑 Root Cause

Vault's Kubernetes auth backend configuration needs to be reconfigured after:
1. Vault pods were restarted
2. Kubernetes was upgraded to v1.34

The Kubernetes API server endpoint or service account token reviewer in Vault may be stale.

## 📋 Recovery Process

### Step 1: Get Vault Root Token

A root token generation process has been **STARTED** with the following details:

```
Nonce: 316e301d-31f0-c095-0ece-a02b031567d4
OTP: n0VuQ9mFu0LDwgZeCYdO6xgUP2y2
Recovery Keys Required: 1 (only one key needed)
```

#### Option A: If you have the recovery key

Run this command and enter your recovery key when prompted:

```bash
ssh -i ~/.ssh/id_rsa ubuntu@98.84.34.188 \
  "kubectl exec -n vault platform-vault-0 -- \
  vault operator generate-root \
  -nonce=316e301d-31f0-c095-0ece-a02b031567d4"
```

This will output an encoded root token. Decode it using:

```bash
ssh -i ~/.ssh/id_rsa ubuntu@98.84.34.188 \
  "kubectl exec -n vault platform-vault-0 -- \
  vault operator generate-root \
  -decode=<ENCODED_TOKEN> \
  -otp=n0VuQ9mFu0LDwgZeCYdO6xgUP2y2"
```

#### Option B: If you have the existing root token

Check these locations:
- Team password manager (1Password, LastPass, etc.)
- AWS Secrets Manager (other secrets)
- Initial setup documentation
- Secure notes from when Vault was first installed
- Ask team member who initially set up Vault

#### Option C: Access Vault UI

If you have any valid Vault credentials:

```bash
ssh -i ~/.ssh/id_rsa ubuntu@98.84.34.188 \
  "kubectl port-forward -n vault svc/platform-vault 8200:8200"
```

Then access: http://localhost:8200

### Step 2: Run Recovery Script

Once you have the root token, run:

```bash
cd /Users/theenukabandara/Desktop/Final-phoenix/pheonix-booking-infra-repo
./fix-vault-k8s-auth.sh <YOUR_VAULT_ROOT_TOKEN>
```

This script will:
1. Get Kubernetes cluster information (API server, CA cert)
2. Create a service account token for Vault
3. Enable and configure Kubernetes auth in Vault
4. Create external-secrets policy
5. Create Kubernetes auth role for external-secrets

### Step 3: Verify Recovery

After running the script, verify:

```bash
# 1. Check external-secrets operator restarted
ssh -i ~/.ssh/id_rsa ubuntu@98.84.34.188 \
  "kubectl rollout restart deployment external-secrets -n platform-system"

# 2. Check ClusterSecretStore status (should be "Ready: True")
ssh -i ~/.ssh/id_rsa ubuntu@98.84.34.188 \
  "kubectl get clustersecretstore vault-cluster-store"

# 3. Check external secrets are syncing
ssh -i ~/.ssh/id_rsa ubuntu@98.84.34.188 \
  "kubectl get externalsecrets -A"

# 4. Check OpenSearch pods (should start within a few minutes)
ssh -i ~/.ssh/id_rsa ubuntu@98.84.34.188 \
  "kubectl get pods -n opensearch"

# 5. Check ArgoCD apps
ssh -i ~/.ssh/id_rsa ubuntu@98.84.34.188 \
  "kubectl get applications -n argocd"
```

## 🔍 Technical Details

### Vault Configuration
- **Seal Type**: AWS KMS auto-unseal
- **Storage Backend**: Raft (persistent across restarts)
- **HA**: 2 replicas (`platform-vault-0`, `platform-vault-1`)
- **KMS Key ID**: `2a6d70ce-261f-4124-b0bf-7a2f6acd5410` (for auto-unseal)

### Kubernetes Auth Details
- **Auth Path**: `/auth/kubernetes`
- **Role**: `eso-role`
- **Service Account**: `eso-vault-auth` (namespace: `platform-system`)
- **Bound Namespaces**: `platform-system`

### External Secrets Configuration
- **Operator**: Running in `platform-system` namespace
- **ClusterSecretStore**: `vault-cluster-store`
- **Vault Endpoint**: `http://platform-vault-internal.vault.svc.cluster.local:8200`

## 📞 Need Help?

If you're stuck:

1. **Can't find recovery keys**: Check with team members who set up the infrastructure initially
2. **Script fails**: Check the error message - it will indicate which step failed
3. **Vault still not working**: Verify Vault is unsealed: `kubectl exec -n vault platform-vault-0 -- vault status`

## 📝 For Future Reference

**Save these somewhere secure**:
- Vault root token (once recovered)
- Vault recovery keys
- This recovery guide

**Best practices**:
1. Store Vault credentials in a secure password manager
2. Document Vault initialization process
3. Keep recovery keys separate from root token
4. Test disaster recovery procedures regularly

---

**Created**: December 14, 2025
**Cluster**: phoenix-cluster (AWS us-east-1)
**Kubernetes Version**: 1.34.3
**Vault Version**: 1.20.4
