# penalty-box

Kinesis Firehose Lambda processor that auto-detects scanning and attacking IPs from WAF logs, writes them to DynamoDB with a configurable TTL, and returns all records unchanged so the Firehose pipeline continues normally.

A downstream component (follow-on ticket) reads DynamoDB Streams and calls `wafv2 update-ip-set` to enforce the block at the WAF layer.

---

## Architecture

```
WAF logs
   │
   ▼
Kinesis Firehose  ──────────────────────────────────────────► S3 (ob1 alloy bucket, primary)
   │
   │  processing_configuration (Lambda processor)
   ▼
penalty-box Lambda
   │  detects violations across 3 tiers
   ▼
DynamoDB  (penalty-box-<environment>)
   │  expires_at TTL = 30 min
   ▼
[follow-on] DynamoDB Streams → Lambda → wafv2 update-ip-set
   │
   │  s3_backup_configuration (S3BackupMode)
   ▼
S3 (bsw-waf-penalty-box-logs-<environment>, backup — same account as Firehose)
```

**Important:** S3BackupMode is a one-way switch. Once enabled on a Firehose stream it cannot be disabled without recreating the stream.

---

## Detection tiers

| Tier | Trigger | Threshold |
|------|---------|-----------|
| 1 | Single request hits a known-bad path (`/.env`, `/wp-admin`, `/actuator`, etc.) | 1 hit |
| 2 | IP accumulates WAF `BLOCK` actions within a single Firehose batch | 20 blocks (configurable) |
| 3 | IP has a high rate of heuristic-404s within a batch (ALLOW + no terminating rule) | 40% of ≥20 requests (configurable) |

> **Tier 3 note:** WAF logs do not carry HTTP response codes. The 404 signal is approximated by counting `ALLOW` actions with a blank `terminatingRuleId` (no WAF rule matched). True 404 detection requires ALB access log correlation.

---

## Resources created

| Resource | Name pattern |
|----------|-------------|
| `aws_lambda_function` | `penalty-box-<environment>` |
| `aws_dynamodb_table` | `penalty-box-<environment>` |
| `aws_s3_bucket` | `bsw-waf-penalty-box-logs-<environment>` |
| `aws_iam_role` (Lambda exec) | `penalty-box-lambda-<environment>` |
| `aws_cloudwatch_log_group` | `/aws/lambda/penalty-box-<environment>` |

---

## Inputs

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `environment` | `string` | — | Environment name used to namespace all resources |
| `lambda_zip_path` | `string` | — | Local path to `lambda.zip`. Build with the command below. |
| `log_retention_days` | `number` | `90` | Days to retain WAF log backups in S3 |
| `penalty_ttl_seconds` | `number` | `1800` | Seconds until a penalised IP is removed from DynamoDB (30 min) |
| `tier2_block_threshold` | `number` | `20` | WAF BLOCK actions per batch to trigger Tier 2 |
| `tier3_404_ratio` | `number` | `0.40` | Heuristic-404 fraction to trigger Tier 3 |
| `tier3_min_requests` | `number` | `20` | Minimum requests before Tier 3 ratio is evaluated |

## Outputs

| Output | Description |
|--------|-------------|
| `lambda_arn` | ARN of the penalty-box Lambda (used as Firehose processor) |
| `dynamodb_table_name` | DynamoDB table name |
| `dynamodb_table_arn` | DynamoDB table ARN |
| `log_bucket_arn` | ARN of the S3 backup bucket |
| `log_bucket_id` | Name of the S3 backup bucket |

---

## Building the Lambda zip

The zip must exist on disk before `terraform plan` because the provider calls `filebase64sha256` at plan time.

```bash
cd modules/penalty-box/lambda
python3 -c "
import zipfile
with zipfile.ZipFile('lambda.zip', 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.write('lambda_function.py')
"
```

The zip is excluded from version control via `.gitignore`. Rebuild it whenever `lambda_function.py` changes.

---

## Wiring to a product environment

Each product has a `.tf` file at the repo root (e.g. `asset-essentials.tf`, `theworxhub.tf`). Wiring the penalty box to an environment requires **3 touch points** in that file.

### Step 1 — Add the penalty-box module block

Add this block near the top of the product `.tf` file, before the `firehose_role_policy` block. Substitute the product name, provider alias, and environment key.

```hcl
module "penalty_box_<product>_<env>" {
  source = "./modules/penalty-box"

  providers = {
    aws = aws.<product>_<env>_<region>   # match the existing provider alias in this file
  }

  environment     = "<product>-<env>-<region>"                                    # e.g. "asset-essentials-dev-us-east-1"
  lambda_zip_path = "${path.module}/modules/penalty-box/lambda/lambda.zip"
}
```

**Example — Asset Essentials dev:**

```hcl
module "penalty_box_asset_essentials_dev" {
  source = "./modules/penalty-box"

  providers = {
    aws = aws.asset_essentials_dev_us_east_1
  }

  environment     = "asset-essentials-dev-us-east-1"
  lambda_zip_path = "${path.module}/modules/penalty-box/lambda/lambda.zip"
}
```

---

### Step 2 — Extend the existing `firehose_role_policy` block

Add 3 lines to the existing `firehose_role_policy_<product>_<env>` module call:

```hcl
module "firehose_role_policy_<product>_<env>" {
  source = "./modules/firehose-role-policy"
  providers = { aws = aws.<product>_<env>_<region> }

  # existing line — extend concat to include the backup bucket
  s3_bucket_arns          = concat(values(local.alloy_s3_buckets), [module.penalty_box_<product>_<env>.log_bucket_arn])

  # new lines
  lambda_processor_arn    = module.penalty_box_<product>_<env>.lambda_arn
  enable_lambda_processor = true
}
```

**Example — Asset Essentials dev (was):**

```hcl
module "firehose_role_policy_asset_essentials_dev" {
  ...
  s3_bucket_arns = values(local.alloy_s3_buckets)
}
```

**After:**

```hcl
module "firehose_role_policy_asset_essentials_dev" {
  ...
  s3_bucket_arns          = concat(values(local.alloy_s3_buckets), [module.penalty_box_asset_essentials_dev.log_bucket_arn])
  lambda_processor_arn    = module.penalty_box_asset_essentials_dev.lambda_arn
  enable_lambda_processor = true
}
```

---

### Step 3 — Extend the existing `waf_wrapper` block

Add the penalty-box module to `depends_on` and pass the two new variables:

```hcl
module "waf_wrapper_<product>_<env>_<region>" {
  # add penalty_box to depends_on
  depends_on = [module.firehose_role_policy_<product>_<env>, module.penalty_box_<product>_<env>]
  ...

  # add at the end of the block
  lambda_processor_arn = module.penalty_box_<product>_<env>.lambda_arn
  s3_backup_bucket_arn = module.penalty_box_<product>_<env>.log_bucket_arn
}
```

**Example — Asset Essentials dev (was):**

```hcl
module "waf_wrapper_asset_essentials_dev_us_east_1" {
  depends_on = [module.firehose_role_policy_asset_essentials_dev]
  ...
  waf_error_subscribers = local.environments["asset-essentials-dev-us-east-1"].waf_error_subscribers
}
```

**After:**

```hcl
module "waf_wrapper_asset_essentials_dev_us_east_1" {
  depends_on = [module.firehose_role_policy_asset_essentials_dev, module.penalty_box_asset_essentials_dev]
  ...
  waf_error_subscribers = local.environments["asset-essentials-dev-us-east-1"].waf_error_subscribers
  lambda_processor_arn  = module.penalty_box_asset_essentials_dev.lambda_arn
  s3_backup_bucket_arn  = module.penalty_box_asset_essentials_dev.log_bucket_arn
}
```

---

## Prerequisite — WAF_Provisioner role permissions

The `WAF_Provisioner` IAM role in each product account must have permissions to manage the resources this module creates. Add the following to its policy if not already present:

```json
{
  "Effect": "Allow",
  "Action": [
    "lambda:CreateFunction",
    "lambda:UpdateFunctionCode",
    "lambda:UpdateFunctionConfiguration",
    "lambda:DeleteFunction",
    "lambda:GetFunction",
    "lambda:AddPermission",
    "lambda:RemovePermission",
    "dynamodb:CreateTable",
    "dynamodb:UpdateTable",
    "dynamodb:DeleteTable",
    "dynamodb:DescribeTable",
    "dynamodb:UpdateTimeToLive",
    "s3:CreateBucket",
    "s3:DeleteBucket",
    "s3:PutBucketPolicy",
    "s3:PutBucketPublicAccessBlock",
    "s3:PutEncryptionConfiguration",
    "s3:PutLifecycleConfiguration",
    "iam:CreateRole",
    "iam:DeleteRole",
    "iam:PutRolePolicy",
    "iam:DeleteRolePolicy",
    "iam:GetRole",
    "iam:GetRolePolicy",
    "iam:PassRole"
  ],
  "Resource": "*"
}
```

---

## Current rollout status

| Product | Environment | Status |
|---------|-------------|--------|
| energy-manager | dev-us-east-1 | Wired — pending apply to EM-DEV |
| All others | — | Not yet wired |

The module was validated via `terraform apply` in the security account (`533267359674`) before being wired to any product environment. All 15 resources deployed successfully.
