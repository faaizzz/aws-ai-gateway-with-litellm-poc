# required_version/required_providers used to live inline at the top of
# providers.tf.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 5.100.0: module.llm_gateway writes secret_string_wo directly,
      # the same floor the use-case module's own versions.tf now states
      # explicitly.
      version = ">= 5.100.0, < 6.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.0, < 4.0.0"
    }
  }
}
