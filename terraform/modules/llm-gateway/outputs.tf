output "gateway_task_role_name" {
  description = "Name of the shared LiteLLM gateway ECS task role. Each module.use_case instance attaches its own inline Bedrock-invoke policy onto this role - the role's overall IAM scope is the union of every provisioned use case's grant."
  value       = aws_iam_role.gateway_task_role.name
}

output "gateway_task_role_arn" {
  description = "ARN of the same shared gateway task role."
  value       = aws_iam_role.gateway_task_role.arn
}

output "gateway_task_execution_role_arn" {
  description = "ARN of the ECS task EXECUTION role - the principal that resolves the container's `secrets` block at task start."
  value       = aws_iam_role.gateway_task_execution_role.arn
}

output "alb_dns_name" {
  description = "Public DNS name of the gateway's Application Load Balancer (HTTPS, self-signed demo certificate - see root README \"Known limitations\")."
  value       = aws_lb.gateway.dns_name
}

output "gateway_key_secret_arn" {
  description = <<-EOT
    Secrets Manager ARN of the shared LiteLLM PLATFORM master key. Never
    handed to an application; it authenticates the gateway process itself
    (`LITELLM_MASTER_KEY`) and the platform's own provisioning calls to
    LiteLLM's admin-only /key/generate and /key/update endpoints. The
    application's actual credential is a route-scoped virtual key minted
    from those endpoints at the environment layer
    (terraform/environments/dev/virtual_key.tf), not this secret.
  EOT
  value       = aws_secretsmanager_secret.gateway_key.arn
}

output "gateway_salt_key_secret_arn" {
  description = "Secrets Manager ARN of LITELLM_SALT_KEY. Injected separately from LITELLM_MASTER_KEY; the two must never share a value."
  value       = aws_secretsmanager_secret.gateway_salt_key.arn
}

output "gateway_key_readers" {
  description = "Principals allowed to read the gateway master and salt key secrets. Exposed for tests."
  value       = local.gateway_key_readers
}

output "stable_secret_reader_arns" {
  description = "Stable reader ARNs: the caller if it is an IAM user, plus var.local_operator_arns. Can be empty; use app_key_reader_arns when it must not be."
  value       = local.stable_secret_reader_arns
}

output "app_key_reader_arns" {
  description = "Reader ARNs for an application key secret: stable_secret_reader_arns plus the CI apply role. Never empty (checked by a precondition)."
  value       = local.app_key_reader_arns
}

output "litellm_config_yaml" {
  description = "The generated LiteLLM config. Plaintext in the task environment, so it must never hold a credential. Exposed for tests."
  value       = local.litellm_config_yaml
}
