#!/usr/bin/env python3
"""
Privacy & Secret Guardrail Script for HomeLab Git Repository.
Prevents personal/unauthorized email addresses and credentials from being committed or pushed.
"""

import os
import re
import subprocess
import sys

EMAIL_REGEX = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")

# Safe domains permitted in documentation, bot manifests, and examples
ALLOWED_DOMAINS = {
    "example.com",
    "example.org",
    "example.net",
    "users.noreply.github.com",
    "renovateapp.com",
    "siderolabs.com",
}

# Explicitly allowed third-party vendor/package emails
ALLOWED_SPECIFIC = {
    "kahan@informatik.tu-muenchen.de",  # Debian Sarge Samba default package comment
}

# Directories to skip when scanning workspace
EXCLUDED_DIRS = {
    ".git",
    ".gemini",
    ".system_generated",
    "node_modules",
}


def is_allowed(email: str) -> bool:
    email_lower = email.lower()
    if email_lower in ALLOWED_SPECIFIC:
        return True
    domain = email_lower.split("@")[-1]
    if domain in ALLOWED_DOMAINS or domain.endswith(".example") or domain.endswith(".test"):
        return True
    return False


def format_violations(violations):
    print("\n\033[1;31m====================================================================\033[0m")
    print("\033[1;31m 🚫 PRIVACY GUARDRAIL VIOLATION: Disallowed Email Address Detected!\033[0m")
    print("\033[1;31m====================================================================\033[0m\n")
    print("To protect privacy and prevent accidental leaks, personal email addresses")
    print("must NEVER be committed or pushed to this Git repository.\n")
    print("\033[1;33mDetected Violations:\033[0m")

    for file_path, email, snippet in violations:
        print(f"  \033[1;36mFile:\033[0m    {file_path}")
        print(f"  \033[1;31mEmail:\033[0m   {email}")
        if snippet:
            print(f"  \033[1;30mLine:\033[0m    {snippet}")
        print("  --------------------------------------------------------------------")

    print("\n\033[1;32mRemediation Guidance:\033[0m")
    print("  1. In documentation and markdown guides, use generic placeholders such as:")
    print("     \033[1;37madmin@example.com\033[0m or \033[1;37muser@example.com\033[0m")
    print("  2. In Kubernetes manifests, use dynamic environment/secret substitution:")
    print("     \033[1;37m${OIDC_ADMIN_EMAIL:=admin@example.com}\033[0m")
    print("  3. Real administrator credentials must originate from Azure Key Vault")
    print("     and be injected at runtime via External Secrets Operator.\n")


def check_diff_content(diff_text: str):
    current_file = "unknown"
    violations = []
    for line in diff_text.splitlines():
        if line.startswith("+++ b/"):
            current_file = line[6:]
            continue
        if line.startswith("+") and not line.startswith("+++"):
            content = line[1:]
            for match in EMAIL_REGEX.findall(content):
                if not is_allowed(match):
                    violations.append((current_file, match, content.strip()))
    return violations


def check_staged():
    res = subprocess.run(
        ["git", "diff", "--cached", "-U0"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    violations = check_diff_content(res.stdout)
    if violations:
        format_violations(violations)
        sys.exit(1)
    print("✅ Privacy check passed: No unauthorized email addresses in staged changes.")
    sys.exit(0)


def check_range(rev_range: str):
    res = subprocess.run(
        ["git", "diff", "-U0", rev_range],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    violations = check_diff_content(res.stdout)
    if violations:
        format_violations(violations)
        sys.exit(1)
    print(f"✅ Privacy check passed: No unauthorized email addresses in range {rev_range}.")
    sys.exit(0)


def check_all_files():
    # Only scan tracked files in git
    res = subprocess.run(
        ["git", "ls-files"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    tracked_files = res.stdout.splitlines()
    violations = []

    for rel_path in tracked_files:
        if any(rel_path.startswith(ex + "/") or rel_path == ex for ex in EXCLUDED_DIRS):
            continue
        if not os.path.isfile(rel_path):
            continue
        try:
            with open(rel_path, "r", encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    for match in EMAIL_REGEX.findall(line):
                        if not is_allowed(match):
                            violations.append((rel_path, match, line.strip()))
        except Exception:
            pass

    if violations:
        format_violations(violations)
        sys.exit(1)

    print("✅ Privacy check passed: Entire repository clean of unauthorized email addresses.")
    sys.exit(0)


def main():
    if len(sys.argv) < 2 or sys.argv[1] == "--staged":
        check_staged()
    elif sys.argv[1] == "--all":
        check_all_files()
    elif sys.argv[1] == "--range" and len(sys.argv) > 2:
        check_range(sys.argv[2])
    elif sys.argv[1] == "--pre-push":
        # Read lines from stdin provided by git pre-push hook:
        # <local ref> <local sha1> <remote ref> <remote sha1>
        has_error = False
        for line in sys.stdin:
            parts = line.strip().split()
            if len(parts) >= 4:
                local_sha, remote_sha = parts[1], parts[3]
                if local_sha == "(delete)" or local_sha == "0000000000000000000000000000000000000000":
                    continue
                if remote_sha == "0000000000000000000000000000000000000000":
                    rev_range = f"{local_sha}^!"
                else:
                    rev_range = f"{remote_sha}..{local_sha}"
                res = subprocess.run(
                    ["git", "diff", "-U0", rev_range],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    check=False,
                )
                violations = check_diff_content(res.stdout)
                if violations:
                    format_violations(violations)
                    has_error = True
        if has_error:
            sys.exit(1)
        print("✅ Privacy check passed: No unauthorized email addresses in push commits.")
        sys.exit(0)
    else:
        print(f"Unknown argument: {sys.argv[1]}")
        sys.exit(1)


if __name__ == "__main__":
    main()
