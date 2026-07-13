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

# Configure the Grafana Provider
# auth is read from the GRAFANA_AUTH environment variable
provider "grafana" {
  url = "https://grafana.brightlysoftware.io/"
}

