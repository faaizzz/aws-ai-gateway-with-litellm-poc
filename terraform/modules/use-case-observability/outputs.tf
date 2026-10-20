output "budget_sns_topic_arn" {
  description = "SNS topic ARN that this use case's budget notifications publish to."
  value       = aws_sns_topic.budget_alerts.arn
}

output "budget_id" {
  description = "AWS Budgets budget ID/name for this use case (see budget.tf's SCOPE CAVEAT - not a true per-use-case cost slice)."
  value       = aws_budgets_budget.this.id
}
