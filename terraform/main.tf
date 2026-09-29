terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  api_throttling_rate_limit  = 5
  api_throttling_burst_limit = 10

  cloudfront_log_retention_days = 30

  common_tags = {
    Project     = "book-search"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Repository  = "book-search"
  }
}

provider "aws" {
  region = "ap-northeast-1"

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "frontend" {
  bucket = "book-search-dev-frontend-${data.aws_caller_identity.current.account_id}"

}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "cloudfront_logs" {
  bucket = "book-search-dev-cloudfront-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  rule {
    id     = "ExpireCloudFrontLogs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = local.cloudfront_log_retention_days
    }
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "book-search-dev-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "api" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    domain_name = trimprefix(aws_apigatewayv2_api.api.api_endpoint,
    "https://")
    origin_id = "API-Gateway"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "S3-frontend"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "API-Gateway"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.api.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "frontend" {
  statement {
    sid    = "AllowCloudFrontReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["${aws_cloudfront_distribution.frontend.arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend.json
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "AllowLambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "book-search-dev-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/book-search-dev-api"
  retention_in_days = 14

}

data "aws_iam_policy_document" "lambda_logs" {
  statement {
    sid    = "AllowLambdaWriteLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "${aws_cloudwatch_log_group.lambda.arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "lambda_logs" {
  name   = "book-search-dev-lambda-logs"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_logs.json
}

resource "aws_lambda_function" "api" {
  function_name = "book-search-dev-api"
  role          = aws_iam_role.lambda.arn

  filename         = "${path.module}/../dist/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../dist/lambda.zip")

  handler = "app.handler"

  runtime     = "python3.12"
  memory_size = 128
  timeout     = 10

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda_logs
  ]

}

resource "aws_apigatewayv2_api" "api" {
  name          = "book-search-dev-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /api/health"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "books" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /api/books"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_lambda_permission" "api_health" {
  statement_id  = "AllowAPIGatewayInvokeGetHealth"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/$default/GET/api/health"
}

resource "aws_lambda_permission" "api_books" {
  statement_id  = "AllowAPIGatewayInvokeGetBooks"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/$default/GET/api/books"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  depends_on = [
    aws_apigatewayv2_route.health,
    aws_apigatewayv2_route.books,
    aws_lambda_permission.api_health,
    aws_lambda_permission.api_books
  ]

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn

    format = jsonencode({
      requestId      = "$context.requestId"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
    })
  }

  default_route_settings {
    throttling_burst_limit = local.api_throttling_burst_limit
    throttling_rate_limit  = local.api_throttling_rate_limit
  }
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/book-search-dev-http-api"
  retention_in_days = 14
}

variable "budget_notification_email" {
  description = "Budget通知先メールアドレス"
  type        = string
  sensitive   = true
}

resource "aws_budgets_budget" "zero_spend" {
  name         = "My Zero-Spend Budget"
  budget_type  = "COST"
  limit_amount = "1"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 0.01
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_notification_email]
  }
}