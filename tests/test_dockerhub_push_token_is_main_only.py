"""The Docker Hub WRITE token reaches main's own image builds only, through a main-only environment.

Follow-up to blazing#1726 (SAVE B: the ORGANIZATION secret DOCKERHUB_TOKEN is visible to every
repo). build.yaml logged in with DOCKERHUB_TOKEN / DOCKERHUB_USERNAME on main pushes, the weekly
schedule, `v*` tag pushes (a tag can point at any commit) and a workflow_dispatch from ANY branch.
Now:

- the token lives in the `dockerhub-push` environment under a DISTINCT name,
  DOCKERHUB_PUSH_TOKEN, so nothing can fall back to the org or repository secret. The environment
  is declared in Terraform (infrastructure/github/environments/main.tf): no reviewers, exactly
  one branch policy (`main`), admin bypass off, no secret value in Terraform;
- the build job enters it only on main's own push / schedule / dispatch. Every other run gets ''
  (no environment, no token): no login, build without push;
- no workflow references any other DOCKERHUB_* secret.

What this file CANNOT enforce: a branch that edits a workflow can still name the org or
repository secret. That closes only when the owner deletes this repo's DOCKERHUB_TOKEN /
DOCKERHUB_USERNAME repository secrets and restricts the org secret so this repo no longer
receives it.

Run: python -m pytest tests (needs pytest and PyYAML); .github/workflows/guard.yaml runs it.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[1]
WORKFLOWS = REPO / ".github" / "workflows"
BUILD = WORKFLOWS / "build.yaml"
GUARD = WORKFLOWS / "guard.yaml"
TF_ROOT = REPO / "infrastructure" / "github" / "environments"

ENV = "dockerhub-push"
PUSH_SECRET = "DOCKERHUB_PUSH_TOKEN"
EXPECTED_ENV_EXPR = (
    "${{ (github.ref == 'refs/heads/main' && (github.event_name == 'push' || "
    "github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')) "
    "&& 'dockerhub-push' || '' }}"
)
_SECRET_REF = re.compile(r"secrets\.([A-Za-z0-9_]+)")


def _load(path: Path) -> dict:
    return yaml.safe_load(path.read_text()) or {}


def _triggers(doc: dict) -> dict:
    on = doc.get("on", doc.get(True))  # PyYAML reads `on:` as True
    return {on: None} if isinstance(on, str) else dict(on or {})


def _workflow_files() -> list[Path]:
    files = sorted(WORKFLOWS.glob("*.y*ml"))
    assert len(files) == 2, (
        f"expected build.yaml and guard.yaml, found {[p.name for p in files]}"
    )
    return files


def _build_job() -> dict:
    return _load(BUILD)["jobs"]["build"]


# ── the job enters the environment only on main's own runs ──────────────────────


def test_the_build_job_enters_the_environment_only_on_mains_own_runs() -> None:
    job = _build_job()
    assert job["environment"] == EXPECTED_ENV_EXPR
    assert job["env"]["PUSH_ENVIRONMENT"] == EXPECTED_ENV_EXPR


def test_the_expression_admits_main_and_no_pr_or_comment_driven_event() -> None:
    assert EXPECTED_ENV_EXPR.count("github.ref == 'refs/heads/main'") == 1
    admitted = set(re.findall(r"github\.event_name == '([a-z_]+)'", EXPECTED_ENV_EXPR))
    assert admitted == {"push", "schedule", "workflow_dispatch"}
    for event in (
        "pull_request",
        "pull_request_target",
        "workflow_run",
        "workflow_call",
        "issue_comment",
    ):
        assert f"'{event}'" not in EXPECTED_ENV_EXPR


def test_the_build_workflow_has_no_tag_or_pr_driven_trigger() -> None:
    """A `v*` tag can point at any commit; pull_request_target / workflow_run run with a main ref
    on behalf of PR input. None of them may reach the push job."""
    triggers = _triggers(_load(BUILD))
    assert set(triggers) == {"push", "schedule", "workflow_dispatch"}
    assert triggers["push"] == {"branches": ["main"]}


def test_only_the_build_job_enters_the_environment() -> None:
    entering = []
    for p in _workflow_files():
        for job_id, job in (_load(p).get("jobs") or {}).items():
            env = job.get("environment") if isinstance(job, dict) else None
            name = env.get("name") if isinstance(env, dict) else env
            if ENV in str(name or ""):
                entering.append(f"{p.name}::{job_id}")
    assert entering == [f"{BUILD.name}::build"]


# ── no other Docker Hub credential is read anywhere ─────────────────────────────


def test_the_only_secret_reference_is_the_gated_login() -> None:
    """Every `secrets.*` reference in every workflow, comments included, is the
    environment-only push token in the one gated login step."""
    refs = [
        (p.name, name)
        for p in _workflow_files()
        for name in _SECRET_REF.findall(p.read_text())
    ]
    assert len(refs) == 1, refs
    assert refs == [(BUILD.name, PUSH_SECRET)]
    steps = _build_job()["steps"]
    holders = [s for s in steps if "secrets." in json.dumps(s)]
    assert len(holders) == 1
    (login,) = holders
    assert login["name"] == "Log in to Docker Hub"
    assert login["if"] == "env.PUSH_ENVIRONMENT == 'dockerhub-push'"
    assert login["with"]["password"] == "${{ secrets.DOCKERHUB_PUSH_TOKEN }}"
    assert "secrets." not in str(login["with"]["username"]), (
        "the username must not be an (org) secret"
    )
    (build,) = [
        s
        for s in steps
        if str(s.get("uses", "")).startswith("docker/build-push-action@")
    ]
    assert build["with"]["push"] == "${{ env.PUSH_ENVIRONMENT == 'dockerhub-push' }}"
    names = [s.get("name") for s in steps]
    assert names.index("Log in to Docker Hub") < names.index(build["name"])


def test_the_guard_workflow_holds_no_credential() -> None:
    doc = _load(GUARD)
    assert set(_triggers(doc)) == {"pull_request", "push"}
    assert doc["permissions"] == {"contents": "read"}
    for job in doc["jobs"].values():
        assert "environment" not in job
    assert "secrets." not in GUARD.read_text()


# ── the environment in Terraform ────────────────────────────────────────────────


def _resource(text: str, kind: str, name: str) -> str:
    match = re.search(rf'^resource "{kind}" "{name}" \{{\n(.*?)^\}}', text, re.S | re.M)
    assert match, f"{kind}.{name} not found"
    return match.group(1)


def test_the_environment_is_main_only_reviewerless_and_holds_no_secret_value() -> None:
    """Mutations that must fail: protected branches, admin bypass on, a second or tag pattern,
    a reviewer, an import block (it is NEW), or a secret VALUE in Terraform."""
    tf_files = sorted(TF_ROOT.glob("*.tf"))
    assert [p.name for p in tf_files] == ["main.tf"]
    text = tf_files[0].read_text()
    assert re.search(r"^  repository_id = 1187012128$", text, re.M)
    assert re.search(r'^  dockerhub_push_environment = "dockerhub-push"$', text, re.M)
    assert (
        text.count('"dockerhub-push"') == 1
    )  # only the local; every resource goes through it
    env = _resource(text, "github_repository_environment", "dockerhub_push")
    assert "environment         = local.dockerhub_push_environment" in env
    assert re.search(r"^  can_admins_bypass   = false$", env, re.M)
    assert re.search(r"^    protected_branches     = false$", env, re.M)
    assert re.search(r"^    custom_branch_policies = true", env, re.M)
    assert "reviewers" not in env and "prevent_destroy = true" in env
    assert "self.repository_id == local.repository_id" in env
    policies = re.findall(
        r'^resource "github_repository_environment_deployment_policy" "([a-z_]+)"',
        text,
        re.M,
    )
    assert policies == ["dockerhub_push_main"]
    policy = _resource(
        text, "github_repository_environment_deployment_policy", "dockerhub_push_main"
    )
    assert re.findall(r'branch_pattern = "([^"]*)"', policy) == ["main"]
    assert "tag_pattern" not in policy
    assert "import {" not in text
    for forbidden in (
        'github_actions_environment_secret"',
        'github_actions_secret"',
        "plaintext_value",
        "encrypted_value",
    ):
        assert forbidden not in text, (
            f"{forbidden}: secret values are never Terraform's"
        )
    names = re.search(r"dockerhub_push_expected = toset\(\[(.*?)\]\)", text, re.S)
    assert names and re.findall(r'"([A-Z_]+)"', names[1]) == [PUSH_SECRET]
