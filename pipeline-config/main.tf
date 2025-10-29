locals {
  bitbucket_fingerprint    = "22D2AFA3B2AF7292F120ADBFAD56E654A73FB021"
  bitbucket_repo_uuid      = "{1c89321f-9c54-4e6b-9793-ab339ab209f9}"
  bitbucket_workspace_uuid = "08320bb4-4352-4eb9-ba1b-50a9a3de64cf"
  bitbucket_workspace_name = "DudeSolutions"
  state_bucket             = "s3-ue1-sharedservices-tfstate"
  state_key                = "aws-waf-tf-code.tfstate"
}
# OIDC Identity Provider
resource "aws_iam_openid_connect_provider" "bitbucket" {
  url = "https://api.bitbucket.org/2.0/workspaces/${local.bitbucket_workspace_name}/pipelines-config/identity/oidc"

  client_id_list = [
    "ari:cloud:bitbucket::workspace/${local.bitbucket_workspace_uuid}"
  ]

  thumbprint_list = [
    local.bitbucket_fingerprint
  ]

  tags = {
    Name        = "Bitbucket WAF OIDC Provider"
    Environment = "production"
  }
}

# IAM Role for Bitbucket Pipelines
resource "aws_iam_role" "bitbucket_terraform" {
  name = "Bitbucket_WAF_Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.bitbucket.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${aws_iam_openid_connect_provider.bitbucket.url}:aud" = "ari:cloud:bitbucket::workspace/${local.bitbucket_workspace_uuid}"
          }
          StringLike = {
            "${aws_iam_openid_connect_provider.bitbucket.url}:sub" = "${local.bitbucket_repo_uuid}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "Bitbucket Terraform Role"
    Environment = "production"
  }
}

# IAM Policy for cross-account role assumption
resource "aws_iam_policy" "bitbucket_terraform" {
  name        = "Bitbucket_WAF_Terraform_Policy"
  description = "Policy for Bitbucket Pipelines to assume WAF_Provisioner roles in target accounts"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeWAFProvisionerRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::*:role/WAF_Provisioner"
      },
      {
        Sid      = "GetCallerIdentity"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:PutObjectAcl"
        ]
        Resource = "arn:aws:s3:::${local.state_bucket}/${local.state_key}"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketVersioning"
        ]
        Resource = "arn:aws:s3:::${local.state_bucket}"
      }
    ]
  })

  tags = {
    Name        = "Bitbucket_WAF_Terraform_Policy"
    Environment = "production"
  }
}

resource "aws_iam_role_policy_attachment" "bitbucket_terraform" {
  role       = aws_iam_role.bitbucket_terraform.name
  policy_arn = aws_iam_policy.bitbucket_terraform.arn
}