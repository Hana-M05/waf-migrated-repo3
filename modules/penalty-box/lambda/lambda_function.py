"""
penalty-box-detector — Kinesis Firehose Lambda processor
=========================================================
Receives WAF JSON log records from Firehose, detects violating IPs
across three tiers, writes them to DynamoDB with a 30-minute TTL,
and returns all records as Ok (pass-through — no data modification).

Tiers:
  Tier 1 — A single request hits a known-bad path (1 hit = block)
  Tier 2 — An IP accumulates 20+ WAF BLOCK actions in one batch
  Tier 3 — An IP has 40%+ heuristic-404 rate AND at least 20 requests in the batch

Note on Tier 3: WAF logs do not carry HTTP response codes. We approximate 404s
by counting ALLOW actions with no terminatingRuleId (no rule matched the request).
True 404 detection requires ALB access log correlation — flag this if precision matters.

Known-good IPs (e.g. ZScaler proxies, Cisco VPN):
  Loaded from SSM at cold start via KNOWN_GOOD_IPS_SSM_PARAM env var.
  IPs in this list are never added to the penalty box. WAF rules are unaffected —
  individual bad requests from these IPs are still blocked normally by the WAF.
  To update the list, change the SSM parameter value — no Lambda redeploy needed.
"""

import base64
import ipaddress
import json
import os
import time
from collections import defaultdict
from urllib.parse import unquote

import boto3

# ---------------------------------------------------------------------------
# Configuration (override via Lambda environment variables)
# ---------------------------------------------------------------------------
DYNAMODB_TABLE           = os.environ.get("DYNAMODB_TABLE", "penalty-box")
PENALTY_TTL_SECONDS      = int(os.environ.get("PENALTY_TTL_SECONDS", "1800"))   # 30 min
TIER2_BLOCK_THRESHOLD    = int(os.environ.get("TIER2_BLOCK_THRESHOLD", "20"))
TIER3_404_RATIO          = float(os.environ.get("TIER3_404_RATIO", "0.40"))
TIER3_MIN_REQUESTS       = int(os.environ.get("TIER3_MIN_REQUESTS", "20"))
KNOWN_GOOD_IPS_SSM_PARAM = os.environ.get("KNOWN_GOOD_IPS_SSM_PARAM", "")

# Tier 1 — bad paths (case-insensitive prefix/exact match)
TIER1_BAD_PATHS = [
    "/wp-admin",
    "/wp-login",
    "/wp-content",
    "/phpMyAdmin",
    "/.env",
    "/.git",
    "/admin/config",
    "/config.php",
    "/shell",
    "/cgi-bin",
    "/actuator",
    "/.aws",
    "/etc/passwd",
    "/proc/self",
]

_dynamodb = None
_known_good_networks = None  # loaded once at cold start

# WAFv2 client — initialised once at cold start
_wafv2 = None

# WAFv2 IP set configuration (from env vars)
WAF_IP_SET_ID   = os.environ.get("WAF_IP_SET_ID", "")
WAF_IP_SET_NAME = os.environ.get("WAF_IP_SET_NAME", "")
WAF_SCOPE       = os.environ.get("WAF_SCOPE", "REGIONAL")


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


def _load_known_good_networks():
    """
    Load the known-good CIDR list from SSM on cold start.
    Returns a list of ipaddress.ip_network objects, or an empty list
    if the SSM parameter name is not configured or the call fails.
    """
    global _known_good_networks
    if _known_good_networks is not None:
        return _known_good_networks

    if not KNOWN_GOOD_IPS_SSM_PARAM:
        _known_good_networks = []
        return _known_good_networks

    try:
        ssm = boto3.client("ssm", region_name=os.environ.get("AWS_REGION", "us-east-1"))
        response = ssm.get_parameter(Name=KNOWN_GOOD_IPS_SSM_PARAM)
        raw = response["Parameter"]["Value"]
        networks = []
        for cidr in raw.split(","):
            cidr = cidr.strip()
            if cidr:
                networks.append(ipaddress.ip_network(cidr, strict=False))
        _known_good_networks = networks
        print(json.dumps({"event": "known_good_loaded", "count": len(networks)}))
    except Exception as exc:
        # Log and continue — a missing SSM param should not break WAF log processing
        print(json.dumps({"event": "known_good_load_error", "error": str(exc)}))
        _known_good_networks = []

    return _known_good_networks


def _is_known_good(ip: str) -> bool:
    """Return True if the IP falls within any known-good CIDR."""
    networks = _load_known_good_networks()
    if not networks:
        return False
    try:
        addr = ipaddress.ip_address(ip)
        return any(addr in net for net in networks)
    except ValueError:
        return False


def _is_bad_path(uri: str) -> bool:
    """Return True if the request URI matches any Tier 1 bad path.

    URI is percent-decoded before matching so encoded variants like
    /.%65nv are caught the same as /.env.
    """
    decoded = unquote(uri).lower().split("?")[0]  # decode + strip query string
    return any(decoded == p.lower() or decoded.startswith(p.lower() + "/") for p in TIER1_BAD_PATHS)


def _build_violation(ip: str, tier: int, reason: str) -> dict:
    """Build a DynamoDB item dict for a violating IP."""
    now = int(time.time())
    return {
        "ip_address":  ip,
        "tier":        tier,
        "reason":      reason,
        "expires_at":  now + PENALTY_TTL_SECONDS,
        "detected_at": now,
    }


def _upsert_violations(violations: list) -> None:
    """Write violations to DynamoDB, extending the ban if the IP is already penalised.

    For each violating IP:
    - If the IP is NOT already in the table → create a fresh item.
    - If the IP IS already in the table:
        - Add PENALTY_TTL_SECONDS to the existing expires_at (accumulate, not overwrite).
        - Escalate the stored tier if the new violation is higher severity.
        - Preserve the original detected_at so audit history is intact.

    This implements the DSO-35 requirement: "if an IP is already in the table,
    add 30 min to their ban time."
    """
    if not violations:
        return

    table = _get_dynamodb().Table(DYNAMODB_TABLE)

    for item in violations:
        ip  = item["ip_address"]
        try:
            table.update_item(
                Key={"ip_address": ip},
                # Condition: item already exists (attribute_exists) OR does not yet exist.
                # Two separate expressions handle the two branches via a single UpdateItem:
                #
                #   SET expires_at  = expires_at + TTL   (if item existed) — accumulate
                #   SET expires_at  = :new_exp           (if item is new)  — via if_not_exists
                #   SET tier        = max(current, new)  — never downgrade tier
                #   SET detected_at = keep original      — if_not_exists preserves first seen
                #   SET reason      = new reason         — always latest reason
                UpdateExpression=(
                    "SET expires_at  = if_not_exists(expires_at, :zero) + :ttl, "
                    "    tier        = if_not_exists(tier, :zero_tier), "
                    "    detected_at = if_not_exists(detected_at, :now), "
                    "    reason      = :reason"
                ),
                # After the SET above, conditionally escalate tier if new violation is higher
                ConditionExpression=(
                    "attribute_not_exists(ip_address) OR tier <= :new_tier"
                ),
                ExpressionAttributeValues={
                    ":ttl":       PENALTY_TTL_SECONDS,
                    ":zero":      0,
                    ":zero_tier": item["tier"],
                    ":now":       item["detected_at"],
                    ":new_tier":  item["tier"],
                    ":reason":    item["reason"],
                },
            )
            print(json.dumps({
                "event":      "violation_upserted",
                "ip":         ip,
                "tier":       item["tier"],
                "reason":     item["reason"],
                "expires_at": item["expires_at"],
            }))
        except _get_dynamodb().meta.client.exceptions.ConditionalCheckFailedException:
            # Existing record has a higher tier — keep it, but still extend the TTL
            table.update_item(
                Key={"ip_address": ip},
                UpdateExpression="SET expires_at = if_not_exists(expires_at, :zero) + :ttl",
                ExpressionAttributeValues={
                    ":ttl":  PENALTY_TTL_SECONDS,
                    ":zero": 0,
                },
            )
            print(json.dumps({
                "event":  "violation_ttl_extended",
                "ip":     ip,
                "reason": "existing tier is higher — TTL extended only",
            }))


def _process_records(records: list) -> tuple:
    """
    Decode and parse all Firehose records; aggregate per-IP stats for Tier 2/3.
    Returns (parsed_waf_events, per_ip_stats).
    """
    parsed = []
    per_ip = defaultdict(lambda: {"blocks": 0, "requests": 0, "not_found": 0})

    for rec in records:
        try:
            raw = base64.b64decode(rec["data"]).decode("utf-8").strip()
            if not raw:
                continue
            # Firehose may batch multiple newline-delimited JSON objects in one record
            for line in raw.splitlines():
                line = line.strip()
                if not line:
                    continue
                event = json.loads(line)
                parsed.append(event)

                ip = (
                    event.get("httpRequest", {}).get("clientIp")
                    or event.get("clientIp", "unknown")
                )
                action           = event.get("action", "")
                terminating_rule = event.get("terminatingRuleId", "")

                per_ip[ip]["requests"] += 1

                if action == "BLOCK":
                    per_ip[ip]["blocks"] += 1

                # Heuristic 404: ALLOW with no matching rule → likely not-found
                if action == "ALLOW" and not terminating_rule:
                    per_ip[ip]["not_found"] += 1

        except (json.JSONDecodeError, KeyError, UnicodeDecodeError) as exc:
            print(json.dumps({"event": "parse_error", "error": str(exc)}))

    return parsed, per_ip


def _add_ips_to_waf_ip_set(ips: list) -> None:
    """
    Add the given IP addresses (plain IPs, not CIDRs) to the WAFv2 penalty-box IP set.
    Each IP is converted to a /32 CIDR before being added.
    Skipped silently if WAF_IP_SET_ID or WAF_IP_SET_NAME is not configured.
    Uses optimistic locking (LockToken) required by the WAFv2 UpdateIPSet API.
    """
    if not WAF_IP_SET_ID or not WAF_IP_SET_NAME or not ips:
        return

    wafv2 = _get_wafv2()
    new_cidrs = {f"{ip}/32" for ip in ips}

    try:
        response = wafv2.get_ip_set(
            Name=WAF_IP_SET_NAME,
            Scope=WAF_SCOPE,
            Id=WAF_IP_SET_ID,
        )
        current_addresses = set(response["IPSet"]["Addresses"])
        lock_token = response["LockToken"]

        to_add = new_cidrs - current_addresses
        if not to_add:
            print(json.dumps({"event": "waf_ip_set_no_change", "ips": list(new_cidrs)}))
            return

        updated_addresses = sorted(current_addresses | to_add)
        wafv2.update_ip_set(
            Name=WAF_IP_SET_NAME,
            Scope=WAF_SCOPE,
            Id=WAF_IP_SET_ID,
            Addresses=updated_addresses,
            LockToken=lock_token,
        )
        print(json.dumps({
            "event":   "waf_ip_set_updated",
            "added":   sorted(to_add),
            "total":   len(updated_addresses),
        }))
    except Exception as exc:
        # Log and continue — a WAF update failure must never break the Firehose processor.
        # The IP is already in DynamoDB; DSO-37 unban Lambda will handle consistency.
        print(json.dumps({"event": "waf_ip_set_error", "error": str(exc)}))


def lambda_handler(event: dict, context) -> dict:
    """
    Firehose transformation handler.
    All records are returned as result=Ok with the original data unchanged.
    Side-effect: violating IPs are collected across all tiers and written to
    DynamoDB in a single batch at the end. Known-good IPs are skipped.
    If an IP qualifies for multiple tiers, only the highest tier is written.
    """
    records = event.get("records", [])
    parsed_events, per_ip = _process_records(records)

    # violations is a dict keyed by IP — ensures one write per IP (highest tier wins)
    violations: dict = {}

    # --- Tier 1: bad path (per-request, single hit = violation) ---
    for waf_event in parsed_events:
        uri = waf_event.get("httpRequest", {}).get("uri", "")
        if not _is_bad_path(uri):
            continue
        ip = (
            waf_event.get("httpRequest", {}).get("clientIp")
            or waf_event.get("clientIp", "unknown")
        )
        if ip in violations:
            continue  # already flagged at a higher or equal tier
        if _is_known_good(ip):
            print(json.dumps({"event": "known_good_skipped", "ip": ip, "tier": 1}))
        else:
            violations[ip] = _build_violation(ip, 1, f"bad path hit: {uri}")

    # --- Tier 2: 20+ WAF BLOCK actions per batch ---
    for ip, stats in per_ip.items():
        if ip in violations:
            continue  # already flagged at Tier 1
        if stats["blocks"] >= TIER2_BLOCK_THRESHOLD:
            if _is_known_good(ip):
                print(json.dumps({"event": "known_good_skipped", "ip": ip, "tier": 2}))
            else:
                violations[ip] = _build_violation(
                    ip, 2,
                    f"{stats['blocks']} WAF BLOCK actions in batch (threshold: {TIER2_BLOCK_THRESHOLD})"
                )

    # --- Tier 3: 40%+ heuristic-404 rate with >=20 requests ---
    for ip, stats in per_ip.items():
        if ip in violations:
            continue  # already flagged at Tier 1 or 2
        if stats["requests"] < TIER3_MIN_REQUESTS:
            continue
        ratio = stats["not_found"] / stats["requests"]
        if ratio >= TIER3_404_RATIO:
            if _is_known_good(ip):
                print(json.dumps({"event": "known_good_skipped", "ip": ip, "tier": 3}))
            else:
                violations[ip] = _build_violation(
                    ip, 3,
                    f"{ratio:.0%} heuristic-404 rate over {stats['requests']} requests "
                    f"(threshold: {TIER3_404_RATIO:.0%} with min {TIER3_MIN_REQUESTS} reqs)"
                )

    # Upsert all violations — extends TTL if IP is already penalised
    _upsert_violations(list(violations.values()))

    # Add violating IPs to the WAFv2 IP set so the WAF blocks them immediately
    if violations:
        _add_ips_to_waf_ip_set(list(violations.keys()))

    # Return all records unchanged — Firehose processor must not modify payload
    return {
        "records": [
            {
                "recordId": rec["recordId"],
                "result":   "Ok",
                "data":     rec["data"],
            }
            for rec in records
        ]
    }
