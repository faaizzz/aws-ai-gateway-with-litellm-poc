# main.tf is now just this orientation note plus the one data source
# catalog.tf needs.

# Used by catalog.tf for the Bedrock inference-profile ARN (account_id).
data "aws_caller_identity" "current" {}
