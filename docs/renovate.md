# Renovate — Dependency Automation

Configuration: `renovate.json` at repository root · Workflow: `.github/workflows/renovate.yaml` (daily schedule + `workflow_dispatch`)

---

## What Renovate Does

Renovate scans the repository for version strings and opens pull requests when newer versions are available. It tracks:

- **Flux HelmRelease version constraints** — `1.17.x`, `3.x`, etc. in `apps/` and `infrastructure/`
- **Direct container image tags** — images in Kubernetes manifests (BOINC, httpbin, etc.)
- **GitHub Actions** — version pins in `.github/workflows/`
- **CLI tool versions** — `versions.env` and workflow environment variables for Cilium, Istio, Envoy Gateway, Kubernetes node image, Kyverno CLI, and Kubescape

---

## Automation Tiers

| Tier | Matches | Schedule | Automerge |
|------|---------|----------|-----------|
| Container image patch | `matchManagers: kubernetes`, `matchUpdateTypes: patch` | Weekdays | Yes — after CI passes |
| Flux minor | `matchManagers: flux`, `matchUpdateTypes: minor` | Mondays | No — human review |
| GitHub Actions patch/minor | `matchManagers: github-actions` | Any | Yes — after CI passes |
| Infrastructure pins | `matchManagers: regex` (versions.env, CI tools) | Any | No — always human |
| Major updates (any) | Not grouped | Any | No — individual PRs |

Automerge is gated on GitHub branch protection: the `validate` workflow (kustomize build + Kyverno tests + Kubescape scan) must pass. If CI fails, Renovate does not merge.

---

## Why Certain Packages Are Disabled

| Package | Reason |
|---------|--------|
| `boinc/client` | `arm64v8` is a Docker manifest architecture alias, not a version tag — there is no newer version to detect |
| `kennethreitz/httpbin` | No versioned tags are published; the manifest pins the image by digest. Digest bumps produce noise with no upgrade signal |

---

## HelmRelease Range Constraints and Renovate

Most HelmReleases in this repository use semver range constraints such as `1.17.x`. Flux resolves the latest matching chart automatically — no manual action is required for patch bumps within the range. Renovate does not create patch PRs for these because the range already covers them.

Renovate opens a PR only when the constraint range itself must change:

- Minor bump: `1.17.x → 1.18.x` — goes into the weekly `flux-minor-updates` group PR
- Major bump: `1.x → 2.x` — individual PR, no automerge, human review required

---

## Day-to-Day Operations

### Manual Run

Trigger from the GitHub Actions interface: **Actions → Renovate → Run workflow → Run workflow**.

This executes the same job as the nightly scheduled run. Use this after changing `renovate.json` to verify the new configuration immediately without waiting for the next scheduled run.

### View Open Renovate PRs

```bash
gh pr list --label "renovate"
```

### Check the Dependency Dashboard

Renovate creates a **Dependency Dashboard** issue in the GitHub repository. It lists:
- All detected dependencies and their current and available versions
- Which PRs are open, pending, or rate-limited
- Error messages if a registry lookup failed

### Force a Renovate Run via the Dashboard

From the Dependency Dashboard issue, check the "Trigger dependency updates" checkbox. On the next scheduled run (midnight UTC) Renovate will act on the checked items. For an immediate run, use the `workflow_dispatch` trigger above instead.

---

## Rolling Back an Automerged PR

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

## Disabling or Snoozing an Update

Add a `packageRules` entry to `renovate.json`:

```json
{
  "matchPackageNames": ["some/package"],
  "enabled": false
}
```

Alternatively, use the Dependency Dashboard issue — Renovate provides checkboxes to suppress specific updates without editing configuration.
