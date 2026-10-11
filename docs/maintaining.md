# Maintaining this repository

For whoever changes the actions or the org defaults. For what the repository is and how to
call the actions, start with [README.md](README.md).

## Run the tests

Both actions are plain Python with no dependencies outside the standard library.

```sh
python3 -m unittest discover -s actions/job-summary/tests -v
python3 -m unittest discover -s actions/jira-comment/tests -v
```

Render a job summary locally against the fixtures:

```sh
JS_TITLE=Local JS_JUNIT='actions/job-summary/tests/fixtures/*.xml' \
  python3 actions/job-summary/summary.py
```

`actions/jira-comment/tests/fake_jira.py` is an in-memory Jira. Start it on a port and
point the action at `http://127.0.0.1:<port>`:

```sh
python3 actions/jira-comment/tests/fake_jira.py 8765            # with comment properties
python3 actions/jira-comment/tests/fake_jira.py 8766 --no-expand  # without, to test the fallback
```

## Self-test workflows

Each action has a workflow that runs on pull requests and pushes to `main` touching that
action, and on demand.

| Workflow                    | What it proves on a real runner                                                                                                                                                                    |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `job-summary-selftest.yml`  | Unit tests; renders tests, rows and links, a `needs` table, a plan log with a missing file, and Playwright errors; then asserts the `overall`, `passed` and `failed` outputs (11 passed, 3 failed) |
| `jira-comment-selftest.yml` | Unit tests; against two fake Jira servers, walks first run → edit → failure → recovery → milestone, the no-`expand` fallback, and an unreachable Jira that must only warn                          |

Both were green on the last merge to `main` (2026-10-10).

## Release

1. Merge the change to `main` through a pull request, with its self-test green.
2. Tag the merge commit and publish a release:

   ```sh
   git tag v0.2.0 <merge-commit>
   git push origin v0.2.0
   gh release create v0.2.0 --generate-notes
   ```

3. Update callers by pull request. Most pin `job-summary@v0.0.1`; see
   [README.md → Who uses them](README.md#who-uses-them-2026-10-11).

**Tags are immutable by convention.** Never move or delete a tag: a caller pinned to a tag
that disappears fails at _Set up job_, before any of its steps run. Tags cannot be
protected on this organization's plan, so the convention is the only guard. A caller that
needs a guarantee should pin the full commit SHA.

Released so far:

| Tag      | Date       | Contents                                     |
| -------- | ---------- | -------------------------------------------- |
| `v0.0.1` | 2026-10-03 | `job-summary`                                |
| `v0.1.0` | 2026-10-05 | adds `jira-comment`; `job-summary` unchanged |

## Repository settings

As of 2026-10-11: public; `main` has **no branch protection and no rulesets**; squash,
merge and rebase merges are all allowed; merged branches are not deleted automatically.
Issues are enabled.

## Known gaps

| Gap                                                                         | Effect                                                                                                                                         | Fix                                                                                                                                    |
| --------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| No branch protection on `main`                                              | Anyone with write access can push to `main` or move a tag that ~29 repositories depend on                                                      | Require a pull request and the two self-test checks on `main`                                                                          |
| The mirror wording in `SECURITY.md`, `ISSUE_TEMPLATE/` and `dependabot.yml` | Tells outside contributors their pull requests can't be merged and that fixes land "upstream", which is not how any org repository works today | Decide whether the mirror model is still the plan; if not, rewrite the three files                                                     |
| Dependabot defaults open no pull requests                                   | Correct for mirrors; for repositories developed here, security fixes need someone to act on the alert by hand                                  | Revisit together with the mirror wording                                                                                               |
| Callers pin `job-summary@v0.0.1`                                            | Fine today, since `job-summary` is unchanged in `v0.1.0`; the next change to it will need ~29 repositories updated                             | Bump callers when `job-summary` next changes, or adopt a moving major tag (and accept that it can be moved)                            |
| The org name still says _factory_                                           | The program is now called JNet Platform Foundry; every `uses:` line embeds `jnet-platform-factory`                                             | Renaming the org means updating ~142 `uses:` lines and re-registering the old name as a placeholder; see the Platform Foundry homepage |
