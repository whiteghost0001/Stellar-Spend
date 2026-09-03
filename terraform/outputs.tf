output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (for Route 53 alias records)"
  value       = aws_lb.main.zone_id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "app_secrets_arn" {
  description = "ARN of the Secrets Manager secret holding app credentials"
  value       = aws_secretsmanager_secret.app.arn
  sensitive   = true
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name for app logs"
  value       = aws_cloudwatch_log_group.app.name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (use for cache invalidations)"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_domain_name" {
  description = "Default CloudFront domain name (e.g. d1234.cloudfront.net) — set as NEXT_PUBLIC_CDN_URL"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront hosted zone ID (for Route 53 alias records)"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "cf_logs_bucket" {
  description = "S3 bucket storing CloudFront access logs"
  value       = aws_s3_bucket.cf_logs.bucket
}
