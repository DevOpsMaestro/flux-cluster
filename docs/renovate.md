# Renovate — Dependency Automation

Configuration: `renovate.json` at repo root · Workflow: `.github/workflows/renovate.yaml` (daily schedule + `workflow_dispatch`)

---

## What Renovate does

Renovate scans the repository for version strings and opens pull requests when newer
versions are available. It tracks:

- **Flux HelmRelease version constraints** — `1.17.x`, `3.x`, etc. in `apps/` and
  `infrastructure/`
- **Direct container image tags** — images in Kubernetes manifests (BOINC, httpbin, etc.)
- **GitHub Actions** — version pins in `.github/workflows/`
- **CLI tool versions** — `versions.env` and workflow env vars for Cilium, Istio, Envoy
  Gateway, Kubernetes node image, Kyverno CLI, and Kubescape

---

## Automation tiers

| Tier | Matches | Schedule | Automerge |
|------|---------|----------|-----------|
| Container image patch | `matchManagers: kubernetes`, `matchUpdateTypes: patch` | Weekdays | Yes — after CI passes |
| Flux minor | `matchManagers: flux`, `matchUpdateTypes: minor` | Mondays | No — human review |
| GitHub Actions patch/minor | `matchManagers: github-actions` | Any | Yes — after CI passes |
| Infrastructure pins | `matchManagers: regex` (versions.env, CI tools) | Any | No — always human |
| Major updates (any) | Not grouped | Any | No — individual PRs |

Automerge is gated on GitHub branch protection: the `validate` workflow (kustomize build +
Kyverno tests + Kubescape scan) must pass. If CI is red, Renovate does not merge.

---

## Why certain packages are disabled

| Package | Reason |
|---------|--------|
| `boinc/client` | `arm64v8` is a Docker manifest architecture alias, not a version tag — there is no "newer" to detect |
| `kennethreitz/httpbin` | No versioned tags published; manifest pins the image by digest. Digest bumps produce noise with no upgrade signal |

---

## HelmRelease range constraints and Renovate

Most HelmReleases in this repo use semver range constraints like `1.17.x`. Flux resolves
the latest matching chart automatically — no human action required for patch bumps within
the range. Renovate does not create patch PRs for these because the range already covers
them.

Renovate only opens a PR when the constraint range itself needs changing:

- Minor bump: `1.17.x → 1.18.x` — goes into the weekly `flux-minor-updates` group PR
- Major bump: `1.x → 2.x` — individual PR, no automerge, human review

---

## Day-to-day operations

### Manual run

Trigger from the GitHub Actions UI: **Actions → Renovate → Run workflow → Run workflow**.

This executes the same job as the nightly scheduled run. Useful after changing
`renovate.json` to verify the new configuration immediately.

### View open Renovate PRs

```bash
gh pr list --label "renovate"
```

### Check the Dependency Dashboard

Renovate creates a **Dependency Dashboard** issue in the GitHub repo. It lists:
- All detected dependencies and their current/available versions
- Which PRs are open, pending, or rate-limited
- Error messages if a registry lookup failed

### Force a Renovate run via the dashboard

From the Dependency Dashboard issue, check the "Trigger dependency updates" checkbox.
On the next scheduled run (midnight UTC) Renovate will act on the checked items.
For an immediate run, use the **workflow_dispatch** trigger above instead.

---

## Rolling back an automerged PR

If an automerged update breaks the cluster:

```bash
# Find the merge commit
git log --oneline -10

# Revert it (new commit — safe for a shared branch)
git revert <merge-commit-sha>
git push origin main

# Reconcile Flux immediately
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization apps --with-source
```

---

## Disabling or snoozing an update

Add a `packageRules` entry to `renovate.json`:

```json
{
  "matchPackageNames": ["some/package"],
  "enabled": false
}
```

Or use the Dependency Dashboard issue — Renovate provides checkboxes to ignore specific
updates without editing config.
