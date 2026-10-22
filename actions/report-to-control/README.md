# report-to-control

Tells **Control** ([control.junctionnet.nl/readiness](https://control.junctionnet.nl/readiness))
that a component was deployed, verified, migrated, provisioned or checked in an environment, so
the readiness grid shows what is actually running where.

It authenticates with the job's **GitHub OIDC token**, so there is no secret to store. Control
verifies the token against GitHub's keys and takes the repository, commit, run and actor from
the token itself; the request body adds only the environment, component, kind, status, version
and an optional `detail` object.

The action **never fails the job it runs in**. A missing permission, a refused report, an
unreachable Control or a bad input each become a `::warning::` annotation, and the step exits 0.
It needs `bash`, `curl` and `jq`, which GitHub-hosted Ubuntu runners already have.

## Usage

### As a step

Place it **after** the step that deployed, verified or migrated, with `if: always()` so a failed
run is reported too:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write # required: this is how the report authenticates
      contents: read
    steps:
      # … the deploy …

      - name: Report to Control
        if: always()
        continue-on-error: true
        uses: JNet-Platform-Foundry/.github/actions/report-to-control@v0.1.0
        with:
          environment: dev
          component: backend
          kind: deployed
          status: ${{ job.status }}
          version: ${{ github.sha }}
          detail: "{}"
```

### As its own job (reusable workflow)

When the deploy runs in another job, or in a workflow you would rather not touch:

```yaml
jobs:
  deploy:
    # …

  report:
    needs: deploy
    if: always()
    permissions: { id-token: write, contents: read }
    uses: JNet-Platform-Foundry/.github/.github/workflows/report-to-control.yml@v0.1.0
    with:
      environment: dev
      component: platform-infra
      kind: provisioned
      status: ${{ needs.deploy.result }}
```

The reusable workflow takes the same inputs as the action (all strings). Its one job runs on
`ubuntu-latest` with `continue-on-error: true` and `timeout-minutes: 3`, so a report can't hold
up or fail the calling workflow.

## Inputs

| input         | default                                               |                                                                                                               |
| ------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `environment` | —                                                     | Required. Lowercased; must then match `^[a-z0-9][a-z0-9._-]{0,62}$`. See [Environments](#environments).       |
| `component`   | —                                                     | Required. Lowercased; same pattern. See [Components](#components).                                            |
| `kind`        | —                                                     | Required. `deployed`, `verified`, `migrated`, `provisioned` or `checked`.                                     |
| `status`      | `success`                                             | Pass `${{ job.status }}` in a step, `${{ needs.<job>.result }}` in a job. See [Status](#status).              |
| `version`     |                                                       | Version or commit of what was deployed. Truncated to 64 characters; empty sends none.                         |
| `detail`      |                                                       | A JSON **object** string, at most 4096 bytes. Anything else is dropped with a warning; the report still goes. |
| `audience`    | `https://control.junctionnet.nl`                      | Audience of the OIDC token. Control accepts only its own; change it only to test against a fake.              |
| `endpoint`    | `https://control.junctionnet.nl/api/readiness/ingest` | Where to POST.                                                                                                |

Outputs (step form only): `result` — `posted`, `rejected`, `unreachable`, `skipped`, `invalid` or
`no-token` — and `http-code`, Control's HTTP status (`000` when nothing came back).

### Status

| `status` given                                          | Reported as                        |
| ------------------------------------------------------- | ---------------------------------- |
| `success`                                               | `success`                          |
| `skipped`, `cancelled`                                  | **nothing** — a notice, no request |
| anything else, including `failure` and an explicit `''` | `failure`                          |

Skipped and cancelled runs are not news: a superseded deploy must not paint a cell red.

### What Control answers

| HTTP | Meaning                                                                                              |
| ---- | ---------------------------------------------------------------------------------------------------- |
| 201  | Recorded.                                                                                            |
| 200  | Already recorded — same repository, run, attempt, environment, component and kind. Re-runs are safe. |
| 400  | The body was refused; Control's reason is printed in the log.                                        |
| 401  | The OIDC token was refused — usually the wrong `audience`.                                           |
| 403  | The repository is not on Control's allowlist (see below).                                            |

The step log prints the HTTP status and Control's answer, never the token, and the job summary
gets one line per report.

## Before a repository can report

1. **`permissions: id-token: write`** on the job (or on the calling job, for the reusable
   workflow). Without it there is no token: the step warns and sends nothing. Pull requests from
   forks never get one.
2. **The repository must be on Control's readiness allowlist** —
   `apps/control/lib/board-repos.js` in `junctionnet/developer-platform`, with `readiness: true`
   on its entry. Until it is, every report answers **403**. That is a change to Control, not to
   the caller.

## Naming

Control maps free-form names onto its grid, so pick names it recognises. Anything it can't place
is stored but not shown in a cell.

### Components

| Control column    | Report as                                                                                      |
| ----------------- | ---------------------------------------------------------------------------------------------- |
| **FE**            | `frontend` (also matched: `portal`, `web`, `ui`, `fe`, `amplify`, …)                           |
| **BE**            | `backend` or `api` (also matched: `service`, `lambda`, `worker`, `be`, …)                      |
| **Infra**         | `platform-infra` or `infra`, e.g. `frontend-infra`; any `kind: provisioned` or `kind: checked` |
| **DB Migrations** | `db-migrations`; any `kind: migrated`                                                          |

Order matters on Control's side: a migration is DB Migrations whatever it is called, and
`frontend-infra` is Infra, not FE.

### Environments

| Control row        | Report as                                       |
| ------------------ | ----------------------------------------------- |
| **DEV**            | `dev`, `development`                            |
| **Pre-Production** | `cloud`, `preprod`, `pre-production`, `staging` |
| **Production**     | `tech`, `prod`, `production`                    |

`cloud` and `tech` are JunctionNet's stage tokens; use whatever your pipeline already calls the
stage as long as it is one of these.

## Versioning

Callers pin a release tag: **`@v0.1.0`**. Changes land on `main` through a pull request, the
self-test workflow runs every path on a real runner, and the tag is cut on the merge commit.

**The reusable workflow hard-pins the action to the same tag.** A reusable workflow can't learn
which ref its caller pinned, and `uses: ./actions/report-to-control` would resolve against the
_caller's_ checkout, not this repository. So
`.github/workflows/report-to-control.yml` says
`uses: JNet-Platform-Foundry/.github/actions/report-to-control@v0.1.0`, and **every release
bumps that pin to the new tag in the release pull request, before the tag is cut**. Forgetting
it means the new workflow runs the previous release's action — harmless while the inputs are
unchanged, wrong once they aren't.

Tags can't be protected on this organization's plan, so anyone with write access can move one.
If you need an immutable reference, pin the full commit SHA instead.

## Development

```sh
shellcheck actions/report-to-control/report.sh
actionlint .github/workflows/report-to-control*.yml
```

`.github/workflows/report-to-control-selftest.yml` runs the action against the real Control
(this repository is not allowlisted, so it answers 401/403 and the step must still succeed),
against a local fake (`tests/fake_control.py`) to check the exact body sent, and in a job
without `id-token: write`.
