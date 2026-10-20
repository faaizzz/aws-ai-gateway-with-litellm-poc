# LiteLLM model_list built from the platform-owned catalogue directly - not
# from any use case's resolved route.
locals {
  catalog_path = coalesce(var.catalog_path, "${path.module}/../../catalog/approved-models.yaml")
  catalog      = yamldecode(file(local.catalog_path))

  # Only bedrock-provider routes: the external-llm-zdr route is catalogued
  # and already deny-by-default for confidential data via the use-case
  # module's own classification.
  bedrock_routes = {
    for name, route in local.catalog.routes : name => route
    if route.provider == "bedrock"
  }

  litellm_model_list = [
    for name, route in local.bedrock_routes : {
      model_name = name
      litellm_params = {
        model           = "${route.provider}/${route.model_id}"
        aws_region_name = route.region
      }
    }
  ]

  # LiteLLM model_list entry, generated from the catalogue so the deployed
  # config can never drift from what Terraform validated.
  litellm_config_yaml = yamlencode({
    model_list = local.litellm_model_list
    # Every call is logged to Langfuse, success or failure, so the trace
    # record is the audit/reconstruction path DPO/Legal need - not just
    # successful calls.
    litellm_settings = {
      success_callback = ["langfuse"]
      failure_callback = ["langfuse"]
    }
    general_settings = {
      master_key = "os.environ/LITELLM_MASTER_KEY"
    }
  })
}
