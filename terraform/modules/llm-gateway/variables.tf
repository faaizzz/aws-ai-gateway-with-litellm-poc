# The shared LiteLLM gateway runtime - owns everything one-per-gateway and
# depends on no use case.

variable "vpc_id" {
  description = "VPC for the gateway's security groups, ALB, ECS task and RDS. The caller resolves it."
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of var.vpc_id. Scopes the ALB egress rule to the VPC instead of 0.0.0.0/0."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the ALB, ECS task and RDS subnet group. The demo passes public subnets (no NAT)."
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener. Created at the environment root (self-signed in the demo)."
  type        = string
}

variable "litellm_image" {
  description = "Pinned LiteLLM image (e.g. ghcr.io/berriai/litellm:v1.102.1). Always a release tag, never a moving one."
  type        = string
}

variable "catalog_path" {
  description = "Path to the model catalogue. null uses terraform/catalog/approved-models.yaml. Tests point it at a fixture."
  type        = string
  nullable    = true
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days. Defaults to 180, the strictest (confidential) retention, since the gateway serves every use case."
  type        = number
  default     = 180
}

variable "langfuse_public_key" {
  description = "Langfuse Cloud public key (pk-lf-...). Ephemeral: never written to state or a saved plan."
  type        = string
  ephemeral   = true
}

variable "langfuse_secret_key" {
  description = "Langfuse Cloud secret key (sk-lf-...). Ephemeral, like the public key."
  type        = string
  ephemeral   = true
}

variable "langfuse_host" {
  description = "Langfuse Cloud host. The environment root restricts it to the EU host."
  type        = string
}

variable "gateway_ci_plan_role_arn" {
  description = "ARN of the GitHub Actions OIDC role that runs `terraform plan`. Added to the gateway key secrets' resource policies. null until the role exists."
  type        = string
  default     = null
  nullable    = true
}

variable "gateway_ci_apply_role_arn" {
  description = "Same as gateway_ci_plan_role_arn, for the `apply` role."
  type        = string
  default     = null
  nullable    = true
}

variable "local_operator_arns" {
  description = "Stable IAM principal ARNs allowed to read the key secrets, besides the identity running Terraform."
  type        = list(string)
  default     = []
}

variable "alb_log_retention_days" {
  description = "Days to keep ALB access logs in S3. They contain client IPs, so keep this as short as incident tracing allows. Defaults to 90 (an assumption pending DPO input)."
  type        = number
  default     = 90

  validation {
    condition     = var.alb_log_retention_days >= 1
    error_message = "alb_log_retention_days must be at least 1."
  }
}

variable "waf_config_path" {
  description = "Path to the platform-owned WAF settings (rate limits and trusted IPs). `null` (the default) resolves to terraform/catalog/gateway-waf.yaml relative to this module, same pattern as catalog_path."
  type        = string
  nullable    = true
  default     = null
}
