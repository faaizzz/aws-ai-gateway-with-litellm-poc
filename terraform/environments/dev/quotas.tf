# Bedrock service-quota increase request for Claude Haiku 4.5, declared as
# code rather than a manual console click.

resource "aws_servicequotas_service_quota" "haiku_requests_per_minute" {
  service_code = "bedrock"
  quota_code   = "L-CCA5DF70" # Cross-region model inference requests per minute, Claude Haiku 4.5

  # NOT a modest ask originally: found by actually running `terraform apply`
  # that the RequestServiceQuotaIncrease API rejects any value <= 10000.
  value = 10
}

resource "aws_servicequotas_service_quota" "haiku_tokens_per_minute" {
  service_code = "bedrock"
  quota_code   = "L-58BE175A" # Cross-region model inference tokens per minute, Claude Haiku 4.5
  value        = 5000000      # same reasoning as above; approved at the full requested value
}

