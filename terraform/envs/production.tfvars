# terraform/envs/production.tfvars
# Apply with: terraform apply -var-file=envs/production.tfvars

environment = "production"
aws_region  = "us-east-1"

# Container image — update to the production-tagged ECR image
app_image = "123456789.dkr.ecr.us-east-1.amazonaws.com/stellar-spend:latest"

# Capacity — HA configuration for production
desired_count = 2
cpu           = 512
memory        = 1024

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

# Public / non-secret config
base_return_address     = "0xYOUR_PRODUCTION_RETURN_ADDRESS"
base_rpc_url            = "https://mainnet.base.org"
stellar_soroban_rpc_url = "https://soroban-rpc.mainnet.stellar.gateway.fm"
stellar_horizon_url     = "https://horizon.stellar.org"
stellar_usdc_issuer     = "GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN"

# Secrets — supply via TF_VAR_* environment variables or a secrets backend.
# Do NOT commit real values here.
# paycrest_api_key        = set via TF_VAR_paycrest_api_key
# paycrest_webhook_secret = set via TF_VAR_paycrest_webhook_secret
# base_private_key        = set via TF_VAR_base_private_key
# database_url            = set via TF_VAR_database_url
