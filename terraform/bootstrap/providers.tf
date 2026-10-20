provider "aws" {
  region = "eu-central-1"

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = "ai-usecase-onboarding"
      Env       = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}
