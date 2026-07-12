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
# Note: Credentials should be set via environment variables or Terraform variables
# GRAFANA_AUTH environment variable can contain the API token
provider "grafana" {
  # URL and authentication configured via environment or variables
  # Example: GRAFANA_AUTH="Bearer <token>" or via grafana_auth variable
}

