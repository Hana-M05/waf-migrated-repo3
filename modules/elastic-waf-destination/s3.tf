resource "aws_s3_bucket" "waf-bucket" {
  bucket = "bsw-siem-waf"

  tags = {
    Name = "bsw-siem-waf"
  }
}

resource "aws_s3_bucket_public_access_block" "waf-bucket-block" {
  bucket = aws_s3_bucket.waf-bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "waf-bucket-versioning" {
  bucket = aws_s3_bucket.waf-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}


// ...existing code...
resource "aws_s3_bucket_policy" "allow_replication" {
  depends_on = [aws_s3_bucket.waf-bucket]
  bucket     = aws_s3_bucket.waf-bucket.id

  policy = jsonencode({
    Version  = "2012-10-17"
    Statement = concat(
      [
        for role in var.replication_roles : {
          Sid       = "ReplicationObjects-${replace(role,":","_")}"
          Effect    = "Allow"
          Principal = { AWS = role }
          Action = [
            "s3:ReplicateObject",
            "s3:ReplicateDelete",
            "s3:ReplicateTags",
            "s3:PutObject",
            "s3:PutObjectAcl",
            "s3:PutObjectTagging"
          ]
          Resource = "${aws_s3_bucket.waf-bucket.arn}/*"
        }
      ],
      [
        {
          Sid    = "ReplicationLegacyObjects"
          Effect = "Allow"
          Principal = {
            AWS = [
              "arn:aws:iam::721748265548:role/service-role/s3crr_role_for_dsi-organizationwide-cloudtrail",
              "arn:aws:iam::381228211842:role/service-role/s3crr_role_for_aws-controltower-logs-381228211842-us-east-1_1"
            ]
          }
          Action = [
            "s3:ReplicateObject",
            "s3:ReplicateDelete"
          ]
          Resource = "${aws_s3_bucket.waf-bucket.arn}/*"
        },
        {
          Sid    = "ReplicationLegacyBucketVersioning"
          Effect = "Allow"
          Principal = {
            AWS = [
              "arn:aws:iam::721748265548:role/service-role/s3crr_role_for_dsi-organizationwide-cloudtrail",
              "arn:aws:iam::381228211842:role/service-role/s3crr_role_for_aws-controltower-logs-381228211842-us-east-1_1"
            ]
          }
          Action = [
            "s3:GetBucketVersioning",
            "s3:PutBucketVersioning"
          ]
          Resource = aws_s3_bucket.waf-bucket.arn
        }
      ]
    )
  })
}
