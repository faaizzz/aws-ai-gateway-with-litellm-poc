# The gateway master/salt key reader-ARN tests that used to live in
# iam_least_privilege.tftest.hcl moved here, against terraform/modules/llm-
# gateway.
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
    account_id = "123456789012"
    # IAM-user-shaped, so reader-ARN counts are stable across runs.
    arn = "arn:aws:iam::123456789012:user/ci-deployer"
  }
}

override_resource {
  target          = aws_iam_role.gateway_task_role
  override_during = plan
  values = {
    arn = "arn:aws:iam::123456789012:role/ai-gateway-task-role"
  }
}

override_resource {
  target          = aws_iam_role.gateway_task_execution_role
  override_during = plan
  values = {
    arn = "arn:aws:iam::123456789012:role/ai-gateway-task-execution-role"
  }
}

variables {
  vpc_id          = "vpc-0123456789abcdef0"
  vpc_cidr_block  = "10.0.0.0/16"
  subnet_ids      = ["subnet-aaaa1111", "subnet-bbbb2222", "subnet-cccc3333"]
  certificate_arn = "arn:aws:acm:eu-central-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
  litellm_image   = "ghcr.io/berriai/litellm:v1.102.1"

  langfuse_public_key = "pk-lf-test"
  langfuse_secret_key = "sk-lf-test"
  langfuse_host       = "https://cloud.langfuse.com"
}

run "gateway_key_secret_policy_trusts_explicit_ci_role_arns" {
  # The gateway key's Secrets Manager resource policy must trust the CI
  # plan/apply role ARNs explicitly, not derive a reader from
  # data.aws_caller_identity.current - which.
  command = plan

  module {
    source = "./terraform/modules/llm-gateway"
  }

  variables {
    gateway_ci_plan_role_arn  = "arn:aws:iam::123456789012:role/gh-actions-tf-plan"
    gateway_ci_apply_role_arn = "arn:aws:iam::123456789012:role/gh-actions-tf-apply"
  }

  assert {
    condition     = contains(output.gateway_key_readers, "arn:aws:iam::123456789012:role/gh-actions-tf-plan")
    error_message = "The gateway key's reader principals must explicitly include the CI plan-role ARN passed via gateway_ci_plan_role_arn."
  }

  assert {
    condition     = contains(output.gateway_key_readers, "arn:aws:iam::123456789012:role/gh-actions-tf-apply")
    error_message = "The gateway key's reader principals must explicitly include the CI apply-role ARN passed via gateway_ci_apply_role_arn."
  }
}

run "gateway_key_secret_policy_omits_unset_ci_role_arns" {
  # With no CI role ARNs configured, the reader list must NOT contain a null
  # or empty-string entry.
  command = plan

  module {
    source = "./terraform/modules/llm-gateway"
  }

  # gateway_ci_plan_role_arn / gateway_ci_apply_role_arn deliberately omitted
  # here to exercise the module's own `null` defaults, not an override.

  assert {
    condition     = alltrue([for r in output.gateway_key_readers : r != null && r != ""])
    error_message = "gateway_key_readers must never contain a null or empty-string entry - compact() should have dropped the unset CI role ARNs."
  }

  assert {
    # The remaining, legitimate readers (gateway role, task execution role,
    # deployer/caller identity) must still be present.
    condition     = length(output.gateway_key_readers) == 3
    error_message = "With both CI role ARNs unset, gateway_key_readers should contain exactly the 3 non-CI readers (gateway role, task execution role, caller identity)."
  }
}

run "stable_secret_reader_arns_excludes_assumed_role_session_but_includes_iam_user_and_operator_arn" {
  # Under GitHub OIDC the caller ARN is a per-run assumed-role session, so it must not be a reader.
  command = plan

  module {
    source = "./terraform/modules/llm-gateway"
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
      arn        = "arn:aws:sts::123456789012:assumed-role/github-oidc-plan/session-1234567890"
    }
  }

  variables {
    local_operator_arns = ["arn:aws:iam::123456789012:role/break-glass-operator"]
  }

  assert {
    condition     = !contains(output.stable_secret_reader_arns, "arn:aws:sts::123456789012:assumed-role/github-oidc-plan/session-1234567890")
    error_message = "An STS assumed-role session ARN must never be placed in the shared stable-secret-reader list."
  }

  assert {
    condition     = !contains(output.gateway_key_readers, "arn:aws:sts::123456789012:assumed-role/github-oidc-plan/session-1234567890")
    error_message = "An STS assumed-role session ARN must never be placed in the gateway master-key's reader list either."
  }

  assert {
    condition     = alltrue([for r in output.stable_secret_reader_arns : !can(regex(":assumed-role/", r))])
    error_message = "No entry in stable_secret_reader_arns may look like an STS assumed-role ARN, regardless of its exact value."
  }

  assert {
    condition     = contains(output.stable_secret_reader_arns, "arn:aws:iam::123456789012:role/break-glass-operator")
    error_message = "var.local_operator_arns must be included in stable_secret_reader_arns as the explicit alternative to the (excluded) ephemeral caller identity."
  }

  assert {
    condition     = length(output.stable_secret_reader_arns) == 1
    error_message = "With an assumed-role caller and one explicit operator ARN, stable_secret_reader_arns must contain exactly that one operator ARN."
  }
}

run "stable_secret_reader_arns_includes_iam_user_caller_identity" {
  # The positive counterpart to the run above: an IAM *user* caller identity
  # is stable across runs and must still be trusted, with no
  # var.local_operator_arns needed.
  command = plan

  module {
    source = "./terraform/modules/llm-gateway"
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/ci-deployer"
    }
  }

  assert {
    condition     = contains(output.stable_secret_reader_arns, "arn:aws:iam::123456789012:user/ci-deployer")
    error_message = "An IAM user's caller-identity ARN is stable and must be included in stable_secret_reader_arns."
  }

  assert {
    condition     = contains(output.gateway_key_readers, "arn:aws:iam::123456789012:user/ci-deployer")
    error_message = "An IAM user's caller-identity ARN must also reach the gateway master-key's reader list."
  }
}

run "app_key_reader_arns_includes_ci_apply_role_when_set" {
  # Under CI OIDC apply the caller is an assumed-role session and no operator ARNs are set.
  command = plan

  module {
    source = "./terraform/modules/llm-gateway"
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
      arn        = "arn:aws:sts::123456789012:assumed-role/github-ci-apply/session-1234567890"
    }
  }

  variables {
    gateway_ci_apply_role_arn = "arn:aws:iam::123456789012:role/github-ci-apply"
  }

  assert {
    condition     = contains(output.app_key_reader_arns, "arn:aws:iam::123456789012:role/github-ci-apply")
    error_message = "app_key_reader_arns must include gateway_ci_apply_role_arn when it is set, even though the caller identity itself is an assumed-role session ARN."
  }

  assert {
    condition     = length(output.app_key_reader_arns) > 0
    error_message = "app_key_reader_arns must never render empty when the CI apply role ARN is set."
  }

  assert {
    condition     = !contains(output.app_key_reader_arns, "arn:aws:sts::123456789012:assumed-role/github-ci-apply/session-1234567890")
    error_message = "The ephemeral assumed-role SESSION ARN must never itself be trusted as a principal, even though the ROLE ARN it was assumed from is trusted."
  }
}

run "app_key_reader_arns_empty_without_ci_apply_role_fails_precondition" {
  # The negative counterpart: same assumed-role caller, still no
  # local_operator_arns, but gateway_ci_apply_role_arn also left unset.
  command = plan

  module {
    source = "./terraform/modules/llm-gateway"
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
      arn        = "arn:aws:sts::123456789012:assumed-role/github-ci-apply/session-1234567890"
    }
  }

  # gateway_ci_apply_role_arn and local_operator_arns deliberately left unset
  # here to exercise the empty-list regression this issue fixes.

  expect_failures = [terraform_data.app_key_reader_safety_net]
}
