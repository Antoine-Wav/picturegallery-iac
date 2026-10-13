data "aws_caller_identity" "current" {}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

locals {
  name_prefix     = "cse-sbx-${var.trigram}-${var.region_short}"
  selected_ami_id = var.ec2_ami_id != "" ? var.ec2_ami_id : data.aws_ami.amazon_linux_2023.id

  tags = merge(
    {
      Project     = var.project_tag
      Environment = var.environment
      Trainee     = var.trigram
      ManagedBy   = "terraform"
    },
    var.common_tags
  )

  # Resource names built from the naming convention
  vpc_name                    = "${local.name_prefix}-vpc-main-01"
  subnet_az1_name             = "${local.name_prefix}-subnet-public-01"
  subnet_az2_name             = "${local.name_prefix}-subnet-public-02"
  internet_gw_name            = "${local.name_prefix}-igw-main-01"
  route_table_name            = "${local.name_prefix}-rt-public-01"
  web_sg_name                 = "${local.name_prefix}-sg-web-01"
  db_sg_name                  = "${local.name_prefix}-sg-db-01"
  ec2_name                    = "${local.name_prefix}-ec2-app-01"
  generated_ec2_key_pair_name = "${local.name_prefix}-keypair-app-01"
  ec2_key_pair_name           = var.ec2_key_pair_name != "" ? var.ec2_key_pair_name : local.generated_ec2_key_pair_name
  db_subnet_group             = "${local.name_prefix}-dbsubnet-main-01"
  db_parameter_group          = "${local.name_prefix}-dbparam-mysql-01"
  db_identifier               = "${local.name_prefix}-mysql-01"
  logo_bucket_name            = lower("${local.name_prefix}-${var.logo_bucket_purpose}-${data.aws_caller_identity.current.account_id}")
  logs_bucket_name            = lower("${local.name_prefix}-${var.logs_bucket_purpose}-${data.aws_caller_identity.current.account_id}")
}