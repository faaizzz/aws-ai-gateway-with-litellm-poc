# `use-case-observability`

Per-use-case AWS Budget alarm (budget notifications are Datadog target state, see `design.md`). It takes no `use_case` input and never reads YAML. Every input is passed through from one `module.use_case[...]` instance's outputs.

```hcl
module "use_case_observability" {
  for_each = module.use_case
  source   = "../../modules/use-case-observability"

  attribution          = each.value.attribution
  resource_names       = each.value.resource_names
  budget_config        = each.value.budget_config
  environment          = "dev"
}
```

Nothing in the module names a specific use case or provider. Names and tags are built from the inputs.

## What it creates

- **Budget:** an AWS Budget with the 75/90/100% thresholds and an SNS topic.

## Known gaps

- **The budget is account-wide.** Per-use-case budgets need a cost-allocation tag, which must be activated manually in the Billing console. Until then every use case's budget alarms on the same total. The resource name says so (`...-account-wide-not-per-usecase`).
- **`trivy` skips this module** when scanning from the environment root, because it cannot follow a `for_each` over another module's output. Scanned directly, it flags `AWS-0136`, which is ignored on purpose in `budget.tf`.

## Tests

`tests/terraform/use_case_observability.tftest.hcl` plans the module twice, for two different use cases. It checks that each gets its own budget and SNS topic, named from its own `resource_names`, with the 75/90/100% notifications.
