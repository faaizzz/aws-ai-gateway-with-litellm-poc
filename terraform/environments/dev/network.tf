# Demo/PoC networking: default VPC/subnets, resolved here and passed into
# module.llm_gateway as vpc_id/subnet_ids.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
