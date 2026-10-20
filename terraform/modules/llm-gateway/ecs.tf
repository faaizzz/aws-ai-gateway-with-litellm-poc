# Moved out of terraform/environments/dev/ecs.tf.

resource "aws_ecs_cluster" "gateway" {
  name = "ai-gateway"
}

resource "aws_cloudwatch_log_group" "gateway" {
  name = "/ecs/${local.gateway_name}"
  # Var.log_retention_days - not derived from any one use case's
  # safe_defaults, since this gateway now serves every onboarded use case,
  # not just one.
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "gateway" {
  family                   = local.gateway_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512  # 0.5 vCPU
  memory                   = 2048 # 2 GB: 1 GB was OOM-killed under admin-UI load
  execution_role_arn       = aws_iam_role.gateway_task_execution_role.arn
  task_role_arn            = aws_iam_role.gateway_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "litellm"
      image     = var.litellm_image
      essential = true

      portMappings = [{ containerPort = 4000, protocol = "tcp" }]

      # The proxy's config is generated from this module's own
      # local.litellm_config_yaml and written out at container start.
      entryPoint = ["sh", "-c"]
      command = [
        <<-EOT
        set -eu
        DB_PASSWORD_ENC=$(python3 -c 'import os,urllib.parse; print(urllib.parse.quote(os.environ["DB_PASSWORD"], safe=""))')
        export DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD_ENC@$DB_HOST:5432/$DB_NAME"
        printf '%s' "$LITELLM_CONFIG_YAML" > /tmp/config.yaml
        exec litellm --config /tmp/config.yaml --port 4000 --host 0.0.0.0 --enforce_prisma_migration_check
        EOT
      ]

      environment = [
        { name = "LITELLM_CONFIG_YAML", value = local.litellm_config_yaml },
        { name = "AWS_REGION", value = "eu-central-1" },
        { name = "DB_HOST", value = aws_db_instance.gateway.address },
        { name = "DB_NAME", value = aws_db_instance.gateway.db_name },
        { name = "DB_USER", value = aws_db_instance.gateway.username },
        { name = "LANGFUSE_HOST", value = var.langfuse_host },
      ]

      secrets = concat([
        {
          name      = "LITELLM_MASTER_KEY"
          valueFrom = "${aws_secretsmanager_secret.gateway_key.arn}:key::"
        },
        {
          # A separate, stable value from LITELLM_MASTER_KEY above -
          # LiteLLM otherwise defaults to encrypting its DB-
          # persisted virtual keys with the master key itself.
          name      = "LITELLM_SALT_KEY"
          valueFrom = aws_secretsmanager_secret.gateway_salt_key.arn
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_db_instance.gateway.master_user_secret[0].secret_arn}:password::"
        },
        {
          name      = "LANGFUSE_PUBLIC_KEY"
          valueFrom = "${aws_secretsmanager_secret.langfuse_keys.arn}:public_key::"
        },
        {
          name      = "LANGFUSE_SECRET_KEY"
          valueFrom = "${aws_secretsmanager_secret.langfuse_keys.arn}:secret_key::"
        },
        ],
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.gateway.name
          "awslogs-region"        = "eu-central-1"
          "awslogs-stream-prefix" = "litellm"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "gateway" {
  name            = "ai-gateway-advisor-chat"
  cluster         = aws_ecs_cluster.gateway.id
  task_definition = aws_ecs_task_definition.gateway.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.gateway_task.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.gateway.arn
    container_name   = "litellm"
    container_port   = 4000
  }

  depends_on = [aws_lb_listener.gateway_https]
}
