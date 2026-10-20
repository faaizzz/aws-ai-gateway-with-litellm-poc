# required_version/required_providers used to live inline at the top of
# main.tf.

terraform {
  # >= 1.11: the floor for write-only resource arguments referencing an
  # ephemeral value.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 5.100.0: the floor for secret_string_wo/
      # secret_string_wo_version on aws_secretsmanager_secret_version,
      # verified against this exact version.
      version = ">= 5.100.0, < 6.0.0"
    }
    random = {
      source = "hashicorp/random"
      # >= 3.7.0 up to <4.0.0.
      version = ">= 3.7.0, < 4.0.0"
    }
  }
}
