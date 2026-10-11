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
