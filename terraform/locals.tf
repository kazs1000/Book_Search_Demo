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
