variable "budget_notification_email" {
  description = "Budget通知先メールアドレス"
  type        = string
  sensitive   = true
}

variable "alarm_notification_email" {
  description = "CloudWatch Alarm通知先メールアドレス"
  type        = string
  sensitive   = true
}
