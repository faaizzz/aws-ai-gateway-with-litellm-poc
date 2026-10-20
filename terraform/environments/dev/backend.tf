# Backend for Terraform state, with -native locking so no DynamoDB lock table
# is required.

terraform {
  backend "s3" {
    bucket       = "ai-gateway-tfstate-123456789012"
    key          = "dev/use-case-advisor-chat.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
