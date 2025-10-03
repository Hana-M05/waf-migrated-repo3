# AWS WAF Terraform Code
A centralized Terraform repository for provisioning AWS Web Application Firewalls (WAF) across multiple environments and products. This solution provides a common set of WAF configurations that can be deployed to any AWS account while allowing developers to customize security rules per environment.

## 🛡️ Features
- **Centralized WAF Management**: Single repository to manage WAF configurations across all environments
- **CloudWatch Logging**: All WAF logs are automatically stored in CloudWatch for monitoring and analysis
- **Comprehensive Rule Set**: Includes AWS managed rules and custom blocking capabilities
- **Developer-Friendly**: Self-service configuration through YAML files
- **Multi-Environment Support**: Deploy to multiple AWS accounts simultaneously

## 🔧 Available Security Rules
The WAF includes the following optional protection layers

### AWS Managed Rules
- `AWSManagedRulesCommonRuleSet` - Basic protection against common threats
- `AWSManagedRulesKnownBadInputsRuleSet` - Blocks known malicious requests
- `AWSManagedRulesSQLiRuleSet` - SQL injection protection
- `AWSManagedRulesWindowsRuleSet` - Windows-specific attack protection
- `AWSManagedRulesLinuxRuleSet` - Linux-specific attack protection

### Custom Rules
- IP Blocking Rule - Block specific IP addresses or CIDR ranges
- URL/Path Blocking Rule - Block access to specific endpoints or paths

## 🚀 Getting Started
### For Developers
1. Create your configuration file at environments/<your-product-name>/<your-environment-name>.yaml
2. Configure your WAF settings using the template below
3. Submit a PR for review and deployment
### For DevSecOps/Ops/Security Teams
1. Add AWS provider for the new environment in `providers.tf`
2. Add module block referencing the environment configuration in `main.tf`
3. Add appropriate reviewers for the new environment in `CODEOWNERS`
4. Deploy via Jenkins using terraform apply

## 🔒 Security Actions
### Block vs Count vs Allow
- Block (Recommended for Production): Completely stops the request
- Count (Good for Testing): Logs the request but allows it through - useful for testing rules before blocking or bypassing pieces of a ruleset
- Allow: Explicitly allows the request (rarely used)

### Testing New Rules
1. Set action to "count" initially
2. Monitor CloudWatch logs for false positives
3. Adjust disabled_rules if needed
4. Change action to "block" when confident

## 🤝 Contributing
1. Create your environment configuration file
2. Test thoroughly in a non-production environment first
3. Submit a PR with clear description of changes
4. Ensure all security reviews are completed
5. Deploy via Jenkins after approval

## 📞 Support
### 🚨 Production Outages
If there's a production outage caused by the WAF:

1. SREs: Make immediate changes directly to the WAF in the AWS console to resolve the outage. 
2. After resolution: Developers must update this repository to reflect the emergency changes made by SREs
3. Follow-up: Submit a PR with the updated configuration to ensure infrastructure-as-code consistency

### 💬 General Support
For general questions, new features, or non-urgent issues:

1. Contact the DevSecOps team
2. Include relevant environment details and specific requirements
3. Allow time for proper review and testing cycles