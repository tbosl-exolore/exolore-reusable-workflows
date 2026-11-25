#!/usr/bin/env python3
"""Reject common secret formats and internal/customer data in this public repo."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
)
PRIVATE_IPV4 = re.compile(r"\b(?:10\.(?:\d{1,3}\.){2}\d{1,3}|192\.168\.(?:\d{1,3}\.)\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.(?:\d{1,3}\.)\d{1,3})\b")
CUSTOMER_MARKERS = ("LLS" + "-Events", "i-" + "LogiX", "Workflow " + "Assistant")
failures: list[str] = []

for path in ROOT.rglob("*"):
    if not path.is_file() or ".git" in path.parts:
        continue
    try:
        content = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    relative = path.relative_to(ROOT).as_posix()
    for pattern in SECRET_PATTERNS:
        if pattern.search(content):
            failures.append(f"{relative}: matches credential pattern {pattern.pattern}")
    if any(marker.casefold() in content.casefold() for marker in CUSTOMER_MARKERS):
        failures.append(f"{relative}: contains a customer-specific project marker")
    if relative.startswith(("docs/", "test/fixtures/")) and PRIVATE_IPV4.search(content):
        failures.append(f"{relative}: contains a private IPv4 address")

if failures:
    print("Public-content scan failed:", file=sys.stderr)
    print("\n".join(f"- {failure}" for failure in failures), file=sys.stderr)
    raise SystemExit(1)

print("Public-content scan passed: no known credential patterns or customer-specific values found.")
