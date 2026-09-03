terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  backend "s3" {
    # Configure via -backend-config or environment variables:
    # TF_VAR_bucket, TF_VAR_key, TF_VAR_region
    # Example:
    #   terraform init \
    #     -backend-config="bucket=my-tfstate" \
    #     -backend-config="key=stellar-spend/terraform.tfstate" \
    #     -backend-config="region=us-east-1" \
    #     -backend-config="dynamodb_table=terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "stellar-spend"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
