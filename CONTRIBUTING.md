# Contributing

Thanks for helping. Issues and pull requests are welcome.

## Setup

You need Terraform 1.5 or later (CI uses 1.16), Docker (for the pinned hook
images), and [pre-commit](https://pre-commit.com).

```bash
pre-commit install
terraform init -backend=false
```

## Before you open a pull request

```bash
pre-commit run --all-files
terraform test
```

`pre-commit` formats Terraform, runs tflint, regenerates the input and output
tables in the READMEs, and lints YAML, Markdown and workflows. The tests mock
the Grafana provider, so they run without Grafana or credentials.

## Adding or changing an alert

1. Edit `modules/alerts/catalog.tf`. Write the query to return the value to
   compare, one series per thing being alerted on, and put the threshold in
   `threshold`, not in the PromQL. A query that returns nothing counts as
   healthy.
2. Workload rules take the namespace selector through the `__SEL__`
   placeholder. Node and control-plane rules don't.
3. Prefer `increase()` or `rate()` over a window to raw counters, so the alert
   resolves when the problem stops.
4. Update the catalog table in README.md and the rule counts in
   `tests/alerts.tftest.hcl`.

Rule IDs are part of the module's interface: callers use them in `overrides`
and `disabled_rules`. Renaming or removing one is a breaking change.

## Commits and pull requests

Commit messages and PR titles follow
[Conventional Commits](https://www.conventionalcommits.org/). Releases are cut
automatically from them: `fix:` makes a patch release, `feat:` a minor one, and
`!` or `BREAKING CHANGE:` a major one.

Keep each pull request to one change, and only touch the lines it needs.
