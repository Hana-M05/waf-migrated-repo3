locals {
  # Find all YAML files in environments directory
  config_files = fileset("${path.module}/environments", "**/*.yaml")
  
  # Parse all configurations and create a map
  environments = {
    for config_file in local.config_files : 
    # Create key from file path: "product1/dev.yaml" becomes "product1-dev"
    replace(replace(config_file, "/", "-"), ".yaml", "") => yamldecode(file("${path.module}/environments/${config_file}"))
  }
}