#!/bin/bash
# Setup Terraform Remote Backend (S3 + DynamoDB)
# This script safely migrates Terraform state from local to remote backend

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"
BUCKET_NAME="phoenix-terraform-state-${AWS_ACCOUNT_ID}"
DYNAMODB_TABLE="phoenix-terraform-locks"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Terraform Remote Backend Setup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "S3 Bucket: $BUCKET_NAME"
echo "DynamoDB Table: $DYNAMODB_TABLE"
echo "Region: $AWS_REGION"
echo ""

# Step 1: Backup existing state
echo -e "${YELLOW}Step 1: Backing up existing Terraform state...${NC}"
if [ -f "terraform/terraform.tfstate" ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    cp terraform/terraform.tfstate "terraform/terraform.tfstate.backup.${TIMESTAMP}"
    cp terraform/terraform.tfstate.backup "terraform/terraform.tfstate.backup.backup.${TIMESTAMP}" 2>/dev/null || true
    echo -e "${GREEN}✓ State backed up to terraform.tfstate.backup.${TIMESTAMP}${NC}"
else
    echo -e "${RED}✗ No local state file found!${NC}"
    exit 1
fi

# Step 2: Create S3 bucket
echo -e "${YELLOW}Step 2: Creating S3 bucket for state storage...${NC}"
if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
    echo -e "${YELLOW}✓ Bucket already exists${NC}"
else
    aws s3api create-bucket \
        --bucket "${BUCKET_NAME}" \
        --region "${AWS_REGION}"
    echo -e "${GREEN}✓ S3 bucket created${NC}"
fi

# Step 3: Enable versioning
echo -e "${YELLOW}Step 3: Enabling versioning...${NC}"
aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled
echo -e "${GREEN}✓ Versioning enabled${NC}"

# Step 4: Enable encryption
echo -e "${YELLOW}Step 4: Enabling encryption...${NC}"
aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'
echo -e "${GREEN}✓ Encryption enabled${NC}"

# Step 5: Block public access
echo -e "${YELLOW}Step 5: Blocking public access...${NC}"
aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo -e "${GREEN}✓ Public access blocked${NC}"

# Step 6: Create DynamoDB table for locking
echo -e "${YELLOW}Step 6: Creating DynamoDB table for state locking...${NC}"
if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}" 2>/dev/null; then
    echo -e "${YELLOW}✓ DynamoDB table already exists${NC}"
else
    aws dynamodb create-table \
        --table-name "${DYNAMODB_TABLE}" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=Phoenix Key=Purpose,Value=TerraformStateLocking \
        --region "${AWS_REGION}"
    echo -e "${GREEN}✓ DynamoDB table created${NC}"
fi

# Step 7: Create backend configuration file
echo -e "${YELLOW}Step 7: Creating backend configuration...${NC}"
cat > terraform/backend.tf <<EOF
# Terraform Remote Backend Configuration
# This file configures S3 backend with DynamoDB locking

terraform {
  backend "s3" {
    bucket         = "${BUCKET_NAME}"
    key            = "phoenix-cluster/terraform.tfstate"
    region         = "${AWS_REGION}"
    encrypt        = true
    dynamodb_table = "${DYNAMODB_TABLE}"

    # Enable versioning for state recovery
    # Note: Bucket versioning must be enabled separately (already done)
  }
}
EOF
echo -e "${GREEN}✓ Backend configuration created at terraform/backend.tf${NC}"

# Step 8: Instructions for migration
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Review the backend configuration:"
echo "   cat terraform/backend.tf"
echo ""
echo "2. Initialize Terraform and migrate state:"
echo "   cd terraform"
echo "   terraform init -migrate-state"
echo ""
echo "   When prompted 'Do you want to copy existing state to the new backend?'"
echo "   Answer: yes"
echo ""
echo "3. Verify migration was successful:"
echo "   terraform state list"
echo "   aws s3 ls s3://${BUCKET_NAME}/phoenix-cluster/"
echo ""
echo "4. Test state locking:"
echo "   terraform plan  # Should acquire and release lock"
echo ""
echo -e "${GREEN}Your Terraform state will now be:${NC}"
echo "  ✓ Stored remotely in S3"
echo "  ✓ Encrypted at rest"
echo "  ✓ Versioned for recovery"
echo "  ✓ Locked during operations"
echo "  ✓ Safe for team collaboration"
echo ""
echo -e "${YELLOW}Backups created:${NC}"
ls -lh terraform/terraform.tfstate.backup.* 2>/dev/null | tail -5
echo ""
echo -e "${GREEN}Ready for production! 🚀${NC}"
