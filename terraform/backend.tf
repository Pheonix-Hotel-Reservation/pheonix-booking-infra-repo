# Terraform Remote Backend Configuration
# This file configures S3 backend with DynamoDB locking

terraform {
  backend "s3" {
    bucket         = "phoenix-terraform-state-787169320414"
    key            = "phoenix-cluster/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "phoenix-terraform-locks"

    # Enable versioning for state recovery
    # Note: Bucket versioning must be enabled separately (already done)
  }
}
