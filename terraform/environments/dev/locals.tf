# All locals for this root, moved out of main.tf and virtual_key.tf.

locals {
  # Onboarding a second use case is now a YAML-only PR - every
  # usecases/*.yaml file becomes its own module.use_case[...] instance.
  usecase_files = fileset("${path.module}/../../../usecases", "*.yaml")

  usecase_declarations_by_file = {
    for f in local.usecase_files :
    f => yamldecode(file("${path.module}/../../../usecases/${f}"))
  }

  # Grouped, not a plain `id => decl` map: Terraform's `for` expression
  # errors outright on a duplicate key with no ellipsis - verified against
  # 1.16.4 before relying on it.
  usecase_declarations_grouped = {
    for decl in values(local.usecase_declarations_by_file) :
    decl.metadata.id => decl...
  }

  usecase_declarations = {
    for id, decls in local.usecase_declarations_grouped :
    id => decls[0]
  }

  # The shape every declaration must have.
  usecase_contract_top_level_keys = ["apiVersion", "kind", "metadata", "spec"]
  usecase_contract_metadata_keys  = ["id", "owner", "team"]
  usecase_contract_spec_keys      = ["dataClassification", "modelRoute", "budget", "observability"]

  # Name of each use case's route-scoped virtual key (virtual_key.tf).
  virtual_key_aliases = {
    for id, uc in module.use_case : id => "${uc.resource_names.gateway}-app-key"
  }

  # LiteLLM soft_budget: the warning tier, at the lowest declared threshold
  # (75%). LiteLLM alerts when a key's spend crosses it; only max_budget blocks.
  virtual_key_soft_budgets = {
    for id, uc in module.use_case : id => uc.budget_config.monthly_usd * min(uc.budget_config.thresholds_pct...) / 100
  }

  # No application workload is deployed for any use case in this PoC, so there
  # is no separate AWS principal to name as "the app role" yet.
  app_key_readers = module.llm_gateway.app_key_reader_arns
}
