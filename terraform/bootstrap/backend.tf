# Same state bucket as terraform/environments/dev, separate state key so this
# root's lifecycle is independent of the dev environment it grants CI access
# to.
terraform {
  backend "s3" {
    bucket       = "ai-gateway-tfstate-123456789012"
    key          = "bootstrap/github-oidc.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
