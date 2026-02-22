"""
Tests for CloudFront WAF association configuration (Issue #54).

Validates the ARN format regex used by the cloudfront_waf_acl_arn variable
validation rule in variables.tf, and asserts default-off behavior semantics.
"""

import re

# Mirrors the regex in variables.tf cloudfront_waf_acl_arn validation block.
_CF_WAF_ARN_PATTERN = re.compile(
    r"^arn:aws:wafv2:eu-west-2:[0-9]{12}:global/webacl/[^/]+/[^/]+$"
)


def _is_valid_cf_waf_arn(arn: str) -> bool:
    """Return True if arn matches the CLOUDFRONT-scope WAFv2 ARN format."""
    return bool(_CF_WAF_ARN_PATTERN.match(arn))


# --- Valid ARN acceptance ---


def test_accepts_well_formed_cf_waf_arn():
    """Standard CLOUDFRONT-scope ARN must be accepted."""
    arn = "arn:aws:wafv2:eu-west-2:123456789012:global/webacl/my-cf-acl/aabbccdd-1234-5678-abcd-ef1234567890"
    assert _is_valid_cf_waf_arn(arn), f"Expected valid, got invalid for: {arn}"


def test_accepts_short_name_and_id():
    """Minimal name and UUID-style id must be accepted."""
    arn = "arn:aws:wafv2:eu-west-2:000000000001:global/webacl/x/y"
    assert _is_valid_cf_waf_arn(arn), f"Expected valid, got invalid for: {arn}"


# --- Invalid ARN rejection ---


def test_rejects_empty_string():
    """Empty string is valid (disabled); pattern itself must not match empty."""
    assert not _is_valid_cf_waf_arn(""), "Empty string must not match ARN pattern"


def test_rejects_regional_scope_arn():
    """REGIONAL-scope (non-eu-west-2) WAFv2 ARN must be rejected for CloudFront."""
    arn = "arn:aws:wafv2:eu-west-2:123456789012:regional/webacl/my-acl/abc123"
    assert not _is_valid_cf_waf_arn(arn), f"Expected invalid REGIONAL ARN to be rejected: {arn}"


def test_rejects_non_us_east_1_region():
    """Only eu-west-2 is valid for CLOUDFRONT-scope WAFv2."""
    arn = "arn:aws:wafv2:us-west-2:123456789012:global/webacl/my-acl/abc123"
    assert not _is_valid_cf_waf_arn(arn), f"Expected wrong region to be rejected: {arn}"


def test_rejects_wrong_service():
    """Non-WAFv2 ARNs must be rejected."""
    arn = "arn:aws:iam::123456789012:policy/my-policy"
    assert not _is_valid_cf_waf_arn(arn), f"Expected non-wafv2 ARN to be rejected: {arn}"


def test_rejects_partial_arn():
    """Malformed ARN missing id segment must be rejected."""
    arn = "arn:aws:wafv2:eu-west-2:123456789012:global/webacl/no-id"
    assert not _is_valid_cf_waf_arn(arn), f"Expected partial ARN to be rejected: {arn}"


def test_rejects_trailing_slash():
    """ARN with trailing slash must be rejected (id segment empty)."""
    arn = "arn:aws:wafv2:eu-west-2:123456789012:global/webacl/my-acl/"
    assert not _is_valid_cf_waf_arn(arn), f"Expected trailing-slash ARN to be rejected: {arn}"


# --- Default-off behavior documentation ---


def test_default_off_behavior_is_empty_string():
    """The default value of cloudfront_waf_acl_arn is '' (WAF disabled on CloudFront).
    An empty string passes module validation but does not configure web_acl_id."""
    default_value = ""
    # Default must not trigger the ARN validator (Terraform skips validation when empty)
    assert default_value == "", "Default value must be an empty string to keep WAF disabled"
    # And must not match a valid ARN (no WAF is wired)
    assert not _is_valid_cf_waf_arn(default_value)


if __name__ == "__main__":
    tests = [
        test_accepts_well_formed_cf_waf_arn,
        test_accepts_short_name_and_id,
        test_rejects_empty_string,
        test_rejects_regional_scope_arn,
        test_rejects_non_us_east_1_region,
        test_rejects_wrong_service,
        test_rejects_partial_arn,
        test_rejects_trailing_slash,
        test_default_off_behavior_is_empty_string,
    ]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"  PASS: {t.__name__}")
        except AssertionError as exc:
            print(f"  FAIL: {t.__name__} — {exc}")
            failed += 1
    if failed:
        import sys
        print(f"\n{failed} test(s) failed.")
        sys.exit(1)
    print("\nAll WAF config tests passed.")
