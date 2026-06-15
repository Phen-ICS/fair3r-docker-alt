#!/usr/bin/env python3
"""Run a ckanext pytest suite on a deployed CKAN VM via SSH.

Mirrors the pattern used by deploy/ansible_deploy.py: CI jobs pass secrets and
per-extension options as CLI flags; this script performs the remote work (resolve
the extension's packaged test.ini, install pytest deps, run pytest, fetch the
JUnit report).
"""

from __future__ import annotations

import argparse
import shlex
import subprocess
import sys

SSH_USER = "devics"
CKAN_PYTHON = "/usr/lib/ckan/default/bin/python3"
CKAN_PYTEST = "/usr/lib/ckan/default/bin/pytest"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run ckanext pytest on a remote CKAN host and fetch the JUnit report.",
    )
    parser.add_argument("--host", required=True, help="Target VM hostname.")
    parser.add_argument("--ckan-db-password", required=True)
    parser.add_argument("--ckan-datastore-db-password", required=True)
    parser.add_argument("--ckan-datastore-readonly-password", required=True)
    parser.add_argument(
        "--tests-module",
        required=True,
        help="Python module passed to pytest --pyargs (e.g. ckanext.fair3r.tests).",
    )
    parser.add_argument(
        "--remote-report",
        required=True,
        help="Absolute path on the remote host for pytest --junitxml.",
    )
    parser.add_argument(
        "--local-report",
        required=True,
        help="Local path where the JUnit XML is copied after the run.",
    )
    parser.add_argument(
        "--export-db-solr-env",
        default="None",
        help='Export CKAN_DB_HOST/PORT and CKAN_SOLR_URL before pytest. Ignored when "None".',
    )
    return parser


def _flag_enabled(value: str | None) -> bool:
    if value is None:
        return False
    return value.strip().lower() not in ("", "none")


def _remote_shell(args: argparse.Namespace) -> str:
    mod = args.tests_module
    lines = [
        "set -e",
        f'export CKAN_DB_HOST="127.0.0.1"',
        f'export CKAN_DB_PORT="5432"',
        f'export CKAN_DB_PASSWORD={shlex.quote(args.ckan_db_password)}',
        f'export CKAN_DATASTORE_DB_PASSWORD={shlex.quote(args.ckan_datastore_db_password)}',
        f'export CKAN_DATASTORE_READONLY_PASSWORD={shlex.quote(args.ckan_datastore_readonly_password)}',
    ]
    if _flag_enabled(args.export_db_solr_env):
        lines.extend(
            [
                'export CKAN_SOLR_URL="http://127.0.0.1:8983/solr/ckan"',
            ]
        )

    lines.extend(
        [
            "",
            "# deploy_integration has already force-reinstalled the extension from",
            "# the preview registry; use the test.ini shipped with that package.",
            f'TEST_INI=$({CKAN_PYTHON} -c "import os, {mod}; '
            f'print(os.path.join(os.path.dirname({mod}.__file__), \\"test.ini\\"))")',
        ]
    )
    
    lines.extend(
        [
            "",
            f"{CKAN_PYTEST} \\",
            '  --ckan-ini="$TEST_INI" \\',
            f"  --pyargs {args.tests_module} \\",
            f'  --junitxml={shlex.quote(args.remote_report)}',
        ]
    )
    return "\n".join(lines)


def main() -> int:
    args = build_parser().parse_args()
    remote_target = f"{SSH_USER}@{args.host}"
    remote_script = _remote_shell(args)

    pytest_rc = 0
    try:
        subprocess.run(
            ["ssh", remote_target, "bash", "-s"],
            input=remote_script,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        pytest_rc = exc.returncode or 1

    scp_cmd = [
        "scp",
        f"{remote_target}:{args.remote_report}",
        args.local_report,
    ]
    try:
        subprocess.run(scp_cmd, check=True)
    except subprocess.CalledProcessError:
        print(
            f"Warning: could not fetch {args.remote_report} from {args.host}",
            file=sys.stderr,
        )

    return pytest_rc


if __name__ == "__main__":
    sys.exit(main())
