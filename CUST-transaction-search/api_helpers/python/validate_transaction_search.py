#!/usr/bin/env python3
"""Validate CloudWatch Transaction Search using boto3.

Complements the bash checks in post-api-helpers.sh with the things that are
awkward in CLI + JMESPath:

  * trace segment destination + status
  * the Default indexing rule's desired vs. actual percentage
  * presence of the CloudWatch Logs resource policy and that it names
    xray.amazonaws.com
  * whether the aws/spans log group exists yet (it is created lazily by X-Ray
    once the first span arrives, so absence right after apply is only a WARN)

Prints [ OK ] / [WARN] / [FAIL] lines. Always exits 0: validation reports, it
does not break the build.
"""

import argparse
import json
import sys

import boto3
from botocore.exceptions import BotoCoreError, ClientError


def ok(msg: str) -> None:
    print(f"[ OK ] {msg}")


def warn(msg: str) -> None:
    print(f"[WARN] {msg}")


def fail(msg: str) -> None:
    print(f"[FAIL] {msg}")


def check_destination(xray) -> None:
    resp = xray.get_trace_segment_destination()
    dest = resp.get("Destination")
    status = resp.get("Status")
    if dest == "CloudWatchLogs" and status == "ACTIVE":
        ok(f"Trace segment destination: {dest} ({status})")
    elif dest == "CloudWatchLogs":
        warn(f"Trace segment destination: {dest} ({status}); wait for ACTIVE")
    else:
        fail(f"Trace segment destination: {dest} ({status}); expected CloudWatchLogs")


def check_indexing_rule(xray) -> None:
    rules = xray.get_indexing_rules().get("IndexingRules", [])
    default = next((r for r in rules if r.get("Name") == "Default"), None)
    if not default:
        fail("Default indexing rule not found")
        return
    prob = default.get("Rule", {}).get("Probabilistic", {})
    desired = prob.get("DesiredSamplingPercentage")
    actual = prob.get("ActualSamplingPercentage")
    ok(f"Default indexing rule: desired={desired}% actual={actual}%")


def check_resource_policy(logs, policy_name: str) -> None:
    paginator = logs.get_paginator("describe_resource_policies")
    for page in paginator.paginate():
        for pol in page.get("resourcePolicies", []):
            if pol.get("policyName") != policy_name:
                continue
            try:
                doc = json.loads(pol.get("policyDocument", "{}"))
            except json.JSONDecodeError:
                fail(f"Resource policy {policy_name}: document is not valid JSON")
                return
            principals = [
                s.get("Principal", {}).get("Service")
                for s in doc.get("Statement", [])
            ]
            if "xray.amazonaws.com" in principals:
                ok(f"Resource policy {policy_name}: grants xray.amazonaws.com")
            else:
                fail(f"Resource policy {policy_name}: does not grant xray.amazonaws.com")
            return
    fail(f"Resource policy {policy_name}: not found")


def check_spans_log_group(logs) -> None:
    resp = logs.describe_log_groups(logGroupNamePrefix="aws/spans")
    groups = [g for g in resp.get("logGroups", []) if g.get("logGroupName") == "aws/spans"]
    if groups:
        stored = groups[0].get("storedBytes", 0)
        ok(f"Log group aws/spans exists (storedBytes={stored})")
    else:
        warn("Log group aws/spans does not exist yet; X-Ray creates it when the first span arrives")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", required=True)
    parser.add_argument("--policy-name", default="TransactionSearchAccess")
    args = parser.parse_args()

    session = boto3.Session(region_name=args.region)
    xray = session.client("xray")
    logs = session.client("logs")

    checks = (
        lambda: check_destination(xray),
        lambda: check_indexing_rule(xray),
        lambda: check_resource_policy(logs, args.policy_name),
        lambda: check_spans_log_group(logs),
    )
    for check in checks:
        try:
            check()
        except (ClientError, BotoCoreError) as exc:
            fail(f"AWS call failed: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
