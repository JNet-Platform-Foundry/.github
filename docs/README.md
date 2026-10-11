# jnet-platform-factory/.github

The organization-level repository for **JNet Platform Foundry**. It does two jobs:

1. **Org defaults.** GitHub reads a repository named `.github` as the fallback for every
   other repository in the organization: its security policy, issue templates and
   Dependabot settings apply wherever a repository has none of its own, and
   `profile/README.md` is the page shown at <https://github.com/jnet-platform-factory>.
2. **Shared CI building blocks.** Two composite actions, called from workflows across the
   JunctionNet, CargoNaut, WSI, Puerto VIA and Triumph organizations:
   - [`job-summary`](../actions/job-summary) — one consistent result summary per job.
   - [`jira-comment`](../actions/jira-comment) — one living CI/CD comment per Jira ticket.

This page is the map. Each action's own README is the reference for its inputs and
behaviour; [maintaining.md](maintaining.md) covers tests, releases and repository settings.

## Layout

```text
.github/
├── profile/README.md               # org page on github.com/jnet-platform-factory
├── SECURITY.md                     # default security policy for every repo
├── LICENSE                         # Apache-2.0
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml          # default bug form
│   │   └── config.yml              # links to SECURITY.md; blank issues allowed
│   ├── dependabot.yml              # default: security alerts only, no version-bump PRs
│   └── workflows/
│       ├── job-summary-selftest.yml
│       └── jira-comment-selftest.yml
├── actions/
│   ├── job-summary/                # action.yml + summary.py + tests/ (fixtures)
│   └── jira-comment/               # action.yml + jira_comment.py + tests/ (fake Jira)
└── docs/                           # this documentation
```

The `.github/` folder inside the repository holds the **defaults** (and this repo's own
self-test workflows). The `actions/` folder holds what other repositories **call**.

## The actions

Both actions share one design:

- **A composite action around one Python script.** They need only `python3` and `bash`,
  which every GitHub-hosted Ubuntu and macOS runner has. No `pip install`, no Docker.
- **They never fail the job they run in.** Any error becomes a `::warning::` annotation
  and the step exits 0. Callers still add `continue-on-error: true` as a second guard.
- **Inputs reach the script as environment variables**, never interpolated into the
  shell, so an input value cannot inject a command.
- **No secrets in output.** Job summaries are readable by anyone who can read the
  repository, so `job-summary` redacts AWS account IDs, ARNs and bearer/token values from
  what it renders and lists Terraform resource addresses without their attribute diffs.

| Action                                              | What it gives you                                                                                                                                                                                                | Typical step                                                    |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| [`job-summary`](../actions/job-summary/README.md)   | A headline (✅ ❌ 🚫 ⏭️), a key/value table, per-job results from `needs`, JUnit and Playwright counts with each failing test's error, and Terraform/Terragrunt plan and apply counts with every resource change | Last step of a job, or a final job that summarizes the pipeline |
| [`jira-comment`](../actions/jira-comment/README.md) | One comment per issue × repository × app × environment, edited in place on green runs; a new comment on the first run, on failure, on recovery and for milestones (production, releases)                         | After a deploy, with the ticket key from the branch name        |

### Calling them

Pin a released tag. The current release is **`v0.1.0`**; `main` is identical to it.

```yaml
- name: Summary
  if: always()
  continue-on-error: true
  uses: jnet-platform-factory/.github/actions/job-summary@v0.1.0
  with:
    title: Deploy — ${{ inputs.stage }}
    status: ${{ job.status }}
    rows: |
      Stage: ${{ inputs.stage }}
      URL: ${{ steps.deploy.outputs.url }}
    junit: reports/junit-*.xml
```

```yaml
- name: Jira
  if: always()
  continue-on-error: true
  uses: jnet-platform-factory/.github/actions/jira-comment@v0.1.0
  with:
    issue-keys: ${{ needs.configure.outputs.issue_key }}
    jira-url: ${{ vars.JIRA_URL }}
    jira-email: ${{ vars.JIRA_API_TOKEN_EMAIL }}
    jira-token: ${{ secrets.JIRA_API_TOKEN }}
    environment: DEV
    status: ${{ needs.deploy.result == 'success' && 'success' || 'failure' }}
    url: ${{ needs.deploy.outputs.url }}
```

`jira-comment` needs a Jira API token whose account can _Add comments_ and _Edit own
comments_ on the project (plus _Transition issues_ if you use `transition-to`).

### Who uses them (2026-10-11)

| Action         | Pinned version                                            | Where                                                                                                                                                                                                                                                                                                     |
| -------------- | --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `job-summary`  | `v0.0.1` — 137 `uses:` lines across about 29 repositories | Every tenant platform repo (`platform-infrastructure`, `wsi-platform`, `cargonaut-platform`, `jnet-via-platform`, `triumph-platform`), the JunctionNet API and portal repos and their blueprints, the reusable workflows in `junctionnet/.github`, Puerto VIA's backend and frontend, WSI's documents API |
| `jira-comment` | `v0.1.0`                                                  | The `jira-comment` and `jira-deploy-comment` actions in `junctionnet/.github`, which service workflows reach indirectly                                                                                                                                                                                   |

`job-summary` did not change between `v0.0.1` and `v0.1.0` (`v0.1.0` only added
`jira-comment`), so callers on `v0.0.1` are not behind.

## Org defaults

GitHub applies these to any repository in the organization that does not have its own
copy. A repository's own file always wins.

| File                                    | Effect                                                                                                                                            |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SECURITY.md`                           | Shown under **Security → Policy**. Asks for private vulnerability reports and promises acknowledgement within five working days.                  |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | The default bug form: version, expected vs actual, reproduction, and a required checkbox confirming account IDs, ARNs and hostnames were removed. |
| `.github/ISSUE_TEMPLATE/config.yml`     | Adds "Security issue" and "Why can't I open a pull request?" links to the new-issue page.                                                         |
| `.github/dependabot.yml`                | Weekly checks for GitHub Actions, pip and Terraform with `open-pull-requests-limit: 0` — security **alerts**, never version-bump pull requests.   |
| `profile/README.md`                     | The org page: the three layers of a platform (account, platform, service) and where each starts.                                                  |

> **These defaults assume a mirror model that is not in use.** `SECURITY.md`, the issue
> templates and the Dependabot comment all say the org's repositories are generated
> mirrors of a private source and cannot take pull requests. Today every repository in the
> org is developed directly, and the mirror pipeline in
> `junctionnet/platform-infrastructure/publish` publishes nothing. See
> [maintaining.md → Known gaps](maintaining.md#known-gaps).

## Related

- Confluence: [jnet-platform-factory/.github — org defaults and CI actions](https://cargonaut-team.atlassian.net/wiki/spaces/PLAT/pages/1287847942)
  in the Platform Foundry space.
- Jira: [JNET-2998](https://cargonaut-team.atlassian.net/browse/JNET-2998) (job-summary),
  [JNET-3004](https://cargonaut-team.atlassian.net/browse/JNET-3004) (jira-comment),
  [CRGN-274](https://cargonaut-team.atlassian.net/browse/CRGN-274) (CargoNaut adoption).
