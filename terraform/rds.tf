# ── RDS PostgreSQL with automated backups ─────────────────────────────────────

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "stellar_spend"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "stellar_spend"
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "db_backup_retention_days" {
  description = "Number of days to retain automated RDS backups (1–35)"
  type        = number
  default     = 7
}

variable "db_backup_window" {
  description = "Daily UTC window for automated backups (hh24:mi-hh24:mi)"
  type        = string
  default     = "03:00-04:00"
}

variable "db_maintenance_window" {
  description = "Weekly UTC window for RDS maintenance"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

# ── DB subnet group ───────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "${local.name_prefix}-db-subnet-group" }
}

# ── DB security group ─────────────────────────────────────────────────────────

resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db-sg"
  description = "Allow PostgreSQL from app containers only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── RDS parameter group ───────────────────────────────────────────────────────

resource "aws_db_parameter_group" "main" {
  name   = "${local.name_prefix}-pg16"
  family = "postgres16"

  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # log queries > 1s
  }
}

# ── RDS instance ──────────────────────────────────────────────────────────────

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-db"

  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Storage
  allocated_storage     = var.environment == "production" ? 20 : 10
  max_allocated_storage = var.environment == "production" ? 100 : 20
  storage_type          = "gp3"
  storage_encrypted     = true

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  # Automated backups
  backup_retention_period = var.environment == "production" ? 30 : var.db_backup_retention_days
  backup_window           = var.db_backup_window
  maintenance_window      = var.db_maintenance_window
  copy_tags_to_snapshot   = true
  delete_automated_backups = false

  # High availability
  multi_az = var.environment == "production"

  # Monitoring
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  performance_insights_enabled    = true
  performance_insights_retention_period = var.environment == "production" ? 731 : 7

  parameter_group_name = aws_db_parameter_group.main.name

  # Deletion protection in production
  deletion_protection = var.environment == "production"
  skip_final_snapshot = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${local.name_prefix}-final-snapshot" : null

  apply_immediately = var.environment != "production"
}

# ── IAM role for RDS Enhanced Monitoring ─────────────────────────────────────

resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name_prefix}-rds-monitoring"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ── Store DB connection string in Secrets Manager ─────────────────────────────

resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name_prefix}/db-credentials"
  recovery_window_in_days = var.environment == "production" ? 30 : 0
  description             = "RDS credentials for stellar-spend ${var.environment}"
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = var.db_name
    url      = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${var.db_name}"
  })
}

# ── CloudWatch alarm: backup failure ─────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "db_backup_failed" {
  alarm_name          = "${local.name_prefix}-db-backup-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BackupRetentionPeriod"
  namespace           = "AWS/RDS"
  period              = 86400 # 24h
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "RDS automated backup may have failed"
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "db_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "db_identifier" {
  description = "RDS instance identifier (used in backup/restore CLI commands)"
  value       = aws_db_instance.main.identifier
}

output "db_secrets_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials"
  value       = aws_secretsmanager_secret.db.arn
  sensitive   = true
}
