terraform {
  backend "s3" {
    region  = "us-east-1"
    bucket  = "s3-ue1-sharedservices-tfstate"
    key     = "aws-waf-tf-code.tfstate"
    encrypt = true
  }
}