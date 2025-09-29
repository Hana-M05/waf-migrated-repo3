# Initialization
terraform init -backend-config ./environments/${PRODUCT}/${ENVIRONMENT}-backend.tfvars
# Plan
terraform plan -var-file=./environments/${PRODUCT}/${ENVIRONMENT}.tfvars 