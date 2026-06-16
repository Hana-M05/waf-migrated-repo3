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
"""

import base64
import json
import os
import time
from collections import defaultdict

import boto3

# ---------------------------------------------------------------------------
# Configuration (override via Lambda environment variables)
# ---------------------------------------------------------------------------
DYNAMODB_TABLE        = os.environ.get("DYNAMODB_TABLE", "penalty-box")
PENALTY_TTL_SECONDS   = int(os.environ.get("PENALTY_TTL_SECONDS", "1800"))   # 30 min
TIER2_BLOCK_THRESHOLD = int(os.environ.get("TIER2_BLOCK_THRESHOLD", "20"))
TIER3_404_RATIO       = float(os.environ.get("TIER3_404_RATIO", "0.40"))
TIER3_MIN_REQUESTS    = int(os.environ.get("TIER3_MIN_REQUESTS", "20"))

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


def _get_dynamodb():
    global _dynamodb
    if _dynamodb is None:
        _dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    return _dynamodb


def _is_bad_path(uri: str) -> bool:
    """Return True if the request URI matches any Tier 1 bad path."""
    lower = uri.lower().split("?")[0]  # strip query string
    return any(lower == p.lower() or lower.startswith(p.lower() + "/") for p in TIER1_BAD_PATHS)


def _write_violation(ip: str, tier: int, reason: str) -> None:
    """Write a violating IP to DynamoDB with a TTL of PENALTY_TTL_SECONDS."""
    expires_at = int(time.time()) + PENALTY_TTL_SECONDS
    table = _get_dynamodb().Table(DYNAMODB_TABLE)
    table.put_item(
        Item={
            "ip_address":  ip,
            "tier":        tier,
            "reason":      reason,
            "expires_at":  expires_at,
            "detected_at": int(time.time()),
        }
    )
    print(json.dumps({
        "event":      "violation_detected",
        "ip":         ip,
        "tier":       tier,
        "reason":     reason,
        "expires_at": expires_at,
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
                action          = event.get("action", "")
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
    Side-effect: violating IPs are written to DynamoDB.
    """
    records = event.get("records", [])
    parsed_events, per_ip = _process_records(records)

    # --- Tier 1: bad path (per-request, single hit = violation) ---
    tier1_ips: set = set()
    for waf_event in parsed_events:
        uri = waf_event.get("httpRequest", {}).get("uri", "")
        if _is_bad_path(uri):
            ip = (
                waf_event.get("httpRequest", {}).get("clientIp")
                or waf_event.get("clientIp", "unknown")
            )
            if ip not in tier1_ips:
                tier1_ips.add(ip)
                _write_violation(ip, 1, f"bad path hit: {uri}")

    # --- Tier 2: 20+ WAF BLOCK actions per batch ---
    for ip, stats in per_ip.items():
        if ip in tier1_ips:
            continue  # already written
        if stats["blocks"] >= TIER2_BLOCK_THRESHOLD:
            _write_violation(
                ip, 2,
                f"{stats['blocks']} WAF BLOCK actions in batch (threshold: {TIER2_BLOCK_THRESHOLD})"
            )

    # --- Tier 3: 40%+ heuristic-404 rate with >=20 requests ---
    for ip, stats in per_ip.items():
        if ip in tier1_ips:
            continue
        if stats["requests"] < TIER3_MIN_REQUESTS:
            continue
        ratio = stats["not_found"] / stats["requests"]
        if ratio >= TIER3_404_RATIO:
            _write_violation(
                ip, 3,
                f"{ratio:.0%} heuristic-404 rate over {stats['requests']} requests "
                f"(threshold: {TIER3_404_RATIO:.0%} with min {TIER3_MIN_REQUESTS} reqs)"
            )

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
