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


def _get_dynamodb():
    global _dynamodb
    if _dynamodb is None:
        _dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    return _dynamodb


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


def _batch_write_violations(violations: list) -> None:
    """Write all violations to DynamoDB in a single batch.

    boto3's batch_writer automatically handles the 25-item limit per request
    and retries any unprocessed items, so callers can pass any number of items.
    """
    if not violations:
        return
    table = _get_dynamodb().Table(DYNAMODB_TABLE)
    with table.batch_writer() as batch:
        for item in violations:
            batch.put_item(Item=item)
            print(json.dumps({
                "event":      "violation_detected",
                "ip":         item["ip_address"],
                "tier":       item["tier"],
                "reason":     item["reason"],
                "expires_at": item["expires_at"],
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

    # Write all violations to DynamoDB in one batch
    _batch_write_violations(list(violations.values()))

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
