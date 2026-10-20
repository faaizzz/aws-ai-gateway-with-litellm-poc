# Moved out of terraform/environments/dev/rds.tf verbatim - RDS Postgres
# backing the gateway's own key/config/spend/request-log storage.

resource "aws_db_subnet_group" "gateway" {
  name       = "ai-gateway-db"
  subnet_ids = var.subnet_ids
}

resource "aws_db_instance" "gateway" {
  identifier     = "ai-gateway-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_encrypted = true

  db_name  = "litellm"
  username = "litellm_admin"
  # AWS-managed master password: generated and rotated in Secrets Manager,
  # never a plaintext Terraform value.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.gateway.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false
  skip_final_snapshot    = true
  deletion_protection    = false # demo environment (10-day demo)

  # . skip_final_snapshot = true above means a destroy loses this data
  # anyway;
  backup_retention_period = 0
}
