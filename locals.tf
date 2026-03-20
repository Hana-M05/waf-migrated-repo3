locals {
  # Find all YAML files in environments directory
  config_files = fileset("${path.module}/environments", "**/*.yaml")

  # Parse all configurations and create a map
  environments = {
    for config_file in local.config_files :
    # Create key from file path: "product1/dev.yaml" becomes "product1-dev"
    replace(replace(config_file, "/", "-"), ".yaml", "") => yamldecode(file("${path.module}/environments/${config_file}"))
  }

  waf_update_monitors = [
    "productops@brightlysoftware.com",
    "amritpal.singh@brightlysoftware.com",
    "tyler.bassett@brightlysoftware.com",
    "amanda.reams@brightlysoftware.com",
    "sam.mcmanus@siemens.com"
  ]

  alloy_s3_buckets = {
    "us-east-1"      = "arn:aws:s3:::aw-ue1-ob1-alloy-audit-logs"
    "us-east-2"      = "arn:aws:s3:::aw-ue1-ob1-alloy-audit-logs"
    "eu-west-2"      = "arn:aws:s3:::aw-ew2-ob1-alloy-audit-logs"
    "ap-south-1"     = "arn:aws:s3:::aw-ue1-ob1-alloy-audit-logs"
    "ap-southeast-2" = "arn:aws:s3:::aw-as2-ob1-alloy-audit-logs"
    "ca-central-1"   = "arn:aws:s3:::aw-ue1-ob1-alloy-audit-logs"
  }
}