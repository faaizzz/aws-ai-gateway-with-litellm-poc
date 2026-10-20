# Moved out of terraform/environments/dev/main.tf and iam.tf verbatim.

data "aws_iam_policy_document" "gateway_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "gateway_task_role" {
  name               = "ai-gateway-task-role"
  assume_role_policy = data.aws_iam_policy_document.gateway_assume_role.json
}

resource "aws_iam_role" "gateway_task_execution_role" {
  name               = "ai-gateway-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.gateway_assume_role.json
}

resource "aws_iam_role_policy_attachment" "gateway_task_execution" {
  role       = aws_iam_role.gateway_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The execution role resolves container `secrets` at task start - it needs
# read access to exactly the secrets this task references.
data "aws_iam_policy_document" "gateway_task_execution_secrets" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.gateway_key.arn,
      aws_secretsmanager_secret.gateway_salt_key.arn,
      aws_db_instance.gateway.master_user_secret[0].secret_arn,
      aws_secretsmanager_secret.langfuse_keys.arn,
    ]
  }
}

resource "aws_iam_role_policy" "gateway_task_execution_secrets" {
  name   = "read-gateway-secrets"
  role   = aws_iam_role.gateway_task_execution_role.name
  policy = data.aws_iam_policy_document.gateway_task_execution_secrets.json
}
