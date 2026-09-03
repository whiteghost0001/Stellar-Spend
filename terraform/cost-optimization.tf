# ── Cost Monitoring and Optimization ───────────────────────────────────────

# ── Cost Allocation Tags ───────────────────────────────────────────────────

locals {
  cost_tags = {
    Environment = var.environment
    Project     = "stellar-spend"
    CostCenter  = var.cost_center
    Owner       = var.owner_email
    ManagedBy   = "terraform"
  }
}

# Apply tags to all resources
resource "aws_resourcegroups_group" "cost_tracking" {
  name = "${local.name_prefix}-cost-tracking"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "Project"
          Values = ["stellar-spend"]
        }
      ]
    })
  }

  tags = local.cost_tags
}

# ── CloudWatch Cost Anomaly Detection ──────────────────────────────────────

resource "aws_ce_anomaly_monitor" "main" {
  name          = "${local.name_prefix}-cost-anomaly"
  monitor_type  = "DIMENSIONAL"
  monitor_dimension = "SERVICE"

  monitor_specification = jsonencode({
    Tags = {
      Key    = "Project"
      Values = ["stellar-spend"]
    }
  })

  tags = local.cost_tags
}

resource "aws_ce_anomaly_subscription" "main" {
  name            = "${local.name_prefix}-cost-alerts"
  threshold       = 100
  frequency       = "DAILY"
  monitor_arn     = aws_ce_anomaly_monitor.main.arn
  sns_topic_arn   = aws_sns_topic.cost_alerts.arn

  tags = local.cost_tags
}

resource "aws_sns_topic" "cost_alerts" {
  name = "${local.name_prefix}-cost-alerts"

  tags = local.cost_tags
}

resource "aws_sns_topic_subscription" "cost_alerts_email" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.cost_alert_email
}

# ── Budget Alerts — Total Monthly ─────────────────────────────────────────

resource "aws_budgets_budget" "monthly" {
  name              = "${local.name_prefix}-monthly-budget"
  budget_type       = "COST"
  limit_unit        = "USD"
  limit_value       = var.monthly_budget_limit
  time_period_start = "2026-01-01_00:00"
  time_period_end   = "2087-12-31_23:59"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Environment$${var.environment}"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "FORECASTED"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }

  tags = local.cost_tags
}

# ── Budget Alerts — Per Service ────────────────────────────────────────────

resource "aws_budgets_budget" "per_service" {
  for_each = var.monthly_budget_by_service

  name              = "${local.name_prefix}-budget-${replace(lower(split(" ", each.key)[0]), "/[^a-z0-9]/", "-")}"
  budget_type       = "COST"
  limit_unit        = "USD"
  limit_value       = each.value
  time_period_start = "2026-01-01_00:00"
  time_period_end   = "2087-12-31_23:59"

  cost_filter {
    name   = "Service"
    values = [each.key]
  }

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Environment$${var.environment}"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "FORECASTED"
    threshold                  = 90
    threshold_type             = "PERCENTAGE"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }

  tags = local.cost_tags
}

# ── Resource Utilization Monitoring ────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "ec2_low_utilization" {
  alarm_name          = "${local.name_prefix}-ec2-low-utilization"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 3600
  statistic           = "Average"
  threshold           = 10
  alarm_description   = "Alert when EC2 CPU utilization is low"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.app[0].id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_low_utilization" {
  alarm_name          = "${local.name_prefix}-rds-low-utilization"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 3600
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "Alert when RDS connections are low"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
}

# ── Unused Resource Detection ──────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "ebs_unused" {
  alarm_name          = "${local.name_prefix}-ebs-unused"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 7
  metric_name         = "VolumeReadOps"
  namespace           = "AWS/EBS"
  period              = 86400
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert on unused EBS volumes"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "nat_gateway_unused" {
  alarm_name          = "${local.name_prefix}-nat-unused"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 7
  metric_name         = "BytesOutToDestination"
  namespace           = "AWS/NatGateway"
  period              = 86400
  statistic           = "Sum"
  threshold           = 1000000
  alarm_description   = "Alert on unused NAT Gateway"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  treat_missing_data  = "notBreaching"
}

# ── Cost Optimization Dashboard ────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "cost_optimization" {
  dashboard_name = "${local.name_prefix}-cost-optimization"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", { stat = "Average" }]
          ]
          period = 86400
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Estimated Monthly Charges"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", { stat = "Average" }],
            [".", "NetworkIn", { stat = "Sum" }],
            [".", "NetworkOut", { stat = "Sum" }]
          ]
          period = 3600
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "EC2 Utilization"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "DatabaseConnections", { stat = "Average" }],
            [".", "CPUUtilization", { stat = "Average" }],
            [".", "FreeableMemory", { stat = "Average" }]
          ]
          period = 3600
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "RDS Utilization"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/NatGateway", "BytesOutToDestination", { stat = "Sum" }],
            [".", "BytesInFromDestination", { stat = "Sum" }]
          ]
          period = 3600
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "NAT Gateway Traffic"
        }
      }
    ]
  })
}

# ── Lambda for Cost Optimization Recommendations ────────────────────────────

resource "aws_lambda_function" "cost_optimizer" {
  filename      = "lambda_cost_optimizer.zip"
  function_name = "${local.name_prefix}-cost-optimizer"
  role          = aws_iam_role.lambda_cost_optimizer.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.cost_alerts.arn
      ENVIRONMENT   = var.environment
    }
  }

  tags = local.cost_tags
}

resource "aws_iam_role" "lambda_cost_optimizer" {
  name = "${local.name_prefix}-lambda-cost-optimizer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_cost_optimizer" {
  name = "${local.name_prefix}-lambda-cost-optimizer-policy"
  role = aws_iam_role.lambda_cost_optimizer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "cloudwatch:GetMetricStatistics",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "rds:DescribeDBInstances",
          "rds:ListTagsForResource",
          "sns:Publish"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "cost_optimizer_schedule" {
  name                = "${local.name_prefix}-cost-optimizer-schedule"
  description         = "Run cost optimizer daily"
  schedule_expression = "cron(0 8 * * ? *)"

  tags = local.cost_tags
}

resource "aws_cloudwatch_event_target" "cost_optimizer" {
  rule      = aws_cloudwatch_event_rule.cost_optimizer_schedule.name
  target_id = "CostOptimizer"
  arn       = aws_lambda_function.cost_optimizer.arn
}

resource "aws_lambda_permission" "cost_optimizer_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_optimizer_schedule.arn
}

# ── Data Sources ───────────────────────────────────────────────────────────

data "aws_region" "current" {}
