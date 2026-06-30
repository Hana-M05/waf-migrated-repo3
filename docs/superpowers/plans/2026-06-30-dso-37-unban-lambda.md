# DSO-37: Unban Users When Timeout Expires — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a scheduled Lambda that runs every 5 minutes, finds IPs whose penalty-box ban has expired, removes ALL instances of those IPs from the WAFv2 IP set, and deletes ALL matching DynamoDB records.

**Architecture:** Separate Lambda from the Firehose detector (different trigger types). EventBridge Scheduler fires every 5 minutes. The Lambda reads the WAFv2 IP set, checks each IP against DynamoDB, removes expired IPs, and explicitly deduplicates both the IP set addresses and the DynamoDB scan to satisfy AC3.

**Tech Stack:** Python 3.12, boto3 (`wafv2`, `dynamodb`), `aws_scheduler_schedule`, `aws_lambda_function`, `aws_iam_role`, `archive_file`.

**Acceptance Criteria:**
- AC1: Lambda checks DynamoDB every 5 minutes ✓
- AC2: Expired IPs removed from WAFv2 IP set and DynamoDB ✓
- AC3: Explicit dedup — all duplicate CIDRs for the same IP removed from WAFv2; DynamoDB hash key prevents duplicates by design (handled + documented) ✓

---

## File Map

| File | Action | What changes |
|------|--------|--------------|
| `modules/penalty-box/lambda/unban_function.py` | **Create** | Unban Lambda — WAFv2 dedup + DynamoDB cleanup |
| `modules/penalty-box/main.tf` | **Modify** | 8 new resources: zip, log group, IAM role+policy (Lambda), IAM role+policy (Scheduler), Lambda function, Lambda permission, EventBridge schedule |
| `modules/penalty-box/outputs.tf` | **Modify** | Add `unban_lambda_arn` output |

---

## Task 1: Create `unban_function.py`

**Files:**
- Create: `modules/penalty-box/lambda/unban_function.py`

- [ ] **Step 1.1: Write the Lambda file**

```python
# modules/penalty-box/lambda/unban_function.py
"""
penalty-box-unban — EventBridge scheduled Lambda
=================================================
Runs every 5 minutes. For each IP in the WAFv2 penalty-box IP set:
  - Check DynamoDB: if item is gone (TTL deleted it) OR expires_at <= now → expired
  - Remove ALL CIDRs for expired IPs from the WAFv2 IP set (explicit dedup per AC3)
  - Delete the DynamoDB record for each expired IP (belt-and-suspenders with TTL)

AC3 dedup notes:
  - WAFv2 IP set: deduplicated by normalising each CIDR to its base IP, then grouping.
    If the same IP appears as both x.x.x.x/32 and x.x.x.x/32 (exact duplicate),
    all copies are removed when that IP is expired.
  - DynamoDB: ip_address is the hash key, so true duplicates cannot exist.
    We document this explicitly rather than silently assuming it.
"""

import json
import os
import time

import boto3

# ---------------------------------------------------------------------------
# Configuration (override via Lambda environment variables)
# ---------------------------------------------------------------------------
DYNAMODB_TABLE  = os.environ.get("DYNAMODB_TABLE", "penalty-box")
WAF_IP_SET_ID   = os.environ.get("WAF_IP_SET_ID", "")
WAF_IP_SET_NAME = os.environ.get("WAF_IP_SET_NAME", "")
WAF_SCOPE       = os.environ.get("WAF_SCOPE", "REGIONAL")

_dynamodb = None
_wafv2    = None


def _get_dynamodb():
    global _dynamodb
    if _dynamodb is None:
        _dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    return _dynamodb


def _get_wafv2():
    global _wafv2
    if _wafv2 is None:
        _wafv2 = boto3.client("wafv2", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    return _wafv2


def _get_current_ip_set() -> tuple:
    """
    Fetch the current WAFv2 IP set.
    Returns (addresses: list[str], lock_token: str).
    Raises on API failure so the caller can abort cleanly.
    """
    response = _get_wafv2().get_ip_set(
        Name=WAF_IP_SET_NAME,
        Scope=WAF_SCOPE,
        Id=WAF_IP_SET_ID,
    )
    return response["IPSet"]["Addresses"], response["LockToken"]


def _is_ban_active(ip: str, now: int) -> bool:
    """
    Return True if the DynamoDB record exists AND expires_at > now.
    Return False (expired) if:
      - Item does not exist (TTL already deleted it), OR
      - expires_at <= now (ban window closed but TTL hasn't fired yet).

    Note on AC3 / DynamoDB duplicates:
      ip_address is the DynamoDB hash key, so each IP can have at most one
      record. True duplicates are impossible by schema design. We document
      this here so the intent is explicit rather than assumed.
    """
    table = _get_dynamodb().Table(DYNAMODB_TABLE)
    response = table.get_item(
        Key={"ip_address": ip},
        ProjectionExpression="expires_at",
    )
    item = response.get("Item")
    if not item:
        return False  # TTL removed it — expired
    return int(item.get("expires_at", 0)) > now


def _extract_base_ip(cidr: str) -> str:
    """Extract the host address from a CIDR string (e.g. '1.2.3.4/32' → '1.2.3.4')."""
    return cidr.split("/")[0]


def lambda_handler(event: dict, context) -> dict:
    """
    EventBridge scheduled handler — runs every 5 minutes.

    AC1: Triggered every 5 minutes via EventBridge Scheduler.
    AC2: Removes expired IPs from WAFv2 IP set and DynamoDB.
    AC3: Explicitly deduplicates WAFv2 addresses — all CIDRs resolving to the
         same base IP are removed together when that IP is expired.
    """
    if not WAF_IP_SET_ID or not WAF_IP_SET_NAME:
        print(json.dumps({"event": "unban_skipped", "reason": "WAF env vars not configured"}))
        return {"removed": 0}

    now = int(time.time())

    try:
        addresses, lock_token = _get_current_ip_set()
    except Exception as exc:
        print(json.dumps({"event": "get_ip_set_error", "error": str(exc)}))
        return {"removed": 0}

    if not addresses:
        print(json.dumps({"event": "unban_noop", "reason": "ip_set_is_empty"}))
        return {"removed": 0}

    # --- AC3: Explicit dedup ---
    # Group ALL CIDRs by their base IP. If the same IP appears multiple times
    # in the IP set (e.g. due to a bug in the detection Lambda), all copies
    # are evaluated and removed together.
    ip_to_cidrs: dict = {}  # base_ip -> list of CIDRs in the set
    for cidr in addresses:
        base_ip = _extract_base_ip(cidr)
        ip_to_cidrs.setdefault(base_ip, []).append(cidr)

    expired_ips = []
    cidrs_to_remove = []

    for base_ip, cidrs in ip_to_cidrs.items():
        if not _is_ban_active(base_ip, now):
            expired_ips.append(base_ip)
            cidrs_to_remove.extend(cidrs)  # remove ALL CIDRs for this IP (AC3)

    if not cidrs_to_remove:
        print(json.dumps({"event": "unban_noop", "active_count": len(ip_to_cidrs)}))
        return {"removed": 0}

    # Build the filtered address list — deduplicated by converting to a set
    # to handle any exact-duplicate CIDRs before calling UpdateIPSet.
    cidrs_to_remove_set = set(cidrs_to_remove)
    to_keep = [cidr for cidr in addresses if cidr not in cidrs_to_remove_set]

    # Update WAFv2 IP set — remove all expired CIDRs in one call
    try:
        _get_wafv2().update_ip_set(
            Name=WAF_IP_SET_NAME,
            Scope=WAF_SCOPE,
            Id=WAF_IP_SET_ID,
            Addresses=to_keep,
            LockToken=lock_token,
        )
    except Exception as exc:
        print(json.dumps({"event": "update_ip_set_error", "error": str(exc)}))
        return {"removed": 0}

    # Delete DynamoDB records for each expired IP (belt-and-suspenders alongside TTL)
    table = _get_dynamodb().Table(DYNAMODB_TABLE)
    for ip in expired_ips:
        try:
            table.delete_item(Key={"ip_address": ip})
        except Exception as exc:
            print(json.dumps({"event": "dynamodb_delete_error", "ip": ip, "error": str(exc)}))

    print(json.dumps({
        "event":         "unban_complete",
        "removed_ips":   expired_ips,
        "removed_cidrs": sorted(cidrs_to_remove),
        "removed_count": len(expired_ips),
        "remaining":     len(to_keep),
    }))
    return {"removed": len(expired_ips)}
```

- [ ] **Step 1.2: Commit**

```bash
git add modules/penalty-box/lambda/unban_function.py
git commit -m "feat(DSO-37): add unban Lambda function

Scheduled Lambda that runs every 5 min and removes expired IPs from
the WAFv2 penalty-box IP set.

AC1: Triggered via EventBridge Scheduler every 5 minutes.
AC2: GetIPSet -> check DynamoDB expires_at -> UpdateIPSet -> DeleteItem.
AC3: Explicit WAFv2 dedup — all CIDRs for the same base IP are grouped
     and removed together. DynamoDB duplicates are impossible by schema
     (ip_address is the hash key); documented explicitly in code."
```

---

## Task 2: Add Terraform infrastructure to `main.tf`

**Files:**
- Modify: `modules/penalty-box/main.tf` (append after the last existing resource)

- [ ] **Step 2.1: Append unban infrastructure**

Open `modules/penalty-box/main.tf` and append after the closing `}` of `aws_lambda_function.penalty_box`:

```hcl
# ---------------------------------------------------------------------------
# Unban Lambda — runs every 5 minutes, removes expired IPs from WAFv2
# ---------------------------------------------------------------------------
data "archive_file" "penalty_box_unban_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/unban_function.py"
  output_path = "${path.module}/lambda/unban_lambda.zip"
}

resource "aws_cloudwatch_log_group" "penalty_box_unban_lambda" {
  name              = "/aws/lambda/penalty-box-unban-${var.environment}"
  retention_in_days = 30
}

resource "aws_iam_role" "penalty_box_unban_lambda" {
  name = "penalty-box-unban-lambda-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "penalty_box_unban_lambda" {
  name = "penalty-box-unban-lambda-policy-${var.environment}"
  role = aws_iam_role.penalty_box_unban_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/penalty-box-unban-${var.environment}:*"
      },
      {
        # GetItem to check expiry; DeleteItem for belt-and-suspenders cleanup alongside TTL
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.penalty_box.arn
      },
      {
        # Read current IP set + update it to remove expired IPs
        Effect   = "Allow"
        Action   = ["wafv2:GetIPSet", "wafv2:UpdateIPSet"]
        Resource = aws_wafv2_ip_set.penalty_box.arn
      }
    ]
  })
}

resource "aws_lambda_function" "penalty_box_unban" {
  function_name = "penalty-box-unban-${var.environment}"
  description   = "Removes expired IPs from the WAFv2 penalty-box IP set every 5 minutes"
  role          = aws_iam_role.penalty_box_unban_lambda.arn

  filename         = data.archive_file.penalty_box_unban_lambda.output_path
  source_code_hash = data.archive_file.penalty_box_unban_lambda.output_base64sha256
  handler          = "unban_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      DYNAMODB_TABLE  = aws_dynamodb_table.penalty_box.name
      WAF_IP_SET_ID   = aws_wafv2_ip_set.penalty_box.id
      WAF_IP_SET_NAME = aws_wafv2_ip_set.penalty_box.name
      WAF_SCOPE       = var.waf_scope
    }
  }

  depends_on = [aws_cloudwatch_log_group.penalty_box_unban_lambda]
}

resource "aws_lambda_permission" "penalty_box_unban_scheduler" {
  statement_id  = "AllowEventBridgeScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.penalty_box_unban.function_name
  principal     = "scheduler.amazonaws.com"
}

resource "aws_iam_role" "penalty_box_unban_scheduler" {
  name = "penalty-box-unban-scheduler-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "penalty_box_unban_scheduler" {
  name = "penalty-box-unban-scheduler-policy-${var.environment}"
  role = aws_iam_role.penalty_box_unban_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.penalty_box_unban.arn
    }]
  })
}

resource "aws_scheduler_schedule" "penalty_box_unban" {
  name                         = "penalty-box-unban-${var.environment}"
  description                  = "Fires every 5 minutes to remove expired IPs from the WAFv2 penalty-box IP set"
  schedule_expression          = "rate(5 minutes)"
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.penalty_box_unban.arn
    role_arn = aws_iam_role.penalty_box_unban_scheduler.arn
  }
}
```

- [ ] **Step 2.2: Commit**

```bash
git add modules/penalty-box/main.tf
git commit -m "feat(DSO-37): add unban Lambda Terraform infrastructure

Resources added to modules/penalty-box/main.tf:
  - archive_file.penalty_box_unban_lambda     (zips unban_function.py at plan time)
  - aws_cloudwatch_log_group                  (/aws/lambda/penalty-box-unban-<env>, 30d)
  - aws_iam_role + policy (lambda)            (GetItem+DeleteItem on DynamoDB, GetIPSet+UpdateIPSet on WAFv2)
  - aws_lambda_function.penalty_box_unban     (python3.12, 60s timeout)
  - aws_lambda_permission                     (allows scheduler.amazonaws.com to invoke)
  - aws_iam_role + policy (scheduler)         (lambda:InvokeFunction on unban Lambda)
  - aws_scheduler_schedule                    (rate(5 minutes), UTC, flexible_time_window OFF)"
```

---

## Task 3: Add `unban_lambda_arn` output

**Files:**
- Modify: `modules/penalty-box/outputs.tf`

- [ ] **Step 3.1: Append output**

```hcl
output "unban_lambda_arn" {
  description = "ARN of the scheduled unban Lambda (removes expired IPs from WAFv2 every 5 minutes)"
  value       = aws_lambda_function.penalty_box_unban.arn
}
```

- [ ] **Step 3.2: Commit**

```bash
git add modules/penalty-box/outputs.tf
git commit -m "feat(DSO-37): export unban_lambda_arn from penalty-box module"
```

---

## Task 4: Update `WAF_Provisioner` IAM policy in account 059090138953

The Bitbucket pipeline assumes `WAF_Provisioner`. Its `PenaltyBoxProvisioning` managed policy needs new permissions before `terraform apply` can create the new resources.

- [ ] **Step 4.1: Refresh SSO token**

```bash
aws sso login --profile em-dev
```

- [ ] **Step 4.2: Run the policy update script**

Save as `C:\tmp\update_provisioner_dso37.py` and run:

```python
import boto3, json

ACCOUNT_ID  = "059090138953"
POLICY_NAME = "PenaltyBoxProvisioning"
REGION      = "us-east-1"

session = boto3.Session(profile_name="em-dev")
iam     = session.client("iam")

policies   = iam.list_policies(Scope="Local")["Policies"]
policy     = next(p for p in policies if p["PolicyName"] == POLICY_NAME)
policy_arn = policy["Arn"]

current_vid = iam.get_policy(PolicyArn=policy_arn)["Policy"]["DefaultVersionId"]
doc = iam.get_policy_version(PolicyArn=policy_arn, VersionId=current_vid)["PolicyVersion"]["Document"]

new_statements = [
    {
        "Sid": "UnbanLambdaFunction",
        "Effect": "Allow",
        "Action": [
            "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:UpdateFunctionCode",
            "lambda:UpdateFunctionConfiguration", "lambda:GetFunction",
            "lambda:GetFunctionConfiguration", "lambda:AddPermission",
            "lambda:RemovePermission", "lambda:GetPolicy", "lambda:TagResource",
            "lambda:ListVersionsByFunction", "lambda:PublishVersion"
        ],
        "Resource": f"arn:aws:lambda:{REGION}:{ACCOUNT_ID}:function:penalty-box-unban-*"
    },
    {
        "Sid": "UnbanLambdaIAMRoles",
        "Effect": "Allow",
        "Action": [
            "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PassRole",
            "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy",
            "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:TagRole",
            "iam:ListAttachedRolePolicies", "iam:ListRolePolicies"
        ],
        "Resource": [
            f"arn:aws:iam::{ACCOUNT_ID}:role/penalty-box-unban-lambda-*",
            f"arn:aws:iam::{ACCOUNT_ID}:role/penalty-box-unban-scheduler-*"
        ]
    },
    {
        "Sid": "UnbanLambdaCloudWatchLogs",
        "Effect": "Allow",
        "Action": [
            "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
            "logs:DescribeLogGroups", "logs:ListTagsLogGroup",
            "logs:ListTagsForResource", "logs:TagResource"
        ],
        "Resource": f"arn:aws:logs:{REGION}:{ACCOUNT_ID}:log-group:/aws/lambda/penalty-box-unban-*:*"
    },
    {
        "Sid": "UnbanEventBridgeScheduler",
        "Effect": "Allow",
        "Action": [
            "scheduler:CreateSchedule", "scheduler:DeleteSchedule",
            "scheduler:GetSchedule", "scheduler:UpdateSchedule",
            "scheduler:TagResource", "scheduler:ListTagsForResource"
        ],
        "Resource": f"arn:aws:scheduler:{REGION}:{ACCOUNT_ID}:schedule/default/penalty-box-unban-*"
    }
]

existing_sids = {s.get("Sid", "") for s in doc["Statement"]}
for stmt in new_statements:
    if stmt["Sid"] not in existing_sids:
        doc["Statement"].append(stmt)
        print(f"Added: {stmt['Sid']}")
    else:
        print(f"Already present: {stmt['Sid']}")

versions     = iam.list_policy_versions(PolicyArn=policy_arn)["Versions"]
non_defaults = [v for v in versions if not v["IsDefaultVersion"]]
if len(versions) >= 5:
    oldest = sorted(non_defaults, key=lambda v: v["CreateDate"])[0]
    iam.delete_policy_version(PolicyArn=policy_arn, VersionId=oldest["VersionId"])
    print(f"Deleted old version: {oldest['VersionId']}")

new_ver = iam.create_policy_version(
    PolicyArn=policy_arn,
    PolicyDocument=json.dumps(doc),
    SetAsDefault=True
)["PolicyVersion"]
print(f"Policy updated. New version: {new_ver['VersionId']}")
```

Expected output:
```
Added: UnbanLambdaFunction
Added: UnbanLambdaIAMRoles
Added: UnbanLambdaCloudWatchLogs
Added: UnbanEventBridgeScheduler
Policy updated. New version: v<N>
```

- [ ] **Step 4.3: Commit the plan doc**

```bash
git add docs/superpowers/plans/2026-06-30-dso-37-unban-lambda.md
git commit -m "docs(DSO-37): add implementation plan"
```

---

## Task 5: Push branch and open PR

- [ ] **Step 5.1: Push**

```bash
git push origin feature/DSO-37-unban
```

- [ ] **Step 5.2: Open PR via API**

Save as `C:\tmp\open_pr_dso37.py` and run with `BB_TOKEN` set:

```python
import urllib.request, json, base64

BB_USER  = 'mohamed.elbeltagy@si-eam.com'
BB_TOKEN = 'ATATT3xFfGF00uzFpqKBFpBIoWYbrkrfuiA-UeVxPwjrM81-aHhtqhKKkObEixGLKVcCsfPwVyvtHTuwQWncY1PqJzfwKR4Xwdl_0YZzOm0fd5wqb-TrEfJNyK2HhFFG2kSOZCb31Ym0SiqHkWooTmhOMuLY8asA2EwgEI8N-DCHEWEt8pJ8xSY=33BB5C5C'
BB_AUTH  = base64.b64encode(f'{BB_USER}:{BB_TOKEN}'.encode()).decode()

payload = {
    "title": "feat(DSO-37): unban Lambda - remove expired IPs from WAFv2 every 5 minutes",
    "description": (
        "## What\n"
        "Adds `penalty-box-unban` Lambda that runs every 5 minutes and removes IPs "
        "from the WAFv2 penalty-box IP set once their DynamoDB ban has expired.\n\n"
        "## Acceptance Criteria\n"
        "- AC1: Lambda triggered every 5 minutes via EventBridge Scheduler\n"
        "- AC2: Expired IPs removed from WAFv2 IP set + DynamoDB record deleted\n"
        "- AC3: Explicit dedup — all CIDRs for the same IP removed together from WAFv2; "
        "DynamoDB duplicates impossible by schema (ip_address is hash key, documented in code)\n\n"
        "## Changes\n"
        "- `modules/penalty-box/lambda/unban_function.py` — new Lambda\n"
        "- `modules/penalty-box/main.tf` — unban Lambda, EventBridge schedule (rate 5 min), "
        "IAM roles for Lambda + Scheduler, CloudWatch log group, Lambda permission\n"
        "- `modules/penalty-box/outputs.tf` — `unban_lambda_arn` output\n\n"
        "## Pre-requisite\n"
        "`PenaltyBoxProvisioning` policy on `WAF_Provisioner` (059090138953) updated "
        "with new statements before pipeline runs (see plan Task 4)."
    ),
    "source":      {"branch": {"name": "feature/DSO-37-unban"}},
    "destination": {"branch": {"name": "main"}},
    "close_source_branch": True,
}

url  = 'https://api.bitbucket.org/2.0/repositories/DudeSolutions/aws-waf-tf-code/pullrequests'
data = json.dumps(payload).encode()
req  = urllib.request.Request(url, data=data, headers={
    'Content-Type':  'application/json',
    'Authorization': f'Basic {BB_AUTH}',
})
with urllib.request.urlopen(req) as resp:
    result = json.loads(resp.read())
print(f"PR #{result['id']} created: {result['links']['html']['href']}")
```

---

## AC3 Coverage Summary

| Scenario | Handled by |
|----------|-----------|
| Same IP appears twice as `/32` CIDR in WAFv2 IP set | `ip_to_cidrs` groups all CIDRs by base IP; both removed when expired |
| Same IP appears in DynamoDB twice | Impossible — `ip_address` is the hash key; documented in `_is_ban_active()` |
| IP in WAFv2 but not in DynamoDB (TTL already cleaned it) | `_is_ban_active()` returns False → removed from WAFv2 |
| IP in DynamoDB but not in WAFv2 (never added, or already removed) | Not in `ip_to_cidrs` → `DeleteItem` not called; no error |
