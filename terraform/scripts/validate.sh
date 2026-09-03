#!/usr/bin/env bash
# terraform/scripts/validate.sh
#
# Validates and lints the Terraform configuration without requiring real
# AWS credentials or a remote backend.
#
# Usage:
#   ./terraform/scripts/validate.sh
#
# Requirements:
#   - terraform >= 1.6.0 on PATH
#   - (optional) tflint on PATH for extended linting

set -euo pipefail

TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Terraform directory: $TERRAFORM_DIR"
cd "$TERRAFORM_DIR"

# ── 1. Version check ──────────────────────────────────────────────────────────
echo ""
echo "==> terraform version"
terraform version

# ── 2. Init (local backend, no real credentials needed) ───────────────────────
echo ""
echo "==> terraform init (local backend)"
terraform init -backend=false -input=false

# ── 3. Format check ───────────────────────────────────────────────────────────
echo ""
echo "==> terraform fmt -check"
terraform fmt -check -recursive

# ── 4. Validate ───────────────────────────────────────────────────────────────
echo ""
echo "==> terraform validate"
terraform validate

# ── 5. tflint (optional) ──────────────────────────────────────────────────────
if command -v tflint &>/dev/null; then
  echo ""
  echo "==> tflint"
  tflint --init
  tflint
else
  echo ""
  echo "==> tflint not found, skipping (install from https://github.com/terraform-linters/tflint)"
fi

echo ""
echo "✓ All Terraform checks passed."
