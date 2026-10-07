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

  alarm_period_seconds       = 300
  alarm_evaluation_periods   = 1
  alarm_datapoints_to_alarm  = 1
  lambda_errors_threshold    = 1
  lambda_duration_threshold  = 8000
  lambda_throttles_threshold = 1
  cloudfront_5xx_threshold   = 5

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

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

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

resource "aws_cloudwatch_log_delivery_source" "cloudfront" {
  provider = aws.us_east_1

  name         = "book-search-dev-cloudfront"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.frontend.arn
}

resource "aws_cloudwatch_log_delivery_destination" "cloudfront_s3" {
  provider = aws.us_east_1

  name          = "book-search-dev-cloudfront-s3"
  output_format = "json"
  delivery_destination_configuration {
    destination_resource_arn = aws_s3_bucket.cloudfront_logs.arn
  }
}

data "aws_iam_policy_document" "cloudfront_logs" {
  statement {
    sid     = "AllowLogDeliveryGetBucketAcl"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]

    resources = [aws_s3_bucket.cloudfront_logs.arn]


    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_log_delivery_source.cloudfront.arn]
    }

  }

  statement {
    sid     = "AllowLogDeliveryPutObject"
    effect  = "Allow"
    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.cloudfront_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/CloudFront/*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_log_delivery_source.cloudfront.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

  }

}

resource "aws_s3_bucket_policy" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  policy = data.aws_iam_policy_document.cloudfront_logs.json
}

resource "aws_cloudwatch_log_delivery" "cloudfront_s3" {
  provider = aws.us_east_1

  delivery_source_name     = aws_cloudwatch_log_delivery_source.cloudfront.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cloudfront_s3.arn

  depends_on = [
    aws_s3_bucket_policy.cloudfront_logs,
    aws_s3_bucket_public_access_block.cloudfront_logs,
    aws_s3_bucket_server_side_encryption_configuration.cloudfront_logs
  ]
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

variable "alarm_notification_email" {
  description = "CloudWatch Alarm通知先メールアドレス"
  type        = string
  sensitive   = true
}

resource "aws_sns_topic" "api_alerts" {
  name = "book-search-dev-api-alerts"
}

resource "aws_sns_topic_subscription" "api_alerts_email" {
  topic_arn = aws_sns_topic.api_alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

resource "aws_sns_topic" "cloudfront_alerts" {
  provider = aws.us_east_1
  name     = "book-search-dev-cloudfront-alerts"
}

resource "aws_sns_topic_subscription" "cloudfront_alerts_email" {
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.cloudfront_alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name        = "book-search-dev-lambda-errors"
  alarm_description = "Lambdaの実行エラーが5分間に1件以上発生した場合に通知"

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  statistic   = "Sum"

  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_evaluation_periods
  datapoints_to_alarm = local.alarm_datapoints_to_alarm
  threshold           = local.lambda_errors_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.api.function_name
  }

  alarm_actions = [aws_sns_topic.api_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name        = "book-search-dev-lambda-duration"
  alarm_description = "Lambdaの最大実行時間が5分間の集計で8秒以上になった場合に通知"

  namespace   = "AWS/Lambda"
  metric_name = "Duration"
  statistic   = "Maximum"

  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_evaluation_periods
  datapoints_to_alarm = local.alarm_datapoints_to_alarm
  threshold           = local.lambda_duration_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.api.function_name
  }

  alarm_actions = [aws_sns_topic.api_alerts.arn]
}


resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name        = "book-search-dev-lambda-throttles"
  alarm_description = "Lambdaのスロットリングが5分間に1件以上発生した場合に通知"

  namespace   = "AWS/Lambda"
  metric_name = "Throttles"
  statistic   = "Sum"

  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_evaluation_periods
  datapoints_to_alarm = local.alarm_datapoints_to_alarm
  threshold           = local.lambda_throttles_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.api.function_name
  }

  alarm_actions = [aws_sns_topic.api_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx" {
  provider = aws.us_east_1

  alarm_name        = "book-search-dev-cloudfront-5xx"
  alarm_description = "CloudFrontの5xxエラー率の平均が5分間の集計で5%以上になった場合に通知"

  namespace   = "AWS/CloudFront"
  metric_name = "5xxErrorRate"
  statistic   = "Average"

  period              = local.alarm_period_seconds
  evaluation_periods  = local.alarm_evaluation_periods
  datapoints_to_alarm = local.alarm_datapoints_to_alarm
  threshold           = local.cloudfront_5xx_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.frontend.id
    Region         = "Global"
  }

  alarm_actions = [aws_sns_topic.cloudfront_alerts.arn]
}