# Per-IP rate limit in front of the gateway. Motivated by the 2026-09-27 burst
# (~92k unauthenticated probe requests, each of which also became a Langfuse
# trace). WAF rate rules cannot express "per day": the window is 60/120/300/600
# seconds and the minimum limit is 10, so this is a burst limiter, not a quota.
# A real daily quota belongs in LiteLLM per-key limits.

locals {
  waf_config_path = coalesce(var.waf_config_path, "${path.module}/../../catalog/gateway-waf.yaml")
  waf_config      = yamldecode(file(local.waf_config_path))
  waf_window      = local.waf_config.rateLimit.windowSeconds
  waf_limit       = local.waf_config.rateLimit.defaultPerWindow
  waf_limit_trust = local.waf_config.rateLimit.trustedPerWindow
  waf_cidrs       = [for c in try(local.waf_config.trustedCidrs, []) : c.cidr]
  waf_has_trusted = length(local.waf_cidrs) > 0
}

resource "aws_wafv2_ip_set" "trusted" {
  count              = local.waf_has_trusted ? 1 : 0
  name               = "${local.gateway_name}-trusted"
  description        = "IPs that get the higher rate limit"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = local.waf_cidrs
}

resource "aws_wafv2_web_acl" "gateway" {
  name        = local.gateway_name
  description = "Rate limit for the LiteLLM gateway ALB"
  scope       = "REGIONAL"

  lifecycle {
    precondition {
      condition     = contains([60, 120, 300, 600], local.waf_window)
      error_message = "gateway-waf.yaml: rateLimit.windowSeconds must be 60, 120, 300 or 600."
    }
    precondition {
      condition     = local.waf_limit >= 10 && local.waf_limit_trust >= local.waf_limit
      error_message = "gateway-waf.yaml: defaultPerWindow must be >= 10 (WAF minimum) and trustedPerWindow must be >= defaultPerWindow."
    }
    precondition {
      condition     = alltrue([for c in local.waf_cidrs : can(cidrnetmask(c))])
      error_message = "gateway-waf.yaml: every trustedCidrs[].cidr must be an IPv4 CIDR such as 203.0.113.7/32."
    }
  }

  default_action {
    allow {}
  }

  # Everyone except trusted IPs.
  rule {
    name     = "rate-limit-per-ip"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = local.waf_limit
        evaluation_window_sec = local.waf_window
        aggregate_key_type    = "IP"

        dynamic "scope_down_statement" {
          for_each = local.waf_has_trusted ? [1] : []
          content {
            not_statement {
              statement {
                ip_set_reference_statement {
                  arn = aws_wafv2_ip_set.trusted[0].arn
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.gateway_name}-rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  # Trusted IPs: a higher limit, not an exemption.
  dynamic "rule" {
    for_each = local.waf_has_trusted ? [1] : []
    content {
      name     = "rate-limit-trusted-ip"
      priority = 2

      action {
        block {}
      }

      statement {
        rate_based_statement {
          limit                 = local.waf_limit_trust
          evaluation_window_sec = local.waf_window
          aggregate_key_type    = "IP"

          scope_down_statement {
            ip_set_reference_statement {
              arn = aws_wafv2_ip_set.trusted[0].arn
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.gateway_name}-rate-limit-trusted-ip"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.gateway_name
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "gateway" {
  resource_arn = aws_lb.gateway.arn
  web_acl_arn  = aws_wafv2_web_acl.gateway.arn
}
