config {
  format            = "compact"
  call_module_type  = "all"
  force             = false
  disabled_by_default = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS-specific ruleset - the built-in "terraform" ruleset above only knows
# generic HCL/ Terraform-language issues, not AWS-provider-specific ones.
plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
