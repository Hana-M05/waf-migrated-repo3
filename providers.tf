terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  alias  = "deployment"
  region = "us-east-1"
}

data "aws_secretsmanager_secret_version" "grafana_auth" {                                  
    provider  = aws.deployment                                                               
    secret_id = "waf-provisioner/grafana-config"
  }   

# Configure the Grafana Provider
# auth is read from the GRAFANA_AUTH environment variable
provider "grafana" {
  url = jsondecode(data.aws_secretsmanager_secret_version.grafana_auth.secret_string)["url"]
  auth = jsondecode(data.aws_secretsmanager_secret_version.grafana_auth.secret_string)["api_token"]
}

