# Moved out of terraform/environments/dev/network.tf verbatim - same
# standalone-rule design, same rule content, only the module location changed.

# ---- Security groups (existence/name/description only - rules below) ----
resource "aws_security_group" "alb" {
  name        = "ai-gateway-alb"
  description = "ALB ingress for the LiteLLM demo gateway"
  vpc_id      = var.vpc_id
}

resource "aws_security_group" "gateway_task" {
  name        = "ai-gateway-task"
  description = "LiteLLM ECS task: inbound from ALB only, outbound to Bedrock/ECR/Secrets Manager/CloudWatch/registry"
  vpc_id      = var.vpc_id
}

resource "aws_security_group" "rds" {
  name        = "ai-gateway-rds"
  description = "RDS Postgres: inbound from the gateway task only"
  vpc_id      = var.vpc_id
}

# ---- ALB rules ----
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from anywhere (demo - no WAF/allow-list in this PoC)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# Scoped to the VPC's own CIDR and the target group's port, not 0.0.0.0/0 -
# the ALB only ever forwards to the gateway task, which lives in the same VPC.
resource "aws_vpc_security_group_egress_rule" "alb_to_gateway_task" {
  security_group_id = aws_security_group.alb.id
  description       = "To the gateway task LiteLLM port, within the VPC only"
  ip_protocol       = "tcp"
  from_port         = 4000
  to_port           = 4000
  cidr_ipv4         = var.vpc_cidr_block
}

# ---- gateway_task rules ----
resource "aws_vpc_security_group_ingress_rule" "gateway_task_from_alb" {
  security_group_id            = aws_security_group.gateway_task.id
  description                  = "LiteLLM proxy port from the ALB only"
  ip_protocol                  = "tcp"
  from_port                    = 4000
  to_port                      = 4000
  referenced_security_group_id = aws_security_group.alb.id
}

# Genuinely broad by design, not an oversight - no NAT Gateway or VPC
# interface endpoints;
# trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "gateway_task_egress" {
  security_group_id = aws_security_group.gateway_task.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---- RDS rules ----
resource "aws_vpc_security_group_ingress_rule" "rds_from_gateway_task" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Postgres from the gateway task only"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.gateway_task.id
}

# rds_egress_removed: removed the RDS security group's egress rule entirely -
# a managed RDS Postgres instance has no legitimate reason to initiate
# outbound connections.
