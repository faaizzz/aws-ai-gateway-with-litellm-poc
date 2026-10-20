# Sample data

Both files are **synthetic**. The organisation, teams, keys, prompts and figures are made up to illustrate the design; none of it is real usage.

| File | What it shows |
|---|---|
| `sample_spend_30d.csv` | 30 days (2026-03-01..30) of per-key LLM spend, 150 rows: `date, api_key, team, model, request_count, prompt_tokens, completion_tokens, cost_usd`. |
| `sample_traces.json` | Five LiteLLM → Langfuse observations, including a Bedrock throttle and cache-read tokens. |

## Spend totals (30 days)

| Team | Cost |
|---|--:|
| DevAgent | $23,507.28 |
| AdvisorChat | $8,915.04 |
| KYC | $3,434.07 |
| *Unattributed* | $2,418.97 |
| DigestBot | $1,691.28 |
| Research | $289.07 |
| Marketing | $2.65 |
| **Total** | **$40,258.36** |

## Deliberate anomalies

Asserted by `tests/policy/spend_quality_checks.py`:

- 4 rows with no `team` (keys `key-research-shared` and `key-personal-jdoe`)
- 1 KYC row with no `cost_usd`
- 1 DigestBot row with $9.85 cost and zero requests

They also contain patterns the design discusses: a DevAgent agent loop from 2026-03-16 (output tokens per request ~1,170 → ~4,990), and five AdvisorChat days on `gpt-4o` ($78.21), a provider not approved for `confidential` data.

## Traces and classification mapping

The traces use `data_class` values `pii_sensitive` / `no_pii`; this repo maps them to `confidential` / `internal`. Attribution in the traces is only via `team`, `product` and `litellm_proxy_key_alias` (no `use_case_id`), and cost comes from the provider-reported `costDetails`, since cached tokens are priced differently.
