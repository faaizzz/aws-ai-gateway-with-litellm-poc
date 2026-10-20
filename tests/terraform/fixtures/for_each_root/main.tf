# Test fixture: reproduces exactly the for_each-keying and duplicate-id-
# detection logic that terraform/environments/dev/main.tf applies to the real
# usecases/ directory.

terraform {
  required_version = ">= 1.11.0"
}

variable "usecases_dir" {
  type = string
}

locals {
  usecase_files = fileset(var.usecases_dir, "*.yaml")

  usecase_declarations_by_file = {
    for f in local.usecase_files :
    f => yamldecode(file("${var.usecases_dir}/${f}"))
  }

  # Grouped, same reasoning as the real main.tf: a plain `id => decl` map
  # errors outright on a duplicate key.
  usecase_declarations_grouped = {
    for decl in values(local.usecase_declarations_by_file) :
    decl.metadata.id => decl...
  }

  usecase_declarations = {
    for id, decls in local.usecase_declarations_grouped :
    id => decls[0]
  }
}

resource "terraform_data" "usecase_id_uniqueness" {
  input = length(local.usecase_files)

  lifecycle {
    precondition {
      condition = alltrue([
        for id, decls in local.usecase_declarations_grouped : length(decls) == 1
      ])
      error_message = "Two or more usecases/*.yaml files declare the same metadata.id: ${join(", ", [for id, decls in local.usecase_declarations_grouped : id if length(decls) > 1])}. Each declaration's metadata.id must be unique."
    }
  }
}

output "usecase_ids" {
  value = keys(local.usecase_declarations)
}

output "usecase_count" {
  value = length(local.usecase_declarations)
}
