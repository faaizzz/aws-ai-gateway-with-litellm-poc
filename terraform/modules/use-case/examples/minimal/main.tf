# The smallest valid call to this module - a public/internal use case on the
# Haiku route, which every classification below `restricted` may use.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100.0, < 6.0.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

module "internal_chat_example" {
  source = "../.."

  gateway_role_name = "example-gateway-task-role"

  use_case = {
    id                  = "internal-chat-example"
    team                = "example-team"
    owner               = "example-platform"
    data_classification = "internal"
    model_route         = "anthropic-claude-haiku-bedrock"

    budget = {
      monthly_usd = 500
    }

    observability = {
      tier = "minimal"
    }
  }
}

output "resource_names" {
  value = module.internal_chat_example.resource_names
}

output "attribution" {
  value = module.internal_chat_example.attribution
}
