terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  alias  = "deployment"
  region = "us-east-1"
}

provider "aws" {
  alias  = "security"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::533267359674:role/WAF_Provisioner"
  }
}