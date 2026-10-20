variable "local_operator_arns" {
  description = "Stable IAM principal ARNs (e.g. an operator role) allowed to read the gateway master-key and app-key secrets, besides an IAM-user caller."
  type        = list(string)
  default     = []
}

# ci_plan_role_arn / ci_apply_role_arn go to the gateway module so the CI roles can read the key secrets.
variable "ci_plan_role_arn" {
  description = "GitHub Actions OIDC role that runs `terraform plan` in CI. null until the role exists."
  type        = string
  default     = null
  nullable    = true
}

variable "ci_apply_role_arn" {
  description = "GitHub Actions OIDC role that runs `terraform apply` in CI. null until the role exists."
  type        = string
  default     = null
  nullable    = true
}

variable "langfuse_public_key" {
  description = "Langfuse Cloud project public key (pk-lf-...)."
  type        = string
  # Ephemeral rather than merely sensitive - ephemeral is Terraform's
  # stronger guarantee.
  ephemeral = true
}

variable "langfuse_secret_key" {
  description = "Langfuse Cloud project secret key (sk-lf-...)."
  type        = string
  ephemeral   = true
}

variable "langfuse_host" {
  description = "Langfuse Cloud host. Must be the EU host (https://cloud.langfuse.com), matching the Bedrock EU residency assumption."
  type        = string

  validation {
    condition     = var.langfuse_host == "https://cloud.langfuse.com"
    error_message = "langfuse_host must be the Langfuse Cloud EU host (https://cloud.langfuse.com). Non-EU hosts (e.g. https://us.cloud.langfuse.com) are rejected to keep trace data in the EU, consistent with this deployment's Bedrock EU-residency assumption."
  }
}
