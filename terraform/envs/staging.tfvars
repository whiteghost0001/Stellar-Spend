# terraform/envs/staging.tfvars
# Apply with: terraform apply -var-file=envs/staging.tfvars

environment = "staging"
aws_region  = "us-east-1"

# Container image — update to the staging-tagged ECR image
app_image = "123456789.dkr.ecr.us-east-1.amazonaws.com/stellar-spend:staging"

# Capacity — smaller footprint for staging
desired_count = 1
cpu           = 256
memory        = 512

# Networking
vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]

# Public / non-secret config
base_return_address     = "0xYOUR_STAGING_RETURN_ADDRESS"
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

# CDN / CloudFront
cf_price_class               = "PriceClass_100"
cf_domain_aliases            = []
cf_acm_certificate_arn       = ""
cf_geo_restriction_type      = "blacklist"
cf_geo_restriction_locations = []
cf_invalidation_trigger      = "initial"
# cf_origin_secret = set via TF_VAR_cf_origin_secret
