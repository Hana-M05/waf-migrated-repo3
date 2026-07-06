# modules/penalty-box/lambda/unban_function.py
"""
penalty-box-unban — EventBridge scheduled Lambda
=================================================
Runs every 5 minutes. For each IP in the WAFv2 penalty-box IP set:
  - Batch-check DynamoDB: one BatchGetItem call covers all IPs in the set
  - If an item is gone (TTL deleted it) OR expires_at <= now → IP is expired
  - Remove ALL CIDRs for expired IPs from the WAFv2 IP set (explicit dedup per AC3)
  - Delete the DynamoDB record for each expired IP (belt-and-suspenders with TTL)

AC3 dedup notes:
  - WAFv2 IP set: deduplicated by normalising each CIDR to its base IP, then grouping.
    If the same IP appears as x.x.x.x/32 multiple times (e.g. due to a detection bug),
    all copies are removed together when that IP is expired.
  - DynamoDB: ip_address is the hash key, so true duplicates cannot exist.
    We document this explicitly rather than silently assuming it.

Race condition protection:
  - WAFv2 UpdateIPSet uses optimistic locking via a LockToken returned by GetIPSet.
    If another process updates the IP set between our GetIPSet and UpdateIPSet calls,
    the API returns WAFOptimisticLockException and we log + abort cleanly.
    The next scheduled run (5 min later) will retry with a fresh token.
"""

import json
import os
import time

import boto3
from boto3.dynamodb.conditions import Key

# ---------------------------------------------------------------------------
# Configuration (override via Lambda environment variables)
# ---------------------------------------------------------------------------
DYNAMODB_TABLE  = os.environ.get("DYNAMODB_TABLE", "penalty-box")
WAF_IP_SET_ID   = os.environ.get("WAF_IP_SET_ID", "")
WAF_IP_SET_NAME = os.environ.get("WAF_IP_SET_NAME", "")
WAF_SCOPE       = os.environ.get("WAF_SCOPE", "REGIONAL")

# DynamoDB BatchGetItem limit — hard AWS limit is 100 items per call.
_DYNAMODB_BATCH_SIZE = 100

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

    The LockToken implements WAFv2 optimistic locking — it must be passed back
    to UpdateIPSet unchanged. If another writer modified the set between our
    GetIPSet and UpdateIPSet calls, the API rejects the update with
    WAFOptimisticLockException, preventing a lost-update race condition.

    Raises on API failure so the caller can abort cleanly.
    """
    response = _get_wafv2().get_ip_set(
        Name=WAF_IP_SET_NAME,
        Scope=WAF_SCOPE,
        Id=WAF_IP_SET_ID,
    )
    return response["IPSet"]["Addresses"], response["LockToken"]


def _batch_get_active_ips(ips: list, now: int) -> set:
    """
    Return the set of IPs whose ban is still active (expires_at > now).

    Uses DynamoDB BatchGetItem to check all IPs in a single round trip
    (or in batches of 100 if the IP set is large), rather than one GetItem
    per IP. This reduces cost and latency linearly with the number of IPs.

    An IP is considered expired if:
      - Its DynamoDB record is absent (TTL already deleted it), OR
      - Its expires_at value is <= now (ban window closed, TTL hasn't fired yet).

    Note on AC3 / DynamoDB duplicates:
      ip_address is the DynamoDB hash key, so each IP can have at most one
      record. True duplicates are impossible by schema design.
    """
    if not ips:
        return set()

    dynamodb = _get_dynamodb()
    active   = set()

    # Process in batches of 100 (AWS BatchGetItem hard limit)
    for batch_start in range(0, len(ips), _DYNAMODB_BATCH_SIZE):
        batch = ips[batch_start: batch_start + _DYNAMODB_BATCH_SIZE]
        keys  = [{"ip_address": ip} for ip in batch]

        try:
            response = dynamodb.meta.client.batch_get_item(
                RequestItems={
                    DYNAMODB_TABLE: {
                        "Keys":                 keys,
                        "ProjectionExpression": "ip_address, expires_at",
                    }
                }
            )
        except Exception as exc:
            # If the batch call fails, conservatively mark all IPs in this
            # batch as active — better to leave an IP blocked than to
            # accidentally unblock it due to a transient error.
            print(json.dumps({"event": "batch_get_error", "error": str(exc),
                               "batch_size": len(batch)}))
            active.update(batch)
            continue

        # Unprocessed keys: retry once (simple approach — production code
        # should use exponential backoff, but the IP set is expected to be
        # small so this is unlikely to matter in practice).
        unprocessed = response.get("UnprocessedKeys", {})
        if unprocessed:
            print(json.dumps({"event": "batch_get_unprocessed",
                               "count": len(unprocessed.get(DYNAMODB_TABLE, {}).get("Keys", []))}))
            # Conservatively treat unprocessed items as active
            for key in unprocessed.get(DYNAMODB_TABLE, {}).get("Keys", []):
                active.add(key["ip_address"])

        for item in response.get("Responses", {}).get(DYNAMODB_TABLE, []):
            ip         = item["ip_address"]
            expires_at = int(item.get("expires_at", 0))
            if expires_at > now:
                active.add(ip)
            # else: item exists but ban has expired — not added to active set

    return active


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

    # GetIPSet also returns the LockToken needed for optimistic-locking on UpdateIPSet.
    # See _get_current_ip_set() docstring for race condition details.
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

    unique_ips = list(ip_to_cidrs.keys())

    # Single batched DynamoDB call to check all IPs at once
    active_ips = _batch_get_active_ips(unique_ips, now)

    expired_ips    = [ip for ip in unique_ips if ip not in active_ips]
    cidrs_to_remove = []
    for ip in expired_ips:
        cidrs_to_remove.extend(ip_to_cidrs[ip])  # remove ALL CIDRs for this IP (AC3)

    if not cidrs_to_remove:
        print(json.dumps({"event": "unban_noop", "active_count": len(active_ips)}))
        return {"removed": 0}

    # Build the filtered address list — deduplicated via set to handle any
    # exact-duplicate CIDRs before calling UpdateIPSet.
    cidrs_to_remove_set = set(cidrs_to_remove)
    to_keep = [cidr for cidr in addresses if cidr not in cidrs_to_remove_set]

    # Update WAFv2 IP set — the LockToken from GetIPSet prevents race conditions.
    # If another process modified the set since our GetIPSet call, AWS will return
    # WAFOptimisticLockException and we abort; the next 5-min run retries cleanly.
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
