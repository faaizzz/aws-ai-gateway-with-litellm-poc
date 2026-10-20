# IAM least-privilege test: proves the safety contract, not just that
# Terraform syntax works.

provider "aws" {
  region                      = "eu-central-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    # Only account_id is used by this module.
    account_id = "123456789012"
  }
}

variables {
  gateway_role_name = "ai-gateway-task-role"

  use_case = {
    id                  = "advisor-chat"
    team                = "advisor"
    owner               = "advisor-platform"
    data_classification = "confidential"
    model_route         = "anthropic-claude-sonnet-bedrock"
    budget              = { monthly_usd = 10000 }
    observability       = { tier = "standard" }
  }
}

run "iam_policy_grants_only_bedrock_invoke" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  assert {
    condition     = !strcontains(output.iam_policy_json, "bedrock:*")
    error_message = "IAM policy must never grant bedrock:* (CLAUDE.md invariants)."
  }

  assert {
    # Every statement whose actions include a bedrock:Invoke* action must
    # be pinned to specific ARNs, never "*" - checked per-statement
    # because the separate.
    condition = alltrue([
      for s in jsondecode(output.iam_policy_json).Statement :
      !strcontains(jsonencode(s.Resource), "\"*\"") if anytrue([for a in flatten([s.Action]) : strcontains(a, "bedrock:Invoke")])
    ])
    error_message = "Any statement granting a bedrock:Invoke* action must be pinned to specific ARNs, never a wildcard."
  }

  assert {
    # The marketplace-check exception must stay exactly that: it must never
    # carry a bedrock:Invoke* action alongside its Resource "*".
    condition = alltrue([
      for s in jsondecode(output.iam_policy_json).Statement :
      !anytrue([for a in flatten([s.Action]) : strcontains(a, "bedrock:Invoke")]) if strcontains(jsonencode(s.Resource), "\"*\"")
    ])
    error_message = "A statement with Resource \"*\" must never also grant a bedrock:Invoke* action."
  }

  assert {
    condition     = strcontains(output.iam_policy_json, "bedrock:InvokeModel") && strcontains(output.iam_policy_json, "bedrock:InvokeModelWithResponseStream")
    error_message = "The gateway must be able to invoke and stream from the approved model."
  }

  assert {
    # Aws-marketplace:Subscribe was only ever needed for the one-time
    # admin action of accepting the model's Marketplace agreement, already
    # done manually against this account.
    condition     = !strcontains(output.iam_policy_json, "aws-marketplace:Subscribe")
    error_message = "The runtime policy must not grant aws-marketplace:Subscribe; that is a one-time admin action, not a gateway runtime permission."
  }

  assert {
    condition     = strcontains(output.iam_policy_json, "inference-profile/eu.anthropic.claude-sonnet-4-6")
    error_message = "The policy must include the EU cross-region inference profile ARN (Bedrock does not support on-demand invoke for this model - see terraform/catalog/approved-models.yaml)."
  }

  assert {
    condition     = strcontains(output.iam_policy_json, "arn:aws:bedrock:eu-central-1::foundation-model/anthropic.claude-sonnet-4-6")
    error_message = "The policy must include the underlying foundation-model ARN in eu-central-1 (and, per the catalogue, every other region the profile fans out to)."
  }
}

run "iam_role_policy_attaches_to_shared_gateway_role_only" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  assert {
    condition     = aws_iam_role_policy.gateway_route_policy[0].role == var.gateway_role_name
    error_message = "The route policy must attach to the shared gateway task role, never to an application role."
  }
}

run "non_bedrock_route_grants_no_bedrock_access" {
  command = plan

  module {
    source = "./terraform/modules/use-case"
  }

  variables {
    use_case = {
      id                  = "advisor-chat"
      team                = "advisor"
      owner               = "advisor-platform"
      data_classification = "internal"
      model_route         = "external-llm-zdr"
      budget              = { monthly_usd = 10000 }
      observability       = { tier = "standard" }
    }
  }

  assert {
    condition     = output.iam_policy_json == null
    error_message = "A use case routed to a non-Bedrock provider must not receive a Bedrock IAM grant."
  }
}
