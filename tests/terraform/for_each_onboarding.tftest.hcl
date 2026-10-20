# Proves the dev root's for_each-over-usecases/*.yaml onboarding mechanism
# against a fixture directory with two valid, distinct declarations.

run "two_distinct_usecases_plan_cleanly" {
  command = plan

  module {
    source = "./tests/terraform/fixtures/for_each_root"
  }

  variables {
    usecases_dir = "./tests/terraform/fixtures/usecases_two_valid"
  }

  assert {
    condition     = output.usecase_count == 2
    error_message = "expected exactly 2 distinct use-case ids from usecases_two_valid, got ${output.usecase_count}"
  }

  assert {
    condition     = contains(output.usecase_ids, "alpha-example") && contains(output.usecase_ids, "beta-example")
    error_message = "expected usecase_ids to contain both alpha-example and beta-example, got ${jsonencode(output.usecase_ids)}"
  }
}

run "duplicate_metadata_id_fails" {
  command = plan

  module {
    source = "./tests/terraform/fixtures/for_each_root"
  }

  variables {
    usecases_dir = "./tests/terraform/fixtures/usecases_duplicate_id"
  }

  expect_failures = [terraform_data.usecase_id_uniqueness]
}
