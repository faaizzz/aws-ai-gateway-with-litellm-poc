# Split out of main.tf by concern - pure move, no functional change.

data "aws_iam_policy_document" "gateway_bedrock_invoke" {
  count = local.is_bedrock_route ? 1 : 0

  statement {
    sid       = "Invoke${replace(var.use_case.id, "-", "")}Bedrock"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = local.bedrock_resource_arns
  }

  # Anthropic's Bedrock models are distributed via AWS Marketplace even when
  # called through the Bedrock API: found by actually invoking the model
  # through this deployment.
  statement {
    sid       = "Invoke${replace(var.use_case.id, "-", "")}BedrockMarketplaceCheck"
    effect    = "Allow"
    actions   = ["aws-marketplace:ViewSubscriptions"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "gateway_route_policy" {
  count = local.is_bedrock_route ? 1 : 0

  name   = "${local.resource_names.gateway}-bedrock-invoke"
  role   = var.gateway_role_name
  policy = data.aws_iam_policy_document.gateway_bedrock_invoke[0].json
}
