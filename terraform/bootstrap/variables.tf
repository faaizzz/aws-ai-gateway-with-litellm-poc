variable "github_sub_prefix" {
  description = "Prefix of the OIDC `sub` claim for this repo. This repository has immutable subject claims enabled (`gh api repos/<owner>/<repo>/actions/oidc/customization/sub`), so the prefix embeds owner/repo IDs rather than plain owner/name, e.g. \"repo:<owner>@<owner-id>/<repo>@<repo-id>\"; without immutable claims it is \"repo:<owner>/<repo>\"."
  type        = string
}

variable "state_bucket" {
  description = "S3 bucket holding Terraform state for terraform/environments/dev (and this root)."
  type        = string
  default     = "ai-gateway-tfstate-123456789012"
}

variable "create_oidc_provider" {
  description = "Set false if the account already has a GitHub OIDC provider (at most one per issuer URL); it is then looked up instead of created."
  type        = bool
  default     = true
}

variable "docs_basic_auth_user" {
  description = "Username for the docs site's HTTP basic auth."
  type        = string
  default     = "docs"
}

variable "docs_basic_auth_password_sha256" {
  description = "Lower-case hex SHA-256 of the docs site password. Only the hash is stored (in the CloudFront function), never the password. Generate both with: pw=$(openssl rand -base64 18); printf %s \"$pw\" | shasum -a 256 | cut -d' ' -f1"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.docs_basic_auth_password_sha256))
    error_message = "Must be a 64-character lower-case hex SHA-256."
  }
}
