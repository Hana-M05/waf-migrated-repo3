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
    If the same IP appears as x.x.x.x/32 multiple times (e.g. due to a detection bug),
    all copies are removed together when that IP is expired.
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
    """Extract the host address from a CIDR string (e.g. '1.2.3.4/32' -> '1.2.3.4')."""
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

    # Build the filtered address list — deduplicated via set to handle any
    # exact-duplicate CIDRs before calling UpdateIPSet.
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
