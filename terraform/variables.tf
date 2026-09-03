variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (staging | production)"
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be 'staging' or 'production'."
  }
}

variable "app_image" {
  description = "Docker image URI for the Next.js app (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/stellar-spend:latest)"
  type        = string
}

variable "app_port" {
  description = "Container port the Next.js app listens on"
  type        = number
  default     = 3000
}

variable "desired_count" {
  description = "Number of ECS task replicas"
  type        = number
  default     = 2
}

variable "cpu" {
  description = "ECS task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "ECS task memory in MiB"
  type        = number
  default     = 512
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ── Secrets (stored in AWS Secrets Manager, injected at runtime) ──────────────

variable "paycrest_api_key" {
  description = "Paycrest API key"
  type        = string
  sensitive   = true
}

variable "paycrest_webhook_secret" {
  description = "Paycrest webhook HMAC signing secret"
  type        = string
  sensitive   = true
}

variable "base_private_key" {
  description = "Private key of the Base payout wallet (hex, 0x…)"
  type        = string
  sensitive   = true
}

variable "base_return_address" {
  description = "Base address for returns / treasury routing"
  type        = string
}

variable "base_rpc_url" {
  description = "Base chain RPC provider URL"
  type        = string
}

variable "stellar_soroban_rpc_url" {
  description = "Soroban RPC endpoint"
  type        = string
  default     = "https://soroban-rpc.mainnet.stellar.gateway.fm"
}

variable "stellar_horizon_url" {
  description = "Horizon endpoint"
  type        = string
  default     = "https://horizon.stellar.org"
}

variable "stellar_usdc_issuer" {
  description = "Stellar USDC issuer account"
  type        = string
}

variable "database_url" {
  description = "PostgreSQL connection string"
  type        = string
  sensitive   = true
}

variable "sentry_dsn" {
  description = "Sentry DSN for error monitoring"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Incoming Slack webhook URL for alert notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "pagerduty_integration_url" {
  description = "PagerDuty Events v2 integration URL (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "log_group_name" {
  description = "CloudWatch Log Group to create metric filters against"
  type        = string
  default     = "/stellar-spend/production"
}

# ── CloudFront / CDN ──────────────────────────────────────────────────────────

variable "cf_price_class" {
  description = "CloudFront price class (PriceClass_100 = US/EU, PriceClass_200 = + Asia, PriceClass_All = global)"
  type        = string
  default     = "PriceClass_100"
  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cf_price_class)
    error_message = "cf_price_class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "cf_domain_aliases" {
  description = "Custom domain aliases for the CloudFront distribution (e.g. [\"cdn.example.com\"]). Leave empty to use the default *.cloudfront.net domain."
  type        = list(string)
  default     = []
}

variable "cf_acm_certificate_arn" {
  description = "ACM certificate ARN (must be in us-east-1) for custom domain aliases. Required when cf_domain_aliases is non-empty."
  type        = string
  default     = ""
}

variable "cf_origin_secret" {
  description = "Shared secret sent as X-CloudFront-Secret header to the ALB origin to restrict direct access."
  type        = string
  sensitive   = true
  default     = "change-me-in-production"
}

variable "cf_geo_restriction_type" {
  description = "Geo-restriction type: 'whitelist' or 'blacklist'. Only used when cf_geo_restriction_locations is non-empty."
  type        = string
  default     = "blacklist"
  validation {
    condition     = contains(["whitelist", "blacklist"], var.cf_geo_restriction_type)
    error_message = "cf_geo_restriction_type must be 'whitelist' or 'blacklist'."
  }
}

variable "cf_geo_restriction_locations" {
  description = "ISO 3166-1 alpha-2 country codes to whitelist or blacklist. Empty list disables geo-restrictions."
  type        = list(string)
  default     = []
}

variable "cf_invalidation_trigger" {
  description = "Bump this value (e.g. a timestamp or deploy ID) to trigger a CloudFront cache invalidation on the next terraform apply."
  type        = string
  default     = "initial"
}

variable "alarm_sns_arn" {
  description = "SNS topic ARN to receive CloudFront alarm notifications. Leave empty to disable."
  type        = string
  default     = ""
}

# ── Cost Monitoring ───────────────────────────────────────────────────────────

variable "cost_center" {
  description = "Cost center tag for cost allocation (e.g. engineering)"
  type        = string
  default     = "engineering"
}

variable "owner_email" {
  description = "Owner/team email for resource tagging"
  type        = string
  default     = "devops@stellar-spend.com"
}

variable "cost_alert_email" {
  description = "Email address to receive budget and cost anomaly alerts"
  type        = string
  default     = "devops@stellar-spend.com"
}

variable "monthly_budget_limit" {
  description = "Total monthly budget limit in USD"
  type        = number
  default     = 1000
}

variable "monthly_budget_by_service" {
  description = "Per-service monthly budget limits in USD (service name -> limit)"
  type        = map(number)
  default = {
    "Amazon Elastic Compute Cloud - Compute" = 400
    "Amazon Relational Database Service"     = 300
    "Amazon Simple Storage Service"          = 100
    "AWS Lambda"                             = 50
    "Amazon CloudFront"                      = 100
  }
}
