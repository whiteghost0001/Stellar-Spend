# ── CloudFront CDN ────────────────────────────────────────────────────────────
# Distributes static assets and optionally the full app via CloudFront.
# Origin: Application Load Balancer (ALB).

locals {
  cf_origin_id = "${local.name_prefix}-alb-origin"
}

# ── S3 bucket for CloudFront access logs ─────────────────────────────────────

resource "aws_s3_bucket" "cf_logs" {
  bucket        = "${local.name_prefix}-cf-logs"
  force_destroy = var.environment != "production"

  tags = { Name = "${local.name_prefix}-cf-logs" }
}

resource "aws_s3_bucket_ownership_controls" "cf_logs" {
  bucket = aws_s3_bucket.cf_logs.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

resource "aws_s3_bucket_acl" "cf_logs" {
  depends_on = [aws_s3_bucket_ownership_controls.cf_logs]
  bucket     = aws_s3_bucket.cf_logs.id
  acl        = "log-delivery-write"
}

resource "aws_s3_bucket_lifecycle_configuration" "cf_logs" {
  bucket = aws_s3_bucket.cf_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    expiration { days = var.environment == "production" ? 90 : 30 }
  }
}

# ── Cache policies ────────────────────────────────────────────────────────────

# Immutable static assets (_next/static, /static) — cache 1 year
resource "aws_cloudfront_cache_policy" "static_assets" {
  name        = "${local.name_prefix}-static-assets"
  min_ttl     = 31536000
  default_ttl = 31536000
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

# Dynamic / API responses — no caching, forward all
resource "aws_cloudfront_cache_policy" "no_cache" {
  name        = "${local.name_prefix}-no-cache"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "all" }
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = [
          "Authorization",
          "Host",
          "Origin",
          "Referer",
          "Accept",
          "Accept-Language",
          "Content-Type",
        ]
      }
    }
    query_strings_config { query_string_behavior = "all" }
    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false
  }
}

# Public pages — short cache with revalidation
resource "aws_cloudfront_cache_policy" "pages" {
  name        = "${local.name_prefix}-pages"
  min_ttl     = 0
  default_ttl = 60
  max_ttl     = 3600

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

# ── Origin request policy (forward necessary headers to ALB) ──────────────────

resource "aws_cloudfront_origin_request_policy" "alb_forward" {
  name = "${local.name_prefix}-alb-forward"

  cookies_config { cookie_behavior = "all" }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = [
        "Host",
        "Origin",
        "Referer",
        "Accept",
        "Accept-Language",
        "Accept-Encoding",
        "Content-Type",
        "X-Forwarded-For",
        "CloudFront-Viewer-Country",
      ]
    }
  }
  query_strings_config { query_string_behavior = "all" }
}

# ── CloudFront distribution ───────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name_prefix} CDN"
  price_class         = var.cf_price_class
  aliases             = var.cf_domain_aliases
  http_version        = "http2and3"
  wait_for_deployment = false

  # ── Origin: ALB ──────────────────────────────────────────────────────────

  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = local.cf_origin_id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # ALB listener is HTTP; TLS terminates at CF
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 60
      origin_keepalive_timeout = 60
    }

    custom_header {
      name  = "X-CloudFront-Secret"
      value = var.cf_origin_secret
    }
  }

  # ── Default behaviour: dynamic pages ─────────────────────────────────────

  default_cache_behavior {
    target_origin_id         = local.cf_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = aws_cloudfront_cache_policy.pages.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.alb_forward.id
    compress                 = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.security_headers.arn
    }
  }

  # ── Immutable static assets: _next/static ────────────────────────────────

  ordered_cache_behavior {
    path_pattern             = "/_next/static/*"
    target_origin_id         = local.cf_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = aws_cloudfront_cache_policy.static_assets.id
    compress                 = true
  }

  # ── Public static files ───────────────────────────────────────────────────

  ordered_cache_behavior {
    path_pattern             = "/static/*"
    target_origin_id         = local.cf_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = aws_cloudfront_cache_policy.static_assets.id
    compress                 = true
  }

  # ── Public directory (icons, manifest, sw.js) ─────────────────────────────

  ordered_cache_behavior {
    path_pattern             = "/icons/*"
    target_origin_id         = local.cf_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = aws_cloudfront_cache_policy.static_assets.id
    compress                 = true
  }

  # ── API routes: no caching ────────────────────────────────────────────────

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = local.cf_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = aws_cloudfront_cache_policy.no_cache.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.alb_forward.id
    compress                 = true
  }

  # ── Geo-restrictions ──────────────────────────────────────────────────────

  restrictions {
    geo_restriction {
      restriction_type = length(var.cf_geo_restriction_locations) > 0 ? var.cf_geo_restriction_type : "none"
      locations        = var.cf_geo_restriction_locations
    }
  }

  # ── SSL/TLS ───────────────────────────────────────────────────────────────

  viewer_certificate {
    # Use ACM certificate when aliases are configured; otherwise use default CF cert
    acm_certificate_arn            = length(var.cf_domain_aliases) > 0 ? var.cf_acm_certificate_arn : null
    cloudfront_default_certificate = length(var.cf_domain_aliases) == 0
    ssl_support_method             = length(var.cf_domain_aliases) > 0 ? "sni-only" : null
    minimum_protocol_version       = length(var.cf_domain_aliases) > 0 ? "TLSv1.2_2021" : null
  }

  # ── Access logging ────────────────────────────────────────────────────────

  logging_config {
    bucket          = aws_s3_bucket.cf_logs.bucket_domain_name
    include_cookies = false
    prefix          = "cloudfront/"
  }

  tags = { Name = "${local.name_prefix}-cf" }

  depends_on = [aws_cloudfront_function.security_headers]
}

# ── CloudFront Function: security headers ─────────────────────────────────────

resource "aws_cloudfront_function" "security_headers" {
  name    = "${local.name_prefix}-security-headers"
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "Inject security headers on viewer response"

  code = <<-EOF
    async function handler(event) {
      const response = event.response;
      const headers = response.headers;

      headers['strict-transport-security'] = { value: 'max-age=63072000; includeSubDomains; preload' };
      headers['x-content-type-options']    = { value: 'nosniff' };
      headers['x-frame-options']           = { value: 'DENY' };
      headers['referrer-policy']           = { value: 'strict-origin-when-cross-origin' };
      headers['permissions-policy']        = { value: 'camera=(), microphone=(), geolocation=(), payment=(), usb=()' };

      return response;
    }
  EOF
}

# ── Cache invalidation via AWS CLI (null_resource) ────────────────────────────
# Run: terraform apply -target=null_resource.cf_invalidation to trigger manually.

resource "null_resource" "cf_invalidation" {
  triggers = {
    distribution_id = aws_cloudfront_distribution.main.id
    # Bump this value to force a new invalidation on next apply
    invalidation_trigger = var.cf_invalidation_trigger
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws cloudfront create-invalidation \
        --distribution-id ${aws_cloudfront_distribution.main.id} \
        --paths "/*" \
        --region ${var.aws_region}
    EOT
  }

  depends_on = [aws_cloudfront_distribution.main]
}

# ── CloudWatch monitoring ─────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "cf_5xx_rate" {
  alarm_name          = "${local.name_prefix}-cf-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "CloudFront 5xx error rate > 5% for 10 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
    Region         = "Global"
  }

  alarm_actions = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
  ok_actions    = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
}

resource "aws_cloudwatch_metric_alarm" "cf_4xx_rate" {
  alarm_name          = "${local.name_prefix}-cf-4xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 10
  alarm_description   = "CloudFront 4xx error rate > 10% for 15 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
    Region         = "Global"
  }

  alarm_actions = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
}

resource "aws_cloudwatch_metric_alarm" "cf_origin_latency" {
  alarm_name          = "${local.name_prefix}-cf-origin-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "OriginLatency"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "p99"
  threshold           = 3000
  alarm_description   = "CloudFront p99 origin latency > 3s for 10 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
    Region         = "Global"
  }

  alarm_actions = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
}
