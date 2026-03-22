#!/usr/bin/env python3
"""Discover all AWS SSO accounts/roles and merge into existing ~/.aws/config.

Preserves existing profiles. New profiles get sanitized names.
If a discovered (account_id, role_name) already exists under a different name,
it's skipped with a comment noting the mapping.

Usage:
    aws-list-sso-roles.py [--ensure-convention] [output_file]

Options:
    --ensure-convention  Add convention-named profiles for every account-role,
                         even if a custom-named profile already exists.
                         e.g., 'mp_analytics' exists -> also adds
                         'mpulse-qa-mpAnalytics-Snowflake'
"""

import configparser
import json
import glob
import os
import re
import subprocess
import sys
import urllib.request
import urllib.error
from datetime import datetime


def refresh_token(token_data, cache_file):
    """Refresh an expired SSO access token using the refresh token."""
    required = ("clientId", "clientSecret", "refreshToken")
    if not all(k in token_data for k in required):
        return None
    region = token_data.get("region", "us-west-2")
    url = f"https://oidc.{region}.amazonaws.com/token"
    body = json.dumps({
        "clientId": token_data["clientId"],
        "clientSecret": token_data["clientSecret"],
        "grantType": "refresh_token",
        "refreshToken": token_data["refreshToken"],
    }).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read())
        token_data["accessToken"] = result["accessToken"]
        if "refreshToken" in result:
            token_data["refreshToken"] = result["refreshToken"]
        token_data["expiresAt"] = result.get("expiresAt", token_data.get("expiresAt"))
        with open(cache_file, "w") as fh:
            json.dump(token_data, fh)
        return token_data
    except urllib.error.URLError:
        return None


def get_access_tokens():
    """Find all SSO access tokens from cache, refreshing if expired."""
    tokens = {}
    for f in glob.glob(os.path.expanduser("~/.aws/sso/cache/*.json")):
        try:
            with open(f) as fh:
                data = json.load(fh)
            if "accessToken" in data and "startUrl" in data:
                url = data["startUrl"]
                if url not in tokens or data.get("expiresAt", "") > tokens[url][0].get("expiresAt", ""):
                    tokens[url] = (data, f)
        except (json.JSONDecodeError, OSError):
            continue
    result = {}
    for url, (data, cache_file) in tokens.items():
        refreshed = refresh_token(data, cache_file)
        if refreshed:
            result[url] = refreshed
        else:
            result[url] = data
    return result


def aws_sso(command, **kwargs):
    """Run an AWS SSO CLI command and return parsed JSON."""
    args = ["aws", "sso", command, "--output", "json"]
    for k, v in kwargs.items():
        args.extend([f"--{k.replace('_', '-')}", v])
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout)


def sanitize_profile_name(name):
    """Replace spaces and special chars with hyphens, collapse multiples."""
    name = re.sub(r"[^a-zA-Z0-9_-]", "-", name)
    name = re.sub(r"-+", "-", name)
    return name.strip("-")


def discover_profiles(tokens):
    """Query SSO and return list of discovered profiles."""
    profiles = []
    for start_url, token_data in sorted(tokens.items()):
        token = token_data["accessToken"]
        region = token_data.get("region", "us-west-2")
        session_name = start_url.rstrip("/").split("//")[1].split(".")[0]

        try:
            accounts = aws_sso("list-accounts", access_token=token, region=region)
        except RuntimeError as e:
            print(f"# Skipping {start_url}: {e}", file=sys.stderr)
            continue

        for acct in sorted(accounts.get("accountList", []), key=lambda a: a.get("accountName", "")):
            acct_id = acct["accountId"]
            acct_name = acct.get("accountName", "Unknown")
            try:
                roles = aws_sso(
                    "list-account-roles",
                    account_id=acct_id,
                    access_token=token,
                    region=region,
                )
            except RuntimeError:
                continue
            for role in sorted(roles.get("roleList", []), key=lambda r: r.get("roleName", "")):
                profiles.append({
                    "account_id": acct_id,
                    "role_name": role["roleName"],
                    "session_name": session_name,
                    "start_url": start_url,
                    "region": region,
                    "account_name": acct_name,
                })
    return profiles


MERGE_METADATA_PREFIXES = (
    "# Merged AWS SSO config",
    "# Merged: ",
    "# === Existing config (preserved) ===",
    "# === Skipped",
    "# === New profiles ===",
    "# === Convention-named profiles",
    "# === New SSO sessions ===",
    "# No new profiles to add",
    "# Also exists as:",
)

# Patterns for lines that are entirely script-generated skip comments
SKIP_COMMENT_RE = re.compile(
    r"^# .+ -> already exists as '.+' \(account: \d+, role: .+\)$"
)


def strip_merge_metadata(text):
    """Remove metadata comments injected by previous runs of this script.

    Preserves all real config sections and blank lines between them,
    but strips merge headers, section dividers, and skip comments.
    """
    lines = text.splitlines()
    cleaned = []
    for line in lines:
        # Skip merge metadata header/divider lines
        if any(line.startswith(prefix) for prefix in MERGE_METADATA_PREFIXES):
            continue
        # Skip generated skip-comment lines like "# foo -> already exists as 'bar' (...)"
        if SKIP_COMMENT_RE.match(line):
            continue
        cleaned.append(line)

    # Collapse runs of blank lines to at most one
    result = []
    prev_blank = False
    for line in cleaned:
        is_blank = line.strip() == ""
        if is_blank and prev_blank:
            continue
        result.append(line)
        prev_blank = is_blank

    return "\n".join(result).strip()


def parse_existing_config(config_path):
    """Parse existing AWS config.

    Returns (clean_text, profile_map, all_profile_names, session_url_map) where:
      clean_text: existing config with previous merge metadata stripped
      profile_map: {(account_id, role_name): profile_name} (first match only)
      all_profile_names: set of all profile names in config
      session_url_map: {start_url: session_name}  (existing sessions by URL)
    """
    try:
        with open(config_path) as f:
            raw_text = f.read()
    except FileNotFoundError:
        return "", {}, set(), {}

    clean_text = strip_merge_metadata(raw_text)

    profile_map = {}
    all_profile_names = set()
    session_url_map = {}
    cp = configparser.ConfigParser()
    cp.read_string(raw_text)

    for section in cp.sections():
        # Map sso-sessions by their start URL
        if section.startswith("sso-session "):
            session_name = section[len("sso-session "):]
            start_url = cp.get(section, "sso_start_url", fallback=None)
            if start_url:
                session_url_map[start_url] = session_name

        # Map profiles by (account_id, role_name)
        acct_id = cp.get(section, "sso_account_id", fallback=None)
        role_name = cp.get(section, "sso_role_name", fallback=None)
        if acct_id and role_name:
            profile_name = section[len("profile "):] if section.startswith("profile ") else section
            all_profile_names.add(profile_name)
            key = (acct_id, role_name)
            if key not in profile_map:
                profile_map[key] = profile_name

    return clean_text, profile_map, all_profile_names, session_url_map


def main():
    config_path = os.path.expanduser("~/.aws/config")
    ensure_convention = "--ensure-convention" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--ensure-convention"]
    output_file = args[0] if args else None

    tokens = get_access_tokens()
    if not tokens:
        print("No SSO access tokens found. Run 'aws sso login' first.")
        sys.exit(1)

    clean_text, existing_map, all_profile_names, session_url_map = parse_existing_config(config_path)
    discovered = discover_profiles(tokens)

    # Build session name mapping: resolve discovered session names to existing ones by URL
    # e.g. discovered "mpulsemobile" -> existing "mpulse" (same start_url)
    session_name_map = {}  # discovered_name -> name to use
    new_session_urls = {}  # start_url -> (discovered_name, region) for truly new sessions
    for p in discovered:
        url = p["start_url"]
        discovered_name = p["session_name"]
        if discovered_name not in session_name_map:
            if url in session_url_map:
                # Existing session covers this URL — reuse its name
                session_name_map[discovered_name] = session_url_map[url]
            else:
                # Truly new session
                session_name_map[discovered_name] = discovered_name
                new_session_urls[url] = (discovered_name, p["region"])

    lines = []
    lines.append("# Merged AWS SSO config")
    lines.append(f"# Merged: {datetime.now().isoformat()}")
    lines.append("")
    lines.append("# === Existing config (preserved) ===")
    lines.append(clean_text)
    lines.append("")

    # New sso-sessions (only truly new URLs)
    if new_session_urls:
        lines.append("# === New SSO sessions ===")
        for url, (name, region) in sorted(new_session_urls.items()):
            lines.append(f"[sso-session {name}]")
            lines.append(f"sso_start_url = {url}")
            lines.append(f"sso_region = {region}")
            lines.append("")

    # Classify discovered profiles
    new_profiles = []
    convention_profiles = []  # convention-named aliases for existing custom profiles
    skipped = []
    for p in discovered:
        key = (p["account_id"], p["role_name"])
        sanitized_name = sanitize_profile_name(f"{p['account_name']}-{p['role_name']}")
        # Resolve session name to existing one if available
        resolved_session = session_name_map.get(p["session_name"], p["session_name"])
        if key in existing_map:
            existing_name = existing_map[key]
            if existing_name != sanitized_name:
                if ensure_convention and sanitized_name not in all_profile_names:
                    # Add convention-named profile alongside the custom one
                    convention_profiles.append((sanitized_name, existing_name, p, resolved_session))
                else:
                    skipped.append((sanitized_name, existing_name, p))
        else:
            new_profiles.append((sanitized_name, p, resolved_session))

    if skipped:
        lines.append("# === Skipped (already exist under different name) ===")
        for sanitized_name, existing_name, p in skipped:
            lines.append(f"# {sanitized_name} -> already exists as '{existing_name}' "
                         f"(account: {p['account_id']}, role: {p['role_name']})")
        lines.append("")

    def _format_profile(name, session, p):
        return [
            f"[profile {name}]",
            f"sso_session = {session}",
            f"sso_account_id = {p['account_id']}",
            f"sso_role_name = {p['role_name']}",
            f"region = {p['region']}",
            "output = yaml",
            "",
        ]

    if convention_profiles:
        lines.append("# === Convention-named profiles (aliases for existing custom profiles) ===")
        for sanitized_name, existing_name, p, resolved_session in convention_profiles:
            lines.append(f"# Also exists as: '{existing_name}'")
            lines.extend(_format_profile(sanitized_name, resolved_session, p))

    if new_profiles:
        lines.append("# === New profiles ===")
        for sanitized_name, p, resolved_session in new_profiles:
            lines.extend(_format_profile(sanitized_name, resolved_session, p))

    if not new_profiles and not convention_profiles and not new_session_urls:
        lines.append("# No new profiles to add - config is up to date")
        lines.append("")

    output = "\n".join(lines)
    if output_file:
        with open(output_file, "w") as f:
            f.write(output)
        print(f"Merged config written to {output_file}")
    else:
        print(output)


if __name__ == "__main__":
    main()
