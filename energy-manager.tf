provider "aws" {
  alias  = "energy_manager_dev_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::059090138953:role/WAF_Provisioner"
  }
}

provider "aws" {
  alias  = "energy_manager_prod_us_east_1"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::875142387490:role/WAF_Provisioner"
  }
}


#########################################################################
########################### Penalty Box (Dev) ###########################
# Deployed to EM-DEV first. Once validated, add an equivalent block for
# prod by duplicating this module call with the prod provider alias.
#########################################################################
module "penalty_box_energy_manager_dev" {
  source = "./modules/penalty-box"

  providers = {
    aws = aws.energy_manager_dev_us_east_1
  }

  environment = "energy-manager-dev-us-east-1"
}

#########################################################################
########################### Firehose IAM Role ###########################
#########################################################################
module "firehose_role_policy_energy_manager_dev" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.energy_manager_dev_us_east_1
  }

  s3_bucket_arns          = concat(values(local.alloy_s3_buckets), [module.penalty_box_energy_manager_dev.log_bucket_arn])
  lambda_processor_arn    = module.penalty_box_energy_manager_dev.lambda_arn
  enable_lambda_processor = true
}

module "firehose_role_policy_energy_manager_prod" {
  source = "./modules/firehose-role-policy"

  providers = {
    aws = aws.energy_manager_prod_us_east_1
  }

  s3_bucket_arns = values(local.alloy_s3_buckets)
}

#########################################################################
########################### EVM Dev Modules #############################
#########################################################################

module "waf_wrapper_energy_manager_dev_us_east_1" {
  depends_on = [module.firehose_role_policy_energy_manager_dev, module.penalty_box_energy_manager_dev]
  source     = "./modules/waf-wrapper"

  providers = {
    aws = aws.energy_manager_dev_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                = local.environments["energy-manager-dev-us-east-1"].alb_arns
  api_gateway_ids         = local.environments["energy-manager-dev-us-east-1"].api_gateway_ids
  disabled_rules          = local.environments["energy-manager-dev-us-east-1"].disabled_rules
  environment             = "energy-manager-dev-us-east-1"
  firehose_destination    = local.alloy_s3_buckets[local.environments["energy-manager-dev-us-east-1"].region]
  firehose_role_arn       = module.firehose_role_policy_energy_manager_dev.firehose_role_arn
  global                  = local.environments["energy-manager-dev-us-east-1"].global
  log_forward_destination = "arn:aws:s3:::bsw-siem-waf"
  protection_rules        = local.environments["energy-manager-dev-us-east-1"].protection_rules
  redacted_headers        = local.environments["energy-manager-dev-us-east-1"].redacted_headers
  waf_error_subscribers   = local.environments["energy-manager-dev-us-east-1"].waf_error_subscribers
  lambda_processor_arn    = module.penalty_box_energy_manager_dev.lambda_arn
  s3_backup_bucket_arn    = module.penalty_box_energy_manager_dev.log_bucket_arn
}

#########################################################################
########################### EVM Prod Modules ############################
#########################################################################

module "waf_wrapper_energy_manager_prod_us_east_1" {
  depends_on = [module.firehose_role_policy_energy_manager_prod]
  source     = "./modules/waf-wrapper"

  providers = {
    aws = aws.energy_manager_prod_us_east_1
  }

  # Key = environments/<subpath>/<filename>
  alb_arns                = local.environments["energy-manager-prod-us-east-1"].alb_arns
  api_gateway_ids         = local.environments["energy-manager-prod-us-east-1"].api_gateway_ids
  disabled_rules          = local.environments["energy-manager-prod-us-east-1"].disabled_rules
  environment             = "energy-manager-prod-us-east-1"
  firehose_destination    = local.alloy_s3_buckets[local.environments["energy-manager-prod-us-east-1"].region]
  firehose_role_arn       = module.firehose_role_policy_energy_manager_prod.firehose_role_arn
  global                  = local.environments["energy-manager-prod-us-east-1"].global
  log_forward_destination = "arn:aws:s3:::bsw-siem-waf"
  protection_rules        = local.environments["energy-manager-prod-us-east-1"].protection_rules
  redacted_headers        = local.environments["energy-manager-prod-us-east-1"].redacted_headers
  waf_error_subscribers   = local.environments["energy-manager-prod-us-east-1"].waf_error_subscribers
}