# AI Platform Design

Design for a governed AI gateway that several product teams share. The Terraform onboarding module is described in `README.md`; the target-state diagram is in [`architecture.md`](architecture.md). The organisation, teams and use cases (AdvisorChat, KYC, DevAgent, DigestBot, Research, Marketing) are fictional.

**Evidence vs. assumptions.** Numbers come from the **synthetic** sample data in `data/sample_spend_30d.csv` (30 days) and `data/sample_traces.json` (see `data/README.md`). Everything else is an assumption and is labelled as one, including: the AdvisorChat budget of $10k/month, the classification levels `public` / `internal` / `confidential` / `restricted` (the sample traces use `pii_sensitive` → `confidential` and `no_pii` → `internal`), and the self-hosting costs.

## Summary

- **Cost:** 64% of spend is one model (`gpt-5.4`, mostly DevAgent) and 6.0% has no team. Make `use_case_id` mandatory, show live spend per team, and stop keys at 100% of budget (already working).
- **Contract:** one small YAML file per use case, submitted as a PR. Each field becomes an enforced control. Defaults come from the data classification and can only be made stricter.
- **Models:** use Bedrock in the EU and pick the model per use case: Sonnet 5.5 for AdvisorChat and KYC, open-weight models for DigestBot and (if they pass evals and Security approves) DevAgent. This saves ~$25.6k/month, or ~$9.9k if DevAgent moves to Sonnet 5.5 instead. Do not self-host.
- **Order:** AdvisorChat first, then KYC, then DevAgent once tool permissions exist.

## 1. Cost governance

**Problems in the data**
- DevAgent costs 6.5x more per request than AdvisorChat. From 16 Mar its daily cost jumped from ~$310 to ~$1,250 and its output per request from ~1,170 to ~4,990 tokens, which suggests an agent loop.
- $2,419 (6.0%) has no team: a shared key and a personal key.
- $78.21 of AdvisorChat's confidential traffic used a provider that is not approved for confidential data.
- One DigestBot row has $9.85 of cost and zero requests.

**What the platform does**

| Need | Control |
|---|---|
| Right model per job | Teams pick a logical route from a platform catalogue, never a model ID. A `costTier` (`economy` / `standard` / `frontier`) is planned; `frontier` needs a written reason. |
| Spend per team, near real time | Every key carries a platform-set `use_case_id` that callers cannot change. Cost is taken from the gateway, not estimated from tokens (cached tokens are priced differently). |
| Stop runaways | Warn at 75% and 90% of budget. At 100% the gateway blocks the key (`HTTP 422`). |

**Status.** The 100% stop works and was tested against real Bedrock calls with a throwaway key (`docs/demo-runtime-evidence.md`). The warnings do not exist yet: nothing sends notifications today. Next, in order:
1. Datadog monitors on `llm_cost_usd_total` per `use_case_id` for the 75% / 90% warnings.
2. Hourly rate limits per use case, so a loop cannot burn a month's budget in an hour.
3. Anomaly detection, which would catch the DigestBot row that no fixed threshold would.

**Why block instead of downgrade.** Each use case has one approved route. Silently switching to a cheaper model could change answer quality or even the classification guarantee without a PR recording it. A short, bounded outage is better than an unbounded bill. Downgrade needs its own declared fallback field first (§7).

## 2. Platform contract and lifecycle

**The declaration.** The first block is built (the Terraform module). The second block is planned.

```yaml
metadata: { id: advisor-chat, team: advisor-chat, owner: ... }  # all required
spec:
  # Built
  dataClassification: confidential
  modelRoute: anthropic-claude-sonnet-bedrock
  budget: { monthlyUsd: 10000 }       # assumption: ~12% above observed spend
  observability: { tier: standard }   # or minimal
  # Planned
  toolPermissions: { allowed: [web_search], requiresApproval: [send_email] }
  reliability: { tier: latency_sensitive }   # or best_effort
  retention: { traceRetentionDays: 180, auditRequired: true }
```

**What each field becomes**

| Field | Enforced as |
|---|---|
| `id`, `team`, `owner` | Resource names and attribution on every request, metric and trace |
| `dataClassification` | Which routes are allowed, plus safe defaults |
| `modelRoute` | The IAM grant (specific Bedrock models only) and the gateway route |
| `budget` | Alert thresholds and the gateway's spend limit |
| `observability.tier` | Which metrics are emitted |
| `toolPermissions` (planned) | The gateway's tool allow-list (§4) |
| `reliability` (planned) | Timeouts, retries, and whether failures page (§5) |
| `retention` (planned) | Trace retention and whether audit is mandatory |

**Inherited defaults.** Teams never set provider, model ID, IAM, EU-only routing or retention. These come from the classification. For example, `confidential` means EU Bedrock only, no content to Datadog, stricter retention. `restricted` is denied until approved. Leaving a field out can never weaken safety.

**Lifecycle**
- **Validate:** `terraform plan` in CI rejects invalid declarations, such as a confidential use case on an unapproved route.
- **Approve:** the platform owner reviews every change to `usecases/` (`.github/CODEOWNERS`). A second platform reviewer for `confidential` or `frontier` is planned. Making the review mandatory needs branch protection, which this repo's GitHub plan does not offer.
- **Change:** a new PR. The `id` never changes; a new identity means a new declaration.
- **Retire:** delete the YAML and its wiring, then apply. This removes the key, IAM grant and alarms (a manual step today).

**People (planned).** Staff sign in through SSO. An IdP group maps to a team, and the team's keys decide which routes a person can use. New users get no access. `confidential` routes need a named group and allow no personal keys, so "who can reach customer data" is answered by group membership.

## 3. Applying the contract

| | AdvisorChat | KYC | DevAgent |
|---|---|---|---|
| Classification | `confidential` | `confidential` or `restricted` (Legal decides) | `internal` |
| Route | Bedrock Sonnet (EU) | Bedrock only | May use `external-llm-zdr` |
| Reliability | `latency_sensitive` | `best_effort`, with an end-to-end deadline | `best_effort` |
| Budget profile | High volume, cheap requests | Low volume, high stakes | Highest spend per request |
| Tools | Almost none | Document fetch, OCR | Code, repos, tickets, wiki |

- **Common:** same contract, catalogue routing, platform-owned attribution, no content in Datadog.
- **Changes through policy:** classification, route, reliability tier, tool allow-list.
- **Justified exception:** DevAgent has the lowest data classification but the highest action risk, because it can write to the wiki, tickets and code. That is why tool permissions are a separate field from classification.

**AdvisorChat credentials.** The app holds no provider key and no Bedrock permission. Its only secret is one route-scoped gateway key in Secrets Manager. Only the gateway's role can call Bedrock or read the external provider key. A leaked app key can only spend AdvisorChat's budget on its approved route.

**DPO / Legal questions (AdvisorChat)**
- **Where can data go?** Only to routes approved for `confidential`: Bedrock through an EU inference profile. That means the EU, not strictly Frankfurt.
- **What do we log, and for how long?** Langfuse traces with content (retention per classification), the gateway's Postgres request log (who, which route, cost; no content), and ALB access logs in S3 (client IP and path, 90 days).
- **How do we reconstruct an interaction?** Join the Postgres request log and the Langfuse trace on the request ID. Datadog is never needed.

## 4. Agentic safety (tools and MCP)

**Where it sits.** In the gateway. It already sees every model call, so it also brokers every tool call: check the allow-list, hold for approval if needed, run, and log. Agents never hold tool credentials; only the gateway does.

**Actions are classified by effect, not by name**

| Class | Examples | Default |
|---|---|---|
| `read_only` | search, read a wiki page | Allowed if on the allow-list |
| `write` / `data_egress` | create a ticket, edit a page, send email | Needs approval |
| `destructive` | delete, run code, merge a PR | Needs approval; denied for higher classifications |

**What every team inherits**
- An empty tool allow-list.
- One key and `use_case_id` per agent, so attribution stays per agent as agents multiply.
- A rolling-window limit on destructive calls per agent (planned). A token budget cannot catch an agent that is cheap but destructive.
- One audit row per tool call (Appendix C).
- `latency_sensitive` use cases get no approval-gated tools, since a human cannot approve in time.

## 5. Observability

**Tool responsibilities.** LiteLLM meters every call. Langfuse explains LLM behaviour, one interaction at a time. Datadog watches platform health across all teams and pages on-call. No signal needs two tools.

| Signal | LiteLLM | Langfuse | Datadog | Why this tool |
|---|:-:|:-:|:-:|---|
| Cost and spend per key, team, model | ✅ | | | The gateway already knows the key, team and token counts for every call. |
| Per-request prompt/response logs | | ✅ | | Searchable next to the trace. LiteLLM's logs are flat, and Datadog charges for log volume (and never receives content here). |
| Multi-step traces (agents, RAG, tool calls) | | ✅ | | Core purpose of Langfuse. LiteLLM sees isolated calls. |
| Evals and user feedback (quality) | | ✅ | | Built for this. LiteLLM has none. |
| Session and user-level LLM analytics | | ✅ | | Groups traces by user and session to debug conversations. |
| Infrastructure metrics (CPU, memory, containers, DBs) | | | ✅ | The other two have no view of infrastructure. |
| APM for non-LLM services (APIs, backend latency) | | | ✅ | Full-stack tracing beyond the LLM layer. |
| Alerting, on-call, SLOs | | | ✅ | Mature incident response. Langfuse alerting is minimal. |
| Gateway health (uptime, error rates, latency) | | | ✅ | LiteLLM exposes the metrics, but something has to watch and alert on them. |

Datadog receives derived metrics only, never prompts, responses or PII.

**SLIs** are the metrics the gateway config defines: requests, errors, throttles, tokens, cost and latency, tagged with `team`, `use_case_id`, `route`, `provider` and `environment`. No user IDs or content. **SLOs** are set per route, because latency belongs to the route (starting targets in Appendix B).

**Quality.** Watch completion length per route against its 7-day baseline to spot sudden changes. Add a small eval set per use case, run on every model or prompt change.

**Alert vs. page.** The rule: customer impact now → page; a trend → ticket.
- **Page:** a route will use up its 30-day error budget in under 2 days; a key hits its 100% budget stop.
- **Ticket:** error budget gone in under 5 days; rising throttles.
- **Notify the owning team:** spend at 75% or 90%.
- **Next business day:** cost or completion-length anomalies.

**Status**
- **Built:** LiteLLM cost metering and Langfuse Cloud traces (EU, synthetic prompts only).
- **Target only:** Datadog, Langfuse evals, self-hosted Langfuse (~$0.7–1.1k/month, assuming the existing cluster is reused).

## 6. Model sourcing

Baseline: $40,258.36 per 30 days (~$483k/year). This excludes one KYC row with no cost (~$192 at the CSV's Sonnet rate). Math in Appendix A.

| Option | Result |
|---|---|
| **A. Stay with current providers and models** | No migration work and no savings. At real EU prices, Sonnet 4.6 costs 10% more than the CSV rates. |
| **B. Newer Anthropic model, same EU route** | Sonnet 5.5 is cheaper, better and faster than Sonnet 4.6: AdvisorChat −26%, KYC −23%. Same provider and data terms. |
| **C. Bedrock open-weight models in the EU** | DevAgent −68% to −89% (GLM-5, MiniMax M2.5), DigestBot −89% (GLM-4.7 Flash). AWS hosts them, so data stays in the EU. |
| **D. Self-host** | **$2.68–3.34 per million tokens**, vs. $0.37 for managed `gpt-oss-120b`. About 7x more expensive. |

**Recommendation per use case.** Full comparison of price, benchmark and latency in [`docs/model-analysis.md`](docs/model-analysis.md).

| Use case | Model | Saving / 30d |
|---|---|--:|
| AdvisorChat (`confidential`, low latency) | Claude Sonnet 5.5 (`eu.`) | $2,358 |
| KYC (`confidential`, audit) | Claude Sonnet 5.5 (`eu.`) | $775 |
| DevAgent (`internal`, agentic) | MiniMax M2.5 or GLM-5 if it passes evals, else Sonnet 5.5 | $5,279–20,927 |
| DigestBot (`internal`, batch) | GLM-4.7 Flash | $1,505 |

Each move needs the team's eval set to pass first. Teams only name a logical route, so a model change is a catalogue PR and teams change nothing. DeepSeek V4.1 and GPT-5.x are not available on Bedrock in the EU (GPT-5.x only through global profiles, which can route data outside the EU). Do not self-host.

**What would change this**
- The open-weight candidates fail DevAgent's eval.
- Security rules out Chinese-origin open-weight models.
- A stronger open-weight model such as DeepSeek V4.1 arrives on EU Bedrock.
- EU open-weight prices rise.
- Self-hosted throughput is above ~1,550 output tokens/s per instance.
- Volume is above ~8B tokens/month (more than two instances can serve, so re-run the math).
- A residency rule appears that no managed provider can meet.

## 7. Six-month plan, rejected alternatives, open questions

**Plan, in dependency order**
1. **Month 0–1**
   - AdvisorChat and DigestBot on the onboarding module (done).
   - Stronger WAF and per-key rate limits.
   - AdvisorChat latency baseline: stream responses, turn on prompt caching for the shared system prompt, and report gateway overhead separately from provider time against the p95 time-to-first-token SLO (Appendix B).
2. **Month 1–3**
   - Add `toolPermissions`, `reliability`, `retention` and the tool broker; these block DevAgent.
   - Optional fallback route per use case, with a short timeout on AdvisorChat so a retry does not double its latency.
   - AdvisorChat fewer round trips: key lookup, route pinning and the spend check served from memory (spend flushed to Postgres asynchronously, not one RDS query per request), and Langfuse/Datadog emission kept off the response path.
   - No tools on the AdvisorChat route (`latency_sensitive` already bars approval-gated tools); `read_only` calls only if run in parallel.
   - Datadog budget and SLO alerts.
   - Onboard KYC once Legal decides its classification.
   - Eval sets for AdvisorChat, KYC, DevAgent and DigestBot.
3. **Month 2–4**
   - Move AdvisorChat and KYC to Sonnet 5.5 once their evals pass.
   - Run DevAgent's evals on MiniMax M2.5, then GLM-5, against a pass bar agreed in advance.
   - Move DigestBot to GLM-4.7 Flash once its eval passes.
4. **Month 4–6**
   - Private network path (Bedrock VPC endpoint, gateway in the app's VPC) so AdvisorChat has no internet leg; re-measure p95 time to first token.
   - Onboard DevAgent.
   - Tune alerts on real traffic.
   - Onboarding by ticket: an issue form that opens the PR for the team.

**Deferred**
- Self-hosting
- A UI or control-plane API
- Multi-region
- Provider failover
- Per-user quotas

**Watch**
- LiteLLM's move to Rust: stay on the pinned image until tested.

**Rejected**
- Apps calling Bedrock directly, or holding provider credentials: both bypass the gateway.
- Free-form model IDs in the declaration: breaks the classification check.
- Onboarding by UI: a PR workflow gives review, history and CI checks for free.
- A control-plane API or EKS: too much for one workload.
- Self-hosting models: ~7x the cost of managed open-weight.

**Open questions**
- **Legal/DPO:** is KYC data `confidential` or `restricted`?
- **Security:** what counts as approval for a tool call, and is an approval UI in scope or are those calls denied until one exists?
- **Leadership:** should budgets follow last month's spend plus a margin, or a forecast?
- **DevAgent team:** does a developer tool need a real SLA?
- **Security/IT:** which IdP groups map to which teams, and may humans use `confidential` routes at all?
- **Security/Procurement:** are Chinese-origin open-weight models (MiniMax, GLM) allowed when AWS hosts them in the EU?
- **Product teams:** who owns each eval set and signs off its pass bar?

## Appendix

Supporting detail. Nothing here changes a conclusion above.

### A. Model sourcing math

**DevAgent today:** about 2.70B input and 1.12B output tokens per month on `gpt-5.4`, costing **$23,507**.

**Same traffic on EU Bedrock** (real EU prices from the AWS Pricing API, 2026-10-03):

| Model | $ per M tokens (in / out) | Cost per month | Saving |
|---|---|--:|--:|
| `gpt-5.4` (today, external provider) | 2.50 / 15.00 | $23,507 | — |
| Claude Sonnet 5.5 | 2.20 / 11.00 | $18,229 | $5,279 |
| Claude Haiku 4.5 | 1.10 / 5.50 | $9,114 | $14,393 |
| GLM-5 | 1.20 / 3.84 | $7,530 | $15,977 |
| MiniMax M2.5 | 0.36 / 1.44 | $2,581 | **$20,927** |
| `gpt-oss-120b` | 0.20 / 0.79 | $1,423 | $22,085 |

Note: EU prices for Anthropic models are about 10% above the rates in the CSV (Sonnet 4.6 is $3.30 / $16.50 in the EU, not $3 / $15). Other use cases are in [`docs/model-analysis.md`](docs/model-analysis.md).

**Self-hosting:**
- **Cost:** two `g5.12xlarge` GPU servers (one spare for failover) cost $10,214/month on EC2 or $12,767 on SageMaker.
- **Per token:** for DevAgent's ~3.82B tokens/month, that is **$2.68–3.34 per M tokens**, vs. **$0.37** for `gpt-oss-120b` on Bedrock. About 7x more.
- **Capacity:** assuming ~450 output tokens/s per server (needs a load test), two servers handle ~8B tokens/month at DevAgent's input/output mix, about 2x today's volume.
- **Break-even:** to match Bedrock's price, each server would need ~1,550 output tokens/s, about 3.4x the assumption (~770 with a 50% discount).

### B. Starting SLOs and alerts

Starting targets, to be tuned after 30 days of real traffic.

| Route | Availability (30d) | p95 time to first token | Output speed (95% of requests at least) |
|---|---:|---:|---:|
| `anthropic-claude-sonnet-bedrock` | 99.5% (3.6h budget) | 2.0s | 30 tokens/s |
| `anthropic-claude-haiku-bedrock` | 99.5% (3.6h budget) | 1.0s | 60 tokens/s |
| `external-llm-zdr` (reasoning model) | 99.0% (7.2h budget) | 15s | 30 tokens/s |

**Why these numbers**
- **Availability:** Bedrock's SLA is 99.9%, and our gateway sits in front of it, so a route can't promise more. The external provider gets less because we have no AWS-backed SLA for it.
- **Time to first token:** the sample traces show 0.3–0.6s. Public medians are 1.15s for Sonnet 4.6 and 0.56s for Haiku 4.5. The reasoning model "thinks" before answering, so its first token is much later.
- **Output speed, not total latency:** total time = time to first token + answer length ÷ speed. A typical 370-token AdvisorChat answer takes ~4–5s, and up to ~14s at these bounds. A fixed total-latency target would fail on every long answer.
- **Metric:** time to first token needs one more gateway metric, `llm_time_to_first_token_seconds`. LiteLLM already exposes it.

| Condition | Action |
|---|---|
| >2% of error budget used in 1h (budget gone in <2 days), one route | **Page** |
| >5% used in 6h (gone in <5 days) | Ticket |
| `llm_provider_throttles_total` rising | Warn; page if it burns budget fast |
| Spend at 75% or 90% | Notify owner |
| Spend at 100%, gateway blocks | **Page** platform and owner |
| Completion-length or cost-per-request anomaly | Warn, next business day |

### C. Tool-call audit row

| Field | Holds |
|---|---|
| `actor` | The agent's own gateway key identity (never shared) |
| `use_case_id` | From provisioned config, never from the caller |
| `tool_name`, `action_class` | What was called and its class |
| `arguments_hash` | SHA-256 of the arguments; full arguments stay in Langfuse if allowed |
| `decision`, `approver` | `allowed` / `denied` / `held_for_approval` / `approved` / `rejected`, and who approved |

The destructive-call limit uses a rolling window, because a fixed window lets up to 2x the limit through at the boundary. Exceeding it denies further calls and pages.
