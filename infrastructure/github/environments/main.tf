# gh-worker-podman GitHub deployment environment as Terraform: the main-only Docker Hub push environment.
#
# Same pattern as blazing#1726 (blazing: infrastructure/github/environments) and Blazing-Back's
# `main-secrets` / `dockerhub-push`: Terraform declares the environment and its branch policy
# ONLY. It never holds, creates, reads or moves a secret value. Jonathan sets the value by hand
# after the apply.
#
# Why: the Docker Hub WRITE token (DOCKERHUB_TOKEN) is an ORGANIZATION secret visible to every
# repo, and this repo also has its own repository secrets of the same names. build.yaml pushed
# jobordu/gh-worker-podman with it on main pushes, the weekly schedule, `v*` tag pushes (a tag
# can point at any commit) and a workflow_dispatch from ANY branch. The token now lives here
# under a DISTINCT name, DOCKERHUB_PUSH_TOKEN, so the workflow can never fall back to the
# org or repository one. The build job enters this environment only on main's own push /
# schedule / workflow_dispatch; every other run builds without pushing or logging in
# (tests/test_dockerhub_push_token_is_main_only.py). The hole closes fully once the owner also
# deletes this repo's DOCKERHUB_TOKEN / DOCKERHUB_USERNAME repository secrets and restricts the
# org secret so this repo no longer receives it.
#
# No reviewers, by decision (same as blazing and Blazing-Back): the gate is the BRANCH, not a
# person. Admin bypass is off. "Protected branches" is false: deployment is limited to the one
# custom policy, "main".
#
# NEW, not adopted: the environment does not exist yet, so there is no import block. The first
# apply creates it with exactly these settings.
#
# APPLY PATH (owner): this repo has no apply workflow, and the Blazing-Back GitHub App used by
# github-environments-apply.yml is installed on Blazing-Back only. Applying this root needs
# either that App's installation widened to this repo plus an apply workflow, or a one-off owner
# apply. Jonathan's call.

terraform {
  required_version = ">= 1.7.0, < 2.0.0"

  # Same protected, versioned state bucket as every other root; an isolated prefix.
  backend "gcs" {
    bucket = "digitalfrontier-terraform-state"
    prefix = "github/environments-gh-worker-podman"
  }

  required_providers {
    github = {
      source  = "integrations/github"
      version = "6.13.0"
    }
  }
}

# Authentication comes from the GITHUB_TOKEN environment variable. No credential is an input
# variable, output or checked-in setting.
provider "github" {
  owner = "Borduas-Holdings"
}

locals {
  repository    = "gh-worker-podman"
  repository_id = 1187012128

  dockerhub_push_environment = "dockerhub-push"

  # Names only. Jonathan sets the value in the environment by hand after the apply
  # (GitHub UI or `gh secret set DOCKERHUB_PUSH_TOKEN --env dockerhub-push`).
  dockerhub_push_expected = toset([
    "DOCKERHUB_PUSH_TOKEN",
  ])
}

resource "github_repository_environment" "dockerhub_push" {
  repository          = local.repository
  environment         = local.dockerhub_push_environment
  can_admins_bypass   = false
  prevent_self_review = false
  wait_timer          = 0

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true # exactly one policy, branch "main" (below)
  }

  lifecycle {
    prevent_destroy = true

    postcondition {
      condition     = self.repository_id == local.repository_id
      error_message = "Environment must belong to the existing gh-worker-podman repository (id 1187012128)."
    }
  }
}

# dockerhub-push's only branch policy: only `main` may deploy into it.
resource "github_repository_environment_deployment_policy" "dockerhub_push_main" {
  repository     = local.repository
  environment    = github_repository_environment.dockerhub_push.environment
  branch_pattern = "main"

  lifecycle {
    prevent_destroy = true
  }
}

# Reports (never fails the plan) which expected secret NAMES are still missing from the
# environment. Reads names only; the provider's data source never returns values.
check "dockerhub_push_names_present" {
  data "github_actions_environment_secrets" "dockerhub_push" {
    name        = local.repository
    environment = github_repository_environment.dockerhub_push.environment
  }

  assert {
    condition = length(setsubtract(
      local.dockerhub_push_expected,
      toset([for s in data.github_actions_environment_secrets.dockerhub_push.secrets : s.name]),
    )) == 0
    error_message = "dockerhub-push is missing secret names (values are Jonathan's to set): ${join(", ", sort(setsubtract(local.dockerhub_push_expected, toset([for s in data.github_actions_environment_secrets.dockerhub_push.secrets : s.name]))))}"
  }
}
