output "resource_names" {
  description = "Deterministic resource names for this use case."
  value       = local.resource_names
}

output "attribution" {
  description = "Platform-owned attribution stamped on every request for this use case."
  value       = local.attribution
}

output "resolved_route" {
  description = "The catalogue entry this use case's model_route resolved to."
  value       = local.resolved_route
}

output "safe_defaults" {
  description = "Classification-derived safe defaults."
  value       = local.safe_defaults
}

# gateway_key_secret_arn, gateway_salt_key_secret_arn, gateway_key_readers,
# stable_secret_reader_arns and app_key_reader_arns used to live here.

output "virtual_key_allowed_models" {
  description = "The exact `models` list a virtual key for this use case must declare: only the resolved route, never the catalogue or a wildcard."
  value       = [local.attribution.route]
}

output "budget_config" {
  description = "Budget metadata and thresholds Terraform establishes; runtime enforces spend decisions."
  value       = local.budget_config
}

output "observability_config" {
  description = "Observability-tier configuration Terraform establishes."
  value       = local.observability_config
}

output "iam_policy_json" {
  description = "The least-privilege IAM policy document attached to the shared gateway task role for this use case's route. Null for a non-Bedrock route (see iam.tf)."
  value       = local.is_bedrock_route ? data.aws_iam_policy_document.gateway_bedrock_invoke[0].json : null
}
