# AWS services used and Azure alternatives

This lists the AWS services the PoC uses and the closest Azure equivalent for each. It is a mapping aid, not a target-state design: nothing here is built for Azure.

The AWS list comes from the resource types in `terraform/`. The Azure column is general knowledge of the two clouds. Azure's current Claude and Foundry regional availability was not checked, so confirm it before relying on it.

| Role in this repo | AWS service | Azure alternative |
|---|---|---|
| Model provider (Anthropic via `eu.` inference profile) | Amazon Bedrock | Azure AI Foundry (Azure OpenAI) for GPT models. Claude is also offered through Foundry, but regional and residency availability differs. |
| Gateway compute (LiteLLM container, 1 task, 0.5 vCPU / 2 GB) | ECS Fargate | Azure Container Apps. Container Instances is a simpler option. |
| Public entry point | Application Load Balancer, ACM certificate | Application Gateway (L7) or Front Door, with App Service Managed Certificates or Key Vault certificates |
| Rate limiting and edge protection | WAFv2 (per-IP rate limit, trusted CIDR IP set) | Azure WAF, attached to Application Gateway or Front Door |
| Gateway database (Postgres request logs, `db.t4g.micro`, private) | RDS for PostgreSQL | Azure Database for PostgreSQL – Flexible Server |
| Secrets (Langfuse keys, gateway keys, external provider key) | Secrets Manager (with resource policies) | Azure Key Vault (access through RBAC or access policies) |
| Identity and access (task roles, scoped `InvokeModel`) | IAM roles and policies | Entra ID, managed identities and Azure RBAC. The Bedrock-scoped IAM policy becomes a role assignment on a specific Foundry deployment or resource. |
| CI authentication (no long-lived keys) | IAM OIDC provider for GitHub Actions | Entra workload identity federation (federated credentials) |
| Network (VPC, public subnets, security groups, no NAT) | VPC, security groups | VNet and NSGs |
| Terraform state (`use_lockfile`) | S3 | Azure Blob Storage backend. Locking uses blob leases. |
| ALB access logs, docs hosting | S3 | Blob Storage. Static site hosting goes behind Front Door or Azure CDN. |
| Docs site CDN | CloudFront (OAC, cache and response-header policies, function) | Azure Front Door or Azure CDN |
| Logs and alarms | CloudWatch Logs, metric filter, metric alarms | Azure Monitor: Log Analytics workspace, log-based metrics, alert rules |
| Alert notifications | SNS | Azure Monitor action groups (or Event Grid) |
| Per-use-case budgets (75% / 90% / 100%) | AWS Budgets | Microsoft Cost Management budgets, which can trigger action groups |
| Quota requests | Service Quotas | Azure Quotas / Quota API |

## What changes in a port

- **LiteLLM and Langfuse stay the same.** LiteLLM already has an Azure provider, so the main catalogue change is the route mapping in `terraform/catalog/approved-models.yaml`.
- **The IAM scoping becomes a different mechanism.** The Bedrock `eu.` inference-profile ARN handling (cross-region EU routing) has no Azure analogue. On Azure you would pin an EU-region deployment, or use a Data Zone deployment type for EU data-zone processing. The residency assumption would need restating.
- **Terraform changes provider.** The module would move from the `aws` provider to `azurerm` (or `azapi` for newer Foundry features). The use-case YAML contract, validation logic and tests would carry over mostly unchanged.
