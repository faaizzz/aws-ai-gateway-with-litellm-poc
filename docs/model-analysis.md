# Model analysis: cheapest Bedrock models per use case

Supporting analysis for `design.md` §6. Prices and availability checked on **2026-10-03** against an AWS account (`eu-central-1` and the other EU regions).

**Question.** Which models on Bedrock, available today, meet our requirements at the lowest cost, considering price, benchmark and latency? Which one should each use case use?

## 1. Method

| Input | Source |
|---|---|
| Token volume per team | `data/sample_spend_30d.csv` (synthetic, 30 days, prompt and completion tokens per team) |
| Price | AWS Pricing API (`AmazonBedrock`, `AmazonBedrockFoundationModels`), standard on-demand rate per region. Batch, flex, priority and global-profile rates excluded unless stated. |
| Availability | `aws bedrock list-foundation-models` and `list-inference-profiles`, per EU region |
| Benchmark | Artificial Analysis Intelligence Index v4.3.2 (higher is better) |
| Latency | Artificial Analysis output speed (tokens/s) and time to first token (TTFT). These are medians across providers, not Bedrock measurements. |

**Requirements used as filters**
1. **EU residency.** The model runs in an EU region (in-region on-demand) or through an `eu.` inference profile. Global profiles (`global.*`) can route requests outside the EU and are excluded.
2. **Callable today**, with status `ACTIVE`.
3. **Text chat with tool use**, so it works for agentic workloads.
4. **Classification.** `confidential` use cases (AdvisorChat, KYC) stay on routes the DPO already knows. Today that is Anthropic on an `eu.` profile.

**Excluded by the residency filter.** These are listed in Frankfurt, but only through `global.*` profiles: OpenAI GPT-5.4 / 5.5 / 5.6 / 6 / 6.1, Moonshot Kimi K3, xAI Grok 4.6 / 4.7. GPT-5.4 is what DevAgent uses today through the external ZDR provider. It cannot move to Bedrock without leaving the EU.

**Not on Bedrock at all.** DeepSeek V4.1 Flash (open weights, MIT licence, September 2026) currently leads open-weight models on the Vals Index. The only ways to use it are DeepSeek's own API (data leaves the EU, so it is ruled out) or self-hosting a 552B-parameter model (see `design.md` Appendix A). Recheck when it lands on EU Bedrock.

## 2. Corrected prices

The rates fitted from the CSV are not what Bedrock charges in the EU today. Anthropic models on an `eu.` profile carry a ~10% regional premium.

| Model | Fitted from CSV ($/M in / out) | EU Bedrock today ($/M in / out) |
|---|---|---|
| Claude Sonnet 4.6 | 3.00 / 15.00 | **3.30 / 16.50** |
| Claude Haiku 4.5 | 0.80 / 4.00 | **1.10 / 5.50** |
| gpt-oss-120b (Frankfurt) | — | 0.20 / 0.79 (confirmed) |

What this changes:
- Moving DevAgent to Haiku saves **$14,393**/30d, not the $16,879 calculated from CSV rates.
- At real EU prices, AdvisorChat on Sonnet 4.6 would cost **$9,835**, using almost all of the assumed $10,000 budget.

## 3. Candidates

These are the 30-day costs on each team's token volume in the sample data. The "Today" row is the CSV cost.

| Model | Where | Score | tok/s | TTFT | AdvisorChat | KYC | DevAgent | DigestBot | $/M in / out |
|---|---|--:|--:|--:|--:|--:|--:|--:|---|
| *Today (CSV)* | | | | | *$8,915* | *$3,434* | *$23,507* | *$1,691* | |
| Claude Sonnet 4.6 (current route) | `eu.` profile | 25 | 44 | 1.15s | $9,835 | $3,989 | $27,343 | $6,936 | 3.30 / 16.50 |
| **Claude Sonnet 5.5** (medium) | `eu.` profile | **41** | 99 | 1.23s | **$6,557** | **$2,659** | $18,229 | $4,624 | 2.20 / 11.00 |
| Claude Haiku 4.5 | `eu.` profile | 15 | 89 | **0.56s** | $3,278 | $1,330 | $9,114 | $2,312 | 1.10 / 5.50 |
| GLM-5 | Stockholm | 28 | 75 | 1.54s | $2,909 | $1,228 | $7,530 | $2,025 | 1.20 / 3.84 |
| GLM-4.7 | Stockholm | 22 | 69 | 1.26s | $1,849 | $771 | $4,893 | $1,292 | 0.72 / 2.64 |
| Kimi K2.5 | Stockholm | 23 | n/a | n/a | $2,146 | $870 | $5,966 | $1,513 | 0.72 / 3.60 |
| DeepSeek V3.2 | Stockholm | 16 | n/a | n/a | $1,748 | $742 | $4,478 | $1,215 | 0.74 / 2.22 |
| **MiniMax M2.5** | Frankfurt | 23 | 91 | 1.39s | $962 | $398 | **$2,581** | $674 | 0.36 / 1.44 |
| Qwen3 235B 2507 | Frankfurt | 12 | 58 | 2.43s | $775 | $321 | $2,079 | $543 | 0.29 / 1.16 |
| gpt-oss-120b | Frankfurt | 12 | 160 | 0.83s | $531 | $220 | $1,423 | $372 | 0.20 / 0.79 |
| gpt-oss-120b (batch) | Frankfurt | 12 | — | — | $267 | $111 | $717 | $187 | 0.10 / 0.40 |
| Nemotron 3 Super 120B | Frankfurt | 13 | 162 | 1.33s | $499 | $205 | $1,357 | $351 | 0.18 / 0.78 |
| **GLM-4.7 Flash** | Frankfurt | 15 | 65 | 1.55s | $263 | $105 | $752 | **$187** | 0.08 / 0.48 |

For reference, GPT-5.4 (xhigh) scores 39 on the same index.

**What the table shows**
- **Sonnet 5.5 beats Sonnet 4.6 on everything:** about 1/3 cheaper, a much higher score, and more than twice the output speed. It uses the same provider, `eu.` profile and data terms.
- **Haiku 4.5 is beaten on cost and score.** MiniMax M2.5 and GLM-5 both score higher and cost less. Haiku still has the best TTFT.
- **For bulk text work, the cheapest models score about the same as Haiku** (GLM-4.7 Flash 15, Nemotron 13, gpt-oss 12) at roughly 1/10 of the price.

## 4. Recommendation per use case

| Use case | Needs | Recommend | 30d cost | Saving | Fallback |
|---|---|---|--:|--:|---|
| **AdvisorChat** | `confidential`, customer-facing, low latency, quality | **Claude Sonnet 5.5** (`eu.`) | $6,557 | −$2,358 (−26%) | Sonnet 4.6 |
| **KYC** | `confidential`/`restricted`, accuracy, full audit | **Claude Sonnet 5.5** (`eu.`) | $2,659 | −$775 (−23%) | Sonnet 4.6 |
| **DevAgent** | `internal`, agentic coding, highest spend | Eval **MiniMax M2.5**, then **GLM-5** | $2,581 / $7,530 | −$20,927 (−89%) / −$15,977 (−68%) | Claude Sonnet 5.5 ($18,229, −22%) |
| **DigestBot** | `internal`, batch, cost-sensitive | **GLM-4.7 Flash** (Frankfurt) | $187 | −$1,505 (−89%) | gpt-oss-120b batch ($187) |
| **Research** | bursty, exploratory | Claude Sonnet 5.5 | $209 | −$80 | — |
| **Marketing** | low volume | Claude Haiku 4.5 | ~$8 | ~+$6 (not material) | — |

**Why each choice**
- **AdvisorChat.** The quality of answers to customers comes first, and the data is `confidential`. Sonnet 5.5 is cheaper, better and faster than the current route, with no change in provider or residency. It's the lowest-risk saving in the whole analysis. Haiku has the best TTFT (0.56s), but a score of 15 is too low for financial Q&A. It could later serve simple intents behind a router.
- **KYC.** Accuracy and audit come first. Keep regulated data on the Anthropic EU route Legal already knows, and don't move it to newer open-weight vendors. Volume is low, so the saving is small anyway.
- **DevAgent.** This is where the money is (58% of spend). It's an internal workload, so open-weight models hosted by AWS in the EU are acceptable on data grounds. MiniMax M2.5 and GLM-5 are both aimed at agentic coding and both score higher than Haiku. Pick the cheapest one that passes DevAgent's eval set. If none does, Sonnet 5.5 outscores today's GPT-5.4 and still saves ~$5.3k.
- **DigestBot.** Summarisation doesn't need a frontier model, and latency doesn't matter for batch. GLM-4.7 Flash matches Haiku's score at ~1/12 of the EU Haiku price. gpt-oss-120b in batch mode is an equal-cost alternative with a better-known vendor.

**Total for the four main use cases** (vs. CSV cost of $37,548)
- **Recommended mix:** saves **~$25.6k / 30 days** (~68%).
- **Conservative mix** (DevAgent on Sonnet 5.5 instead of an open-weight model): saves **~$9.9k / 30 days**.

## 5. Caveats

- **Benchmarks are medians across providers, not Bedrock-specific,** and come from one general index. Each team's own eval set decides; nothing moves without passing it.
- **Reasoning effort changes cost and latency.** A higher effort setting produces more output tokens. The costs above assume today's token counts, so they are a lower bound for reasoning models. Different tokenizers also count the same text differently.
- **Model origin.** MiniMax, GLM (Z AI), Kimi and DeepSeek are Chinese open-weight models. On Bedrock, AWS runs them and no data goes to the model vendor, but Security must still decide whether they are allowed. This is an open question in `design.md`.
- **Several of these models are already marked deprecated** by Artificial Analysis (Sonnet 4.6, GLM-5, MiniMax M2.5, Qwen3 235B), with newer versions out. Recheck when each eval runs.
- **Prices and availability change often.** Re-run this analysis before any route change.

## 6. Reproduce

```bash
source .env.aws
# Availability per EU region
aws bedrock list-foundation-models --region eu-central-1 \
  --query "modelSummaries[].[modelId,join(',',inferenceTypesSupported)]" --output text
# Which regions an inference profile routes to (eu.* stays in the EU, global.* does not)
aws bedrock list-inference-profiles --region eu-central-1 \
  --query "inferenceProfileSummaries[].[inferenceProfileId,models[].modelArn]"
# Prices
aws pricing get-products --region us-east-1 --service-code AmazonBedrock \
  --filters Type=TERM_MATCH,Field=regionCode,Value=eu-central-1
```

Cost per model = team input tokens / 1M × input price + team output tokens / 1M × output price, using each team's 30-day totals from the CSV.

## Sources

- AWS Pricing API and Bedrock APIs, 2026-10-03
- [Artificial Analysis leaderboard](https://artificialanalysis.ai/leaderboards/models)
- Artificial Analysis model pages: [Claude Sonnet 4.6](https://artificialanalysis.ai/models/claude-sonnet-4-6), [Claude Haiku 4.5](https://artificialanalysis.ai/models/claude-4-5-haiku), [GLM-5](https://artificialanalysis.ai/models/glm-5), [GLM-4.7](https://artificialanalysis.ai/models/glm-4-7), [GLM-4.7 Flash](https://artificialanalysis.ai/models/glm-4-7-flash), [MiniMax M2.5](https://artificialanalysis.ai/models/minimax-m2-5), [Kimi K2.5](https://artificialanalysis.ai/models/kimi-k2-5), [DeepSeek V3.2](https://artificialanalysis.ai/models/deepseek-v3-2), [gpt-oss-120b](https://artificialanalysis.ai/models/gpt-oss-120b), [Qwen3 235B](https://artificialanalysis.ai/models/qwen3-235b-a22b-instruct-2507), [GPT-5.4](https://artificialanalysis.ai/models/gpt-5-4)
- [Vals AI: DeepSeek V4.1 Flash](https://www.vals.ai/models/deepseek_deepseek-v4.1-flash)
