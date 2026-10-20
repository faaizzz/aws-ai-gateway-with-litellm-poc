output "use_cases" {
  description = "Every module.use_case instance's own outputs (resource_names, attribution, resolved_route, safe_defaults, budget_config, observability_config, iam_policy_json), keyed by use-case id."
  value = {
    for id, m in module.use_case : id => {
      resource_names       = m.resource_names
      attribution          = m.attribution
      resolved_route       = m.resolved_route
      safe_defaults        = m.safe_defaults
      budget_config        = m.budget_config
      observability_config = m.observability_config
      iam_policy_json      = m.iam_policy_json
    }
  }
}

output "gateway_task_role_arn" {
  description = "ARN of the shared gateway ECS task role. Each use case attaches its own route-scoped policy to it."
  value       = module.llm_gateway.gateway_task_role_arn
}

output "gateway_alb_dns_name" {
  description = "Public DNS name of the gateway's Application Load Balancer (HTTPS, self-signed demo certificate - see README \"Known limitations\")."
  value       = module.llm_gateway.alb_dns_name
}

output "haiku_quota_request_status" {
  description = "AWS Service Quotas request status for the Haiku model's requests-per-minute and tokens-per-minute quota increase requests."
  value = {
    requests_per_minute = aws_servicequotas_service_quota.haiku_requests_per_minute.request_status
    tokens_per_minute   = aws_servicequotas_service_quota.haiku_tokens_per_minute.request_status
  }
}

output "app_key_secret_arns" {
  description = "Secrets Manager ARN of each use case's route-scoped virtual key - the application's real credential, not the platform master key. Keyed by use-case id."
  value       = { for id, s in aws_secretsmanager_secret.app_key : id => s.arn }
}
