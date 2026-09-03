# ── Disaster Recovery Configuration ────────────────────────────────────────

# RTO: 1 hour, RPO: 15 minutes

# ── Backup Configuration ───────────────────────────────────────────────────

resource "aws_backup_vault" "main" {
  name        = "${local.name_prefix}-backup-vault"
  kms_key_arn = aws_kms_key.backup.arn

  tags = { Name = "${local.name_prefix}-backup-vault" }
}

resource "aws_kms_key" "backup" {
  description             = "KMS key for backup encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = { Name = "${local.name_prefix}-backup-key" }
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${local.name_prefix}-backup"
  target_key_id = aws_kms_key.backup.key_id
}

# ── RDS Backup Configuration ───────────────────────────────────────────────

resource "aws_db_instance" "main" {
  identifier            = "${local.name_prefix}-db"
  engine                = "postgres"
  engine_version        = "16.1"
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.backup.arn
  
  # Backup configuration
  backup_retention_period = 30
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"
  copy_tags_to_snapshot  = true
  
  # Multi-AZ for high availability
  multi_az               = true
  
  # Enhanced monitoring
  enabled_cloudwatch_logs_exports = ["postgresql"]
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  
  # Performance Insights
  performance_insights_enabled    = true
  performance_insights_retention_period = 7
  
  skip_final_snapshot = false
  final_snapshot_identifier = "${local.name_prefix}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  tags = { Name = "${local.name_prefix}-db" }
}

resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name_prefix}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ── Automated Backup Plan ──────────────────────────────────────────────────

resource "aws_backup_plan" "main" {
  name = "${local.name_prefix}-backup-plan"

  rule {
    rule_name         = "daily_backup"
    target_backup_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 5 ? * * *)"
    start_window      = 60
    completion_window = 120
    
    lifecycle {
      delete_after = 30
      cold_storage_after = 7
    }

    recovery_point_tags = {
      Environment = var.environment
      Type        = "daily"
    }
  }

  rule {
    rule_name         = "weekly_backup"
    target_backup_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 6 ? * 1 *)"
    start_window      = 60
    completion_window = 120
    
    lifecycle {
      delete_after = 90
      cold_storage_after = 30
    }

    recovery_point_tags = {
      Environment = var.environment
      Type        = "weekly"
    }
  }
}

resource "aws_backup_resource_assignment" "rds" {
  name             = "${local.name_prefix}-rds-backup"
  backup_plan_id   = aws_backup_plan.main.id
  iam_role_arn     = aws_iam_role.backup.arn
  resources        = ["arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:db:${aws_db_instance.main.identifier}"]
}

resource "aws_iam_role" "backup" {
  name = "${local.name_prefix}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "backup.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# ── S3 Backup for Application Data ─────────────────────────────────────────

resource "aws_s3_bucket" "backups" {
  bucket = "${local.name_prefix}-backups-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "${local.name_prefix}-backups" }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.backup.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "archive_old_backups"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 90
    }
  }
}

# ── Cross-Region Replication ───────────────────────────────────────────────

resource "aws_s3_bucket_replication_configuration" "backups" {
  depends_on = [aws_s3_bucket_versioning.backups]
  bucket     = aws_s3_bucket.backups.id
  role       = aws_iam_role.s3_replication.arn

  rule {
    id     = "replicate_backups"
    status = "Enabled"

    filter {
      prefix = ""
    }

    destination {
      bucket       = "arn:aws:s3:::${local.name_prefix}-backups-replica-${data.aws_caller_identity.current.account_id}"
      storage_class = "STANDARD_IA"
      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
    }
  }
}

resource "aws_iam_role" "s3_replication" {
  name = "${local.name_prefix}-s3-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "${local.name_prefix}-s3-replication-policy"
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.backups.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.backups.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Resource = "arn:aws:s3:::${local.name_prefix}-backups-replica-${data.aws_caller_identity.current.account_id}/*"
      }
    ]
  })
}

# ── Data Sources ───────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
