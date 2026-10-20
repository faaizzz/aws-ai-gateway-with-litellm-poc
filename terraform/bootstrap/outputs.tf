output "plan_role_arn" {
  description = "Set as the AWS_PLAN_ROLE_ARN GitHub repository variable."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Set as the AWS_APPLY_ROLE_ARN GitHub repository variable."
  value       = aws_iam_role.apply.arn
}

output "oidc_provider_arn" {
  value = local.oidc_provider_arn
}

output "docs_bucket_name" {
  description = "Set as the DOCS_BUCKET GitHub repository variable."
  value       = aws_s3_bucket.docs.bucket
}

output "docs_distribution_id" {
  description = "Set as the DOCS_DISTRIBUTION_ID GitHub repository variable."
  value       = aws_cloudfront_distribution.docs.id
}

output "docs_site_url" {
  value = "https://${aws_cloudfront_distribution.docs.domain_name}"
}

output "docs_publish_role_arn" {
  description = "Set as the AWS_DOCS_ROLE_ARN GitHub repository secret."
  value       = aws_iam_role.docs.arn
}
