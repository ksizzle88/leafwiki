"""Tests for aws-list-sso-roles.py

Run: pytest /workspace/.claude/scripts/test_aws_list_sso_roles.py -v
"""

import importlib.util
import json
import os
import re
import textwrap

import pytest

# Import the script as a module
_spec = importlib.util.spec_from_file_location(
    "aws_list_sso_roles",
    os.path.join(os.path.dirname(__file__), "aws-list-sso-roles.py"),
)
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)

strip_merge_metadata = mod.strip_merge_metadata
sanitize_profile_name = mod.sanitize_profile_name
parse_existing_config = mod.parse_existing_config
refresh_token = mod.refresh_token
get_access_tokens = mod.get_access_tokens
discover_profiles = mod.discover_profiles
MERGE_METADATA_PREFIXES = mod.MERGE_METADATA_PREFIXES
SKIP_COMMENT_RE = mod.SKIP_COMMENT_RE
main = mod.main


# ---------------------------------------------------------------------------
# Fixtures: reusable config snippets
# ---------------------------------------------------------------------------

BASELINE_CONFIG = textwrap.dedent("""\
    [default]
    sso_start_url = https://mpulsemobile.awsapps.com/start
    sso_region=us-west-2
    region = us-west-2
    output = yaml
    sso_session = mpulse
    profile = mpulse-qa
    sso_account_id = 277014072346
    sso_role_name = AWSPowerUserAccess

    [sso-session dphs]
    sso_start_url = https://decisionpoint.awsapps.com/start
    sso_region = us-east-1
    sso_registration_scopes = sso:account:access

    [profile prod]
    sso_session = dphs
    sso_account_id = 223016925961
    sso_role_name = AWSPowerUserAccess
    region = us-east-1
    output = yaml

    [sso-session mpulse]
    sso_start_url = https://mpulsemobile.awsapps.com/start
    sso_region = us-west-2
    sso_registration_scopes = sso:account:access

    [profile mp_analytics]
    sso_session = mpulse
    sso_account_id = 277014072346
    sso_role_name = mpAnalytics-Snowflake
    region = us-west-2
    output = yaml
""")

MERGED_CONFIG = textwrap.dedent("""\
    # Merged AWS SSO config
    # Merged: 2026-03-11T10:11:36.312364

    # === Existing config (preserved) ===
    [default]
    sso_start_url = https://mpulsemobile.awsapps.com/start
    sso_region=us-west-2
    region = us-west-2
    output = yaml
    sso_session = mpulse
    profile = mpulse-qa
    sso_account_id = 277014072346
    sso_role_name = AWSPowerUserAccess

    [sso-session dphs]
    sso_start_url = https://decisionpoint.awsapps.com/start
    sso_region = us-east-1

    [profile prod]
    sso_session = dphs
    sso_account_id = 223016925961
    sso_role_name = AWSPowerUserAccess
    region = us-east-1
    output = yaml

    [sso-session mpulse]
    sso_start_url = https://mpulsemobile.awsapps.com/start
    sso_region = us-west-2

    [profile mp_analytics]
    sso_session = mpulse
    sso_account_id = 277014072346
    sso_role_name = mpAnalytics-Snowflake
    region = us-west-2
    output = yaml

    # === Skipped (already exist under different name) ===
    # mpulse-qa-AWSPowerUserAccess -> already exists as 'default' (account: 277014072346, role: AWSPowerUserAccess)
    # mpulse-qa-mpAnalytics-Snowflake -> already exists as 'mp_analytics' (account: 277014072346, role: mpAnalytics-Snowflake)

    # === New profiles ===
    [profile SomeNew-Profile]
    sso_session = mpulse
    sso_account_id = 999999999999
    sso_role_name = NewRole
    region = us-west-2
    output = yaml
""")


DOUBLE_MERGED_CONFIG = textwrap.dedent("""\
    # Merged AWS SSO config
    # Merged: 2026-03-11T11:08:38.000000

    # === Existing config (preserved) ===
    # Merged AWS SSO config
    # Merged: 2026-03-11T10:11:36.312364

    # === Existing config (preserved) ===
    [default]
    sso_account_id = 277014072346
    sso_role_name = AWSPowerUserAccess

    # === Skipped (already exist under different name) ===
    # foo -> already exists as 'default' (account: 277014072346, role: AWSPowerUserAccess)

    # No new profiles to add - config is up to date
""")


@pytest.fixture
def baseline_config_file(tmp_path):
    p = tmp_path / "config"
    p.write_text(BASELINE_CONFIG)
    return str(p)


@pytest.fixture
def merged_config_file(tmp_path):
    p = tmp_path / "config"
    p.write_text(MERGED_CONFIG)
    return str(p)


@pytest.fixture
def double_merged_config_file(tmp_path):
    p = tmp_path / "config"
    p.write_text(DOUBLE_MERGED_CONFIG)
    return str(p)


# ---------------------------------------------------------------------------
# Tests: sanitize_profile_name
# ---------------------------------------------------------------------------

class TestSanitizeProfileName:
    def test_simple_name(self):
        assert sanitize_profile_name("mpulse-qa") == "mpulse-qa"

    def test_spaces_replaced(self):
        assert sanitize_profile_name("My Account Name") == "My-Account-Name"

    def test_special_chars_replaced(self):
        assert sanitize_profile_name("acct@name!here") == "acct-name-here"

    def test_consecutive_hyphens_collapsed(self):
        assert sanitize_profile_name("a---b") == "a-b"

    def test_leading_trailing_hyphens_stripped(self):
        assert sanitize_profile_name("-foo-") == "foo"

    def test_underscores_preserved(self):
        assert sanitize_profile_name("my_profile_name") == "my_profile_name"

    def test_mixed(self):
        assert sanitize_profile_name("AWS Prod (us-east-1)") == "AWS-Prod-us-east-1"

    def test_empty_string(self):
        assert sanitize_profile_name("") == ""

    def test_all_special(self):
        assert sanitize_profile_name("@#$%") == ""


# ---------------------------------------------------------------------------
# Tests: strip_merge_metadata
# ---------------------------------------------------------------------------

class TestStripMergeMetadata:
    def test_strips_merge_header(self):
        text = "# Merged AWS SSO config\n# Merged: 2026-01-01T00:00:00\n\n[default]\nfoo = bar"
        result = strip_merge_metadata(text)
        assert result == "[default]\nfoo = bar"

    def test_strips_section_dividers(self):
        text = "# === Existing config (preserved) ===\n[default]\nfoo = bar\n\n# === New profiles ===\n[profile new]\nbaz = qux"
        result = strip_merge_metadata(text)
        assert "[default]" in result
        assert "[profile new]" in result
        assert "# === Existing" not in result
        assert "# === New profiles" not in result

    def test_strips_skip_comments(self):
        text = "[default]\nfoo = bar\n\n# foo-bar -> already exists as 'baz' (account: 123456, role: Admin)\n\n[profile x]\na = b"
        result = strip_merge_metadata(text)
        assert "already exists as" not in result
        assert "[default]" in result
        assert "[profile x]" in result

    def test_strips_also_exists_as(self):
        text = "# Also exists as: 'prod'\n[profile foo]\na = b"
        result = strip_merge_metadata(text)
        assert "Also exists as" not in result
        assert "[profile foo]" in result

    def test_strips_no_new_profiles(self):
        text = "[default]\nfoo = bar\n\n# No new profiles to add - config is up to date"
        result = strip_merge_metadata(text)
        assert "No new profiles" not in result
        assert "[default]" in result

    def test_collapses_blank_lines(self):
        text = "[default]\nfoo = bar\n\n\n\n\n[profile x]\na = b"
        result = strip_merge_metadata(text)
        # Should have at most one blank line between sections
        assert "\n\n\n" not in result
        assert "[default]\nfoo = bar\n\n[profile x]\na = b" == result

    def test_preserves_real_comments(self):
        text = "[default]\n# this is a real user comment\nfoo = bar"
        result = strip_merge_metadata(text)
        assert "# this is a real user comment" in result

    def test_double_merged_nesting(self):
        """The original bug: double-merged config should flatten to just the real sections."""
        result = strip_merge_metadata(DOUBLE_MERGED_CONFIG)
        assert "# Merged AWS SSO config" not in result
        assert "# Merged:" not in result
        assert "# === Existing config" not in result
        assert "# === Skipped" not in result
        assert "already exists as" not in result
        assert "[default]" in result
        assert "sso_account_id = 277014072346" in result

    def test_empty_input(self):
        assert strip_merge_metadata("") == ""

    def test_only_metadata(self):
        text = "# Merged AWS SSO config\n# Merged: 2026-01-01\n# === Existing config (preserved) ===\n# No new profiles to add - config is up to date"
        assert strip_merge_metadata(text) == ""

    def test_idempotent(self):
        """Stripping twice should give the same result."""
        once = strip_merge_metadata(MERGED_CONFIG)
        twice = strip_merge_metadata(once)
        assert once == twice


# ---------------------------------------------------------------------------
# Tests: parse_existing_config
# ---------------------------------------------------------------------------

class TestParseExistingConfig:
    def test_nonexistent_file(self):
        clean, pmap, names, smap = parse_existing_config("/nonexistent/path")
        assert clean == ""
        assert pmap == {}
        assert names == set()
        assert smap == {}

    def test_baseline_profile_map(self, baseline_config_file):
        _, pmap, _, _ = parse_existing_config(baseline_config_file)
        assert ("277014072346", "AWSPowerUserAccess") in pmap
        assert pmap[("277014072346", "AWSPowerUserAccess")] == "default"
        assert ("223016925961", "AWSPowerUserAccess") in pmap
        assert pmap[("223016925961", "AWSPowerUserAccess")] == "prod"
        assert ("277014072346", "mpAnalytics-Snowflake") in pmap
        assert pmap[("277014072346", "mpAnalytics-Snowflake")] == "mp_analytics"

    def test_baseline_all_profile_names(self, baseline_config_file):
        _, _, names, _ = parse_existing_config(baseline_config_file)
        assert "default" in names
        assert "prod" in names
        assert "mp_analytics" in names

    def test_baseline_session_url_map(self, baseline_config_file):
        _, _, _, smap = parse_existing_config(baseline_config_file)
        assert "https://decisionpoint.awsapps.com/start" in smap
        assert smap["https://decisionpoint.awsapps.com/start"] == "dphs"
        assert "https://mpulsemobile.awsapps.com/start" in smap
        assert smap["https://mpulsemobile.awsapps.com/start"] == "mpulse"

    def test_clean_text_strips_metadata(self, merged_config_file):
        clean, _, _, _ = parse_existing_config(merged_config_file)
        assert "# Merged AWS SSO config" not in clean
        assert "# Merged:" not in clean
        assert "# === Existing config" not in clean
        assert "already exists as" not in clean
        # But real config sections are preserved
        assert "[default]" in clean
        assert "[profile prod]" in clean

    def test_merged_config_includes_new_profiles(self, merged_config_file):
        _, pmap, names, _ = parse_existing_config(merged_config_file)
        # The "new" profile from the merged config should be detected
        assert ("999999999999", "NewRole") in pmap
        assert "SomeNew-Profile" in names

    def test_first_match_wins_in_profile_map(self, tmp_path):
        """When two profiles share the same (account, role), profile_map keeps the first."""
        config = textwrap.dedent("""\
            [profile custom-name]
            sso_account_id = 111111111111
            sso_role_name = Admin

            [profile convention-name]
            sso_account_id = 111111111111
            sso_role_name = Admin
        """)
        p = tmp_path / "config"
        p.write_text(config)
        _, pmap, names, _ = parse_existing_config(str(p))
        assert pmap[("111111111111", "Admin")] == "custom-name"
        assert "custom-name" in names
        assert "convention-name" in names


# ---------------------------------------------------------------------------
# Tests: refresh_token
# ---------------------------------------------------------------------------

class TestRefreshToken:
    def test_missing_client_id(self, tmp_path):
        data = {"clientSecret": "s", "refreshToken": "r"}
        assert refresh_token(data, str(tmp_path / "f")) is None

    def test_missing_client_secret(self, tmp_path):
        data = {"clientId": "c", "refreshToken": "r"}
        assert refresh_token(data, str(tmp_path / "f")) is None

    def test_missing_refresh_token(self, tmp_path):
        data = {"clientId": "c", "clientSecret": "s"}
        assert refresh_token(data, str(tmp_path / "f")) is None

    def test_all_keys_missing(self, tmp_path):
        data = {"accessToken": "a", "startUrl": "https://example.com"}
        assert refresh_token(data, str(tmp_path / "f")) is None

    def test_url_error_returns_none(self, tmp_path, monkeypatch):
        import urllib.request
        import urllib.error

        def mock_urlopen(req):
            raise urllib.error.URLError("connection refused")

        monkeypatch.setattr(urllib.request, "urlopen", mock_urlopen)
        data = {"clientId": "c", "clientSecret": "s", "refreshToken": "r", "region": "us-west-2"}
        assert refresh_token(data, str(tmp_path / "f")) is None

    def test_successful_refresh(self, tmp_path, monkeypatch):
        import urllib.request

        cache_file = str(tmp_path / "token.json")
        response_body = json.dumps({
            "accessToken": "new-token",
            "refreshToken": "new-refresh",
            "expiresAt": "2026-12-31T00:00:00Z",
        }).encode()

        class MockResponse:
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass
            def read(self):
                return response_body

        monkeypatch.setattr(urllib.request, "urlopen", lambda req: MockResponse())

        data = {
            "clientId": "c",
            "clientSecret": "s",
            "refreshToken": "old-refresh",
            "accessToken": "old-token",
            "region": "us-west-2",
        }
        result = refresh_token(data, cache_file)
        assert result is not None
        assert result["accessToken"] == "new-token"
        assert result["refreshToken"] == "new-refresh"
        # Verify cache file was updated
        with open(cache_file) as f:
            saved = json.load(f)
        assert saved["accessToken"] == "new-token"


# ---------------------------------------------------------------------------
# Tests: get_access_tokens
# ---------------------------------------------------------------------------

class TestGetAccessTokens:
    def test_picks_latest_expiry(self, tmp_path, monkeypatch):
        cache_dir = tmp_path / ".aws" / "sso" / "cache"
        cache_dir.mkdir(parents=True)

        old_token = {
            "accessToken": "old",
            "startUrl": "https://example.com/start",
            "expiresAt": "2026-01-01T00:00:00Z",
            "region": "us-west-2",
        }
        new_token = {
            "accessToken": "new",
            "startUrl": "https://example.com/start",
            "expiresAt": "2026-12-31T00:00:00Z",
            "region": "us-west-2",
        }

        (cache_dir / "old.json").write_text(json.dumps(old_token))
        (cache_dir / "new.json").write_text(json.dumps(new_token))

        monkeypatch.setattr(os.path, "expanduser", lambda p: str(tmp_path / p.lstrip("~/")))
        # refresh_token will return None (no refresh keys), so it falls back to data
        result = get_access_tokens()
        assert len(result) == 1
        assert result["https://example.com/start"]["accessToken"] == "new"

    def test_skips_invalid_json(self, tmp_path, monkeypatch):
        cache_dir = tmp_path / ".aws" / "sso" / "cache"
        cache_dir.mkdir(parents=True)

        (cache_dir / "bad.json").write_text("not json")
        (cache_dir / "good.json").write_text(json.dumps({
            "accessToken": "tok",
            "startUrl": "https://example.com/start",
            "region": "us-west-2",
        }))

        monkeypatch.setattr(os.path, "expanduser", lambda p: str(tmp_path / p.lstrip("~/")))
        result = get_access_tokens()
        assert len(result) == 1

    def test_skips_files_without_access_token(self, tmp_path, monkeypatch):
        cache_dir = tmp_path / ".aws" / "sso" / "cache"
        cache_dir.mkdir(parents=True)

        (cache_dir / "noreg.json").write_text(json.dumps({
            "startUrl": "https://example.com/start",
        }))

        monkeypatch.setattr(os.path, "expanduser", lambda p: str(tmp_path / p.lstrip("~/")))
        result = get_access_tokens()
        assert len(result) == 0

    def test_empty_cache_dir(self, tmp_path, monkeypatch):
        cache_dir = tmp_path / ".aws" / "sso" / "cache"
        cache_dir.mkdir(parents=True)
        monkeypatch.setattr(os.path, "expanduser", lambda p: str(tmp_path / p.lstrip("~/")))
        result = get_access_tokens()
        assert result == {}


# ---------------------------------------------------------------------------
# Tests: discover_profiles (mocked SSO calls)
# ---------------------------------------------------------------------------

class TestDiscoverProfiles:
    def test_basic_discovery(self, monkeypatch):
        def mock_aws_sso(command, **kwargs):
            if command == "list-accounts":
                return {"accountList": [
                    {"accountId": "111", "accountName": "Acme"},
                ]}
            elif command == "list-account-roles":
                return {"roleList": [
                    {"roleName": "Admin"},
                    {"roleName": "ReadOnly"},
                ]}

        monkeypatch.setattr(mod, "aws_sso", mock_aws_sso)
        tokens = {
            "https://example.com/start": {
                "accessToken": "tok",
                "region": "us-west-2",
            }
        }
        profiles = discover_profiles(tokens)
        assert len(profiles) == 2
        assert profiles[0]["account_id"] == "111"
        assert profiles[0]["role_name"] == "Admin"
        assert profiles[0]["session_name"] == "example"
        assert profiles[1]["role_name"] == "ReadOnly"

    def test_skips_failed_accounts(self, monkeypatch):
        def mock_aws_sso(command, **kwargs):
            if command == "list-accounts":
                raise RuntimeError("expired token")
            return {}

        monkeypatch.setattr(mod, "aws_sso", mock_aws_sso)
        tokens = {"https://example.com/start": {"accessToken": "tok", "region": "us-west-2"}}
        profiles = discover_profiles(tokens)
        assert profiles == []

    def test_skips_failed_roles(self, monkeypatch):
        def mock_aws_sso(command, **kwargs):
            if command == "list-accounts":
                return {"accountList": [{"accountId": "111", "accountName": "Acme"}]}
            elif command == "list-account-roles":
                raise RuntimeError("role listing failed")

        monkeypatch.setattr(mod, "aws_sso", mock_aws_sso)
        tokens = {"https://example.com/start": {"accessToken": "tok", "region": "us-west-2"}}
        profiles = discover_profiles(tokens)
        assert profiles == []

    def test_sorted_output(self, monkeypatch):
        def mock_aws_sso(command, **kwargs):
            if command == "list-accounts":
                return {"accountList": [
                    {"accountId": "2", "accountName": "Zulu"},
                    {"accountId": "1", "accountName": "Alpha"},
                ]}
            elif command == "list-account-roles":
                return {"roleList": [{"roleName": "Admin"}]}

        monkeypatch.setattr(mod, "aws_sso", mock_aws_sso)
        tokens = {"https://example.com/start": {"accessToken": "tok", "region": "us-west-2"}}
        profiles = discover_profiles(tokens)
        assert profiles[0]["account_name"] == "Alpha"
        assert profiles[1]["account_name"] == "Zulu"


# ---------------------------------------------------------------------------
# Tests: main() end-to-end with mocked SSO
# ---------------------------------------------------------------------------

def _make_mock_sso(accounts_roles):
    """Create a mock aws_sso that returns given accounts and roles."""
    def mock(command, **kwargs):
        if command == "list-accounts":
            return {"accountList": [
                {"accountId": aid, "accountName": name}
                for aid, name, _ in accounts_roles
            ]}
        elif command == "list-account-roles":
            acct_id = kwargs.get("account_id")
            for aid, _, roles in accounts_roles:
                if aid == acct_id:
                    return {"roleList": [{"roleName": r} for r in roles]}
            return {"roleList": []}
    return mock


class TestMainEndToEnd:
    def _run_main(self, monkeypatch, tmp_path, existing_config, accounts_roles,
                  ensure_convention=False):
        """Helper: write config, mock SSO, run main(), return output text."""
        config_path = str(tmp_path / "config")
        output_path = str(tmp_path / "output")

        if existing_config:
            with open(config_path, "w") as f:
                f.write(existing_config)

        monkeypatch.setattr(mod, "aws_sso", _make_mock_sso(accounts_roles))
        # Mock get_access_tokens to return a single token
        monkeypatch.setattr(mod, "get_access_tokens", lambda: {
            "https://mpulsemobile.awsapps.com/start": {
                "accessToken": "tok",
                "region": "us-west-2",
            }
        })

        argv = ["script", output_path]
        if ensure_convention:
            argv.insert(1, "--ensure-convention")
        monkeypatch.setattr("sys.argv", argv)
        monkeypatch.setattr(os.path, "expanduser", lambda p: config_path if p == "~/.aws/config" else p)

        main()
        with open(output_path) as f:
            return f.read()

    def test_new_profile_added(self, monkeypatch, tmp_path):
        accounts = [("999", "NewAcct", ["Admin"])]
        output = self._run_main(monkeypatch, tmp_path, BASELINE_CONFIG, accounts)
        assert "[profile NewAcct-Admin]" in output
        assert "sso_account_id = 999" in output
        assert "# === New profiles ===" in output

    def test_existing_profile_skipped(self, monkeypatch, tmp_path):
        # Account 277014072346 / AWSPowerUserAccess already exists as 'default'
        accounts = [("277014072346", "mpulse-qa", ["AWSPowerUserAccess"])]
        output = self._run_main(monkeypatch, tmp_path, BASELINE_CONFIG, accounts)
        assert "already exists as 'default'" in output
        assert "# === Skipped" in output

    def test_convention_profile_added(self, monkeypatch, tmp_path):
        accounts = [("277014072346", "mpulse-qa", ["AWSPowerUserAccess"])]
        output = self._run_main(monkeypatch, tmp_path, BASELINE_CONFIG, accounts,
                                ensure_convention=True)
        assert "[profile mpulse-qa-AWSPowerUserAccess]" in output
        assert "# Also exists as: 'default'" in output

    def test_convention_not_duplicated_on_rerun(self, monkeypatch, tmp_path):
        """Ensure --ensure-convention doesn't duplicate profiles already in config."""
        accounts = [("277014072346", "mpulse-qa", ["AWSPowerUserAccess"])]
        # First run
        output1 = self._run_main(monkeypatch, tmp_path, BASELINE_CONFIG, accounts,
                                 ensure_convention=True)
        assert "[profile mpulse-qa-AWSPowerUserAccess]" in output1

        # Write output1 as the new config and run again
        config_path = str(tmp_path / "config")
        with open(config_path, "w") as f:
            f.write(output1)

        output_path2 = str(tmp_path / "output2")
        monkeypatch.setattr("sys.argv", ["script", "--ensure-convention", output_path2])
        main()
        with open(output_path2) as f:
            output2 = f.read()

        # The convention profile should NOT appear in the convention section again
        assert output2.count("[profile mpulse-qa-AWSPowerUserAccess]") == 1
        # It should be in the preserved existing config, not re-added
        convention_section = "# === Convention-named profiles"
        if convention_section in output2:
            after_convention = output2.split(convention_section)[1]
            assert "mpulse-qa-AWSPowerUserAccess" not in after_convention

    def test_no_new_profiles_message(self, monkeypatch, tmp_path):
        # All discovered profiles already exist
        accounts = [("223016925961", "AWS-Prod-Env", ["AWSPowerUserAccess"])]
        output = self._run_main(monkeypatch, tmp_path, BASELINE_CONFIG, accounts)
        assert "# No new profiles to add" in output

    def test_session_name_resolved_to_existing(self, monkeypatch, tmp_path):
        """Discovered session 'mpulsemobile' should resolve to existing 'mpulse'."""
        accounts = [("999", "NewAcct", ["Admin"])]
        output = self._run_main(monkeypatch, tmp_path, BASELINE_CONFIG, accounts)
        # The new profile should use 'mpulse' not 'mpulsemobile'
        assert "sso_session = mpulse" in output

    def test_empty_existing_config(self, monkeypatch, tmp_path):
        accounts = [("111", "Acme", ["Admin"])]
        output = self._run_main(monkeypatch, tmp_path, "", accounts)
        assert "[profile Acme-Admin]" in output
        assert "# === New SSO sessions ===" in output
        assert "[sso-session mpulsemobile]" in output

    def test_preserves_existing_config_content(self, monkeypatch, tmp_path):
        accounts = [("999", "New", ["Role"])]
        output = self._run_main(monkeypatch, tmp_path, BASELINE_CONFIG, accounts)
        assert "[default]" in output
        assert "[profile prod]" in output
        assert "[sso-session dphs]" in output
        assert "[profile mp_analytics]" in output


# ---------------------------------------------------------------------------
# Tests: idempotency (the critical property)
# ---------------------------------------------------------------------------

class TestIdempotency:
    def test_strip_is_idempotent(self):
        """strip_merge_metadata applied twice gives the same result."""
        once = strip_merge_metadata(MERGED_CONFIG)
        twice = strip_merge_metadata(once)
        assert once == twice

    def test_main_output_stable_after_rerun(self, monkeypatch, tmp_path):
        """Running main() on its own output should not grow the file."""
        accounts = [
            ("277014072346", "mpulse-qa", ["AWSPowerUserAccess", "mpAnalytics-Snowflake"]),
            ("223016925961", "AWS-Prod-Env", ["AWSPowerUserAccess"]),
            ("999", "NewAcct", ["Admin"]),
        ]

        monkeypatch.setattr(mod, "aws_sso", _make_mock_sso(accounts))
        monkeypatch.setattr(mod, "get_access_tokens", lambda: {
            "https://mpulsemobile.awsapps.com/start": {
                "accessToken": "tok",
                "region": "us-west-2",
            }
        })

        config_path = str(tmp_path / "config")
        with open(config_path, "w") as f:
            f.write(BASELINE_CONFIG)
        monkeypatch.setattr(os.path, "expanduser", lambda p: config_path if p == "~/.aws/config" else p)

        # Run 1
        out1 = str(tmp_path / "out1")
        monkeypatch.setattr("sys.argv", ["script", "--ensure-convention", out1])
        main()
        with open(out1) as f:
            text1 = f.read()

        # Write output back as config
        with open(config_path, "w") as f:
            f.write(text1)

        # Run 2
        out2 = str(tmp_path / "out2")
        monkeypatch.setattr("sys.argv", ["script", "--ensure-convention", out2])
        main()
        with open(out2) as f:
            text2 = f.read()

        # Run 3
        with open(config_path, "w") as f:
            f.write(text2)
        out3 = str(tmp_path / "out3")
        monkeypatch.setattr("sys.argv", ["script", "--ensure-convention", out3])
        main()
        with open(out3) as f:
            text3 = f.read()

        # Runs 2 and 3 should be identical (minus timestamp)
        def strip_ts(t):
            return re.sub(r"# Merged: .+", "# Merged: <TS>", t)

        assert strip_ts(text2) == strip_ts(text3), "Output should stabilize after first re-run"

    def test_no_nested_headers_after_rerun(self, monkeypatch, tmp_path):
        """The original bug: re-running should not nest '# Merged' headers."""
        accounts = [("999", "New", ["Role"])]
        monkeypatch.setattr(mod, "aws_sso", _make_mock_sso(accounts))
        monkeypatch.setattr(mod, "get_access_tokens", lambda: {
            "https://mpulsemobile.awsapps.com/start": {
                "accessToken": "tok",
                "region": "us-west-2",
            }
        })

        config_path = str(tmp_path / "config")
        with open(config_path, "w") as f:
            f.write(BASELINE_CONFIG)
        monkeypatch.setattr(os.path, "expanduser", lambda p: config_path if p == "~/.aws/config" else p)

        # Run 3 times, feeding output back each time
        for i in range(3):
            out = str(tmp_path / f"out{i}")
            monkeypatch.setattr("sys.argv", ["script", out])
            main()
            with open(out) as f:
                text = f.read()
            with open(config_path, "w") as f:
                f.write(text)

        # Final output should have exactly ONE merge header
        assert text.count("# Merged AWS SSO config") == 1
        assert text.count("# === Existing config (preserved) ===") == 1


# ---------------------------------------------------------------------------
# Tests: SKIP_COMMENT_RE pattern
# ---------------------------------------------------------------------------

class TestSkipCommentRegex:
    def test_matches_standard_skip(self):
        line = "# foo-bar -> already exists as 'baz' (account: 123456789012, role: Admin)"
        assert SKIP_COMMENT_RE.match(line)

    def test_matches_hyphenated_role(self):
        line = "# mpulse-qa-mpAnalytics-Snowflake -> already exists as 'mp_analytics' (account: 277014072346, role: mpAnalytics-Snowflake)"
        assert SKIP_COMMENT_RE.match(line)

    def test_no_match_real_comment(self):
        line = "# this is a real user comment"
        assert not SKIP_COMMENT_RE.match(line)

    def test_no_match_section_header(self):
        line = "[profile foo]"
        assert not SKIP_COMMENT_RE.match(line)

    def test_no_match_partial(self):
        line = "# foo -> already exists"
        assert not SKIP_COMMENT_RE.match(line)
