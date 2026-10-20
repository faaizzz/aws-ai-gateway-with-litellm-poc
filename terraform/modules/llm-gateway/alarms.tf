# Early warning before the gateway task is OOM-killed (exit 137). No
# alarm_actions: this module owns no SNS topic, so the alarm is visible in the
# CloudWatch console; wiring it to a notification topic is a later step.
resource "aws_cloudwatch_metric_alarm" "gateway_memory_high" {
  alarm_name          = "${local.gateway_name}-memory-high"
  alarm_description   = "Gateway ECS service memory above 80% for 10 minutes - the task is close to being OOM-killed."
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.gateway.name
    ServiceName = aws_ecs_service.gateway.name
  }
}

# The RDS-managed master password rotates on its own, but the running task only
# reads DB_PASSWORD at start, so after a rotation every DB-backed call fails
# until the service is redeployed. LiteLLM logs this line on each failed reconnect.
resource "aws_cloudwatch_log_metric_filter" "gateway_db_reconnect_failed" {
  name           = "${local.gateway_name}-db-reconnect-failed"
  log_group_name = aws_cloudwatch_log_group.gateway.name
  pattern        = "\"Prisma DB reconnect failed\""

  metric_transformation {
    name          = "DbReconnectFailed"
    namespace     = "AiGateway/${local.gateway_name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "gateway_db_reconnect_failed" {
  alarm_name          = "${local.gateway_name}-db-reconnect-failed"
  alarm_description   = "Gateway cannot reconnect to its database (usually a rotated RDS master password). Force a new ECS deployment - see docs/known-limitations.md."
  namespace           = "AiGateway/${local.gateway_name}"
  metric_name         = "DbReconnectFailed"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}
