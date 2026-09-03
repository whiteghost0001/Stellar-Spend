# Terraform Modules

The `terraform/modules/` directory contains reusable, independently testable modules. The root `terraform/` directory composes them.

## Modules

### `modules/network`

Creates the VPC, public/private subnets, NAT gateway, and security groups.

**Inputs:** `name_prefix`, `vpc_cidr`, `public_subnet_cidrs`, `private_subnet_cidrs`, `app_port`

**Outputs:** `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `alb_sg_id`, `app_sg_id`

### `modules/alarms`

Creates CloudWatch metric alarms for ECS CPU/memory and ALB 5xx errors.

**Inputs:** `name_prefix`, `ecs_cluster_name`, `ecs_service_name`, `alb_arn_suffix`, `alarm_actions`

## Remote State

State is stored in S3 with DynamoDB locking (configured in `versions.tf`). Initialize per environment:

```bash
# Staging
terraform init \
  -backend-config="bucket=<TF_STATE_BUCKET>" \
  -backend-config="key=stellar-spend/staging/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=<TF_LOCK_TABLE>"

# Production
terraform init \
  -backend-config="bucket=<TF_STATE_BUCKET>" \
  -backend-config="key=stellar-spend/production/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=<TF_LOCK_TABLE>"
```

## Applying per environment

```bash
# Staging
terraform apply -var-file=envs/staging.tfvars

# Production
terraform apply -var-file=envs/production.tfvars
```

Secrets are passed via `TF_VAR_*` environment variables — never committed to tfvars files.

## CI

The `terraform.yml` workflow runs on every PR that touches `terraform/`:

1. **Validate** — `terraform fmt`, `init -backend=false`, `validate`
2. **Plan (staging)** — full plan against staging state, with Infracost cost estimate
3. **Plan (production)** — full plan against production state, with Infracost cost estimate

Both plans and cost estimates are posted as PR comments.
