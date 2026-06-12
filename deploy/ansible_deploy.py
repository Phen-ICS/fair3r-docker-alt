#!/usr/bin/env python3
"""Wrapper around ansible-playbook that deploys Fair3R CKAN to a native VM.

Mirrors the pattern used by /opt/ics-standalone-app-template/deploy/ansible_deploy.py:

  * receives every secret / per-context value as a CLI flag,
  * prefixes context-specific values with ``<context>_`` when forwarding them
    to Ansible (so the same playbook can be reused for every deploy context),
  * installs the Galaxy collections listed in ansible/requirements.yml before
    running the playbook.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys


# Per-context secrets. Each one is forwarded to ansible-playbook as
# `-e <env>_<key>=<value>`, matching the ics-standalone-app-template pattern.
#
# Non-secret per-context values (site URL, contact mail, DOI publisher /
# test_mode / site_title) live in deploy/ansible/group_vars/<context>.yml
# and therefore don't appear here. Non-secret pipeline-level values
# (sysadmin name/email, fair3r_enable_fdf_integration) live in
# group_vars/all.yml and are not passed through the CLI either.
CONTEXT_SCOPED = (
    "ckan_session_secret",
    "ckan_secret_key",
    "ckan_app_instance_uuid",
    "ckan_db_password",
    "ckan_datastore_db_password",
    "ckan_datastore_readonly_password",
    "ckan_bootstrap_sysadmin_password",
    "fair3r_extension_pypi_token",
    "page_extension_pypi_token",
    "doi_extension_pypi_token",
    "plotly_extension_pypi_token",
    "doi_account_name",
    "doi_account_password",
    "doi_prefix",
)

# Plain (non-context-prefixed) pass-through flags. Mostly optional overrides
# for values that otherwise come from group_vars/all.yml.
PLAIN_PASSTHROUGH = (
    "ckan_deb_url",
    "ckan_email_smtp_password",
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Deploy Fair3R CKAN via Ansible (validation, integration, production).",
    )
    parser.add_argument(
        "--env",
        choices=["validation", "integration", "production"],
        required=True,
        help="Target environment; selects the matching inventory group and"
        " is used as the context prefix for per-context variables.",
    )
    parser.add_argument(
        "--host",
        default=None,
        help="Override target host (defaults to the single host in the env's"
        " inventory group).",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Pass --check --diff to ansible-playbook (dry-run).",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="count",
        default=0,
        help="Forward -v / -vv / -vvv to ansible-playbook.",
    )

    for name in CONTEXT_SCOPED + PLAIN_PASSTHROUGH:
        parser.add_argument(f"--{name.replace('_', '-')}", dest=name, default=None)

    return parser


def main() -> int:
    args = build_parser().parse_args()

    os.chdir(os.path.dirname(os.path.abspath(__file__)))

    # Install Galaxy collections first. Non-fatal if already installed.
    try:
        subprocess.check_call(
            ["ansible-galaxy", "collection", "install", "-r", "ansible/requirements.yml"]
        )
    except subprocess.CalledProcessError as exc:
        print(f"Error installing Ansible collections: {exc}", file=sys.stderr)
        return 1

    target_host = args.host or args.env

    # Note: fair3r_context (e.g. VALIDATION/INTEGRATION/PRODUCTION) is derived
    # inside the playbook via `{{ context | upper }}`, so it is not forwarded
    # here.
    cmd = [
        "ansible-playbook",
        "-i",
        "ansible/inventory.ini",
        "ansible/fair3r_deploy.yml",
        "-e",
        f"context={args.env}",
        "-e",
        f"target_host={target_host}",
    ]

    if args.check:
        cmd.extend(["--check", "--diff"])
    if args.verbose:
        cmd.append("-" + "v" * min(args.verbose, 4))

    for name in CONTEXT_SCOPED:
        value = getattr(args, name)
        if value is not None:
            cmd.extend(["-e", f"{args.env}_{name}={value}"])

    for name in PLAIN_PASSTHROUGH:
        value = getattr(args, name)
        if value is not None:
            cmd.extend(["-e", f"{name}={value}"])

    try:
        subprocess.check_call(cmd)
    except subprocess.CalledProcessError as exc:
        print(f"ansible-playbook failed: {exc}", file=sys.stderr)
        return exc.returncode or 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
