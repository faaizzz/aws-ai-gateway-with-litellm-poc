# AWS Budget alarm.

resource "aws_sns_topic" "budget_alerts" {
  name = "${var.resource_names.budget}-alerts"
  # Demo/PoC account;
  # trivy:ignore:AWS-0136
  kms_master_key_id = "alias/aws/sns"

  # Var.environment isn't otherwise read by this module - tagging the AWS
  # side independently means this topic's environment doesn't silently drift
  # out of sync with that.
  tags = {
    environment = var.environment
    use_case_id = var.attribution.use_case_id
  }
}

resource "aws_budgets_budget" "this" {
  name         = "${var.resource_names.budget}-account-wide-not-per-usecase"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_config.monthly_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = var.budget_config.thresholds_pct
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
    }
  }
}
