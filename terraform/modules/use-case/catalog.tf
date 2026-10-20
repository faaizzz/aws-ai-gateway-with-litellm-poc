# Split out of main.tf by concern - pure move, no functional change.

locals {
  # Platform-owned catalogue: the only place a logical route resolves to a
  # real provider/model.
  catalog_path = coalesce(var.catalog_path, "${path.module}/../../catalog/approved-models.yaml")
  catalog      = yamldecode(file(local.catalog_path))

  resolved_route = try(local.catalog.routes[var.use_case.model_route], null)
  route_exists   = local.resolved_route != null

  # ---- Bedrock resource resolution ----
  # Only Bedrock routes need IAM;
  is_bedrock_route = local.route_exists && local.resolved_route.provider == "bedrock"

  # The catalogue's model_id is the EU cross-region inference-profile ID.
  bedrock_foundation_model_arns = local.is_bedrock_route ? [
    for region in local.resolved_route.profile_regions :
    "arn:aws:bedrock:${region}::foundation-model/${trimprefix(local.resolved_route.model_id, "eu.")}"
  ] : []

  bedrock_inference_profile_arn = local.is_bedrock_route ? "arn:aws:bedrock:${local.resolved_route.region}:${data.aws_caller_identity.current.account_id}:inference-profile/${local.resolved_route.model_id}" : null

  bedrock_resource_arns = local.is_bedrock_route ? concat(
    [local.bedrock_inference_profile_arn],
    local.bedrock_foundation_model_arns
  ) : []
}
