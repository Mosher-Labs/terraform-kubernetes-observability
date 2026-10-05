# Agent Instructions

Instructions for AI coding agents (Claude Code, Codex, Copilot, Cursor, and
others) working in this repository. Human contributors should read
[CONTRIBUTING.md](CONTRIBUTING.md); everything there applies to agents too.

## Project

A Terraform module that creates Kubernetes alerting in Grafana. The root module
wires together `modules/alerts` and `modules/notifications`. `modules/stack`
installs the monitoring stack with Helm and is called on its own, so the root
module never needs a Helm provider. The alert catalog lives in
`modules/catalog`, once for every backend: `modules/alerts` renders it as
Grafana rules and `modules/datadog` as Datadog monitors. Tests in `tests/` use
`terraform test` with a mocked Grafana provider.

## Rules

- **Only change the lines your task needs.** Do not reformat files or strip
  whitespace outside the change.
- **Run the checks before you finish:**

  ```bash
  pre-commit run --all-files
  terraform init -backend=false && terraform test
  terraform -chdir=modules/datadog init -backend=false && terraform -chdir=modules/datadog test
  ```

- **Test every behavior change** in `tests/`. Never point tests at a real
  Grafana.
- **Catalog changes:** edit `modules/catalog` only. Define each rule once, with
  a `grafana` and a `datadog` block, or `skip = "reason"` for a backend that
  can't express it. Keep the threshold out of the query (no data counts as
  healthy), use `__SEL__` for the workload selector on workload rules only, and
  update the catalog table in README.md and the rule counts in the tests. A
  backend block that replaces a shared field needs a comment saying why, and an
  entry in `tests/catalog.tftest.hcl`.
  Changing a rule ID is a breaking change, because callers reference IDs in
  `overrides` and `disabled_rules`.
- **Avoid cumulative-counter thresholds.** Alert on `increase()` or `rate()`
  over a window, so an alert resolves once the problem stops.
- **Alphabetize** variable and output blocks, and the attributes inside every
  block, object type and object value. Meta-arguments (`count`, `for_each`,
  `source`) come first, nested blocks after attributes, and `lifecycle` last.
  Catalog rules are alphabetical within each section. Keep `locals` in
  `locals.tf`.
- **Supported Terraform versions** are `required_version` (1.15) through the
  newest in the CI matrix. Raise the floor and the matrix together.
- **Pin GitHub Actions** and reusable workflows to a full commit SHA with the
  version in a trailing comment. Hook images use `tag@sha256:<digest>`.
- **Provider constraints** stay ranges with a major-version cap
  (`>= 4.0.0, < 5.0.0`). This is a module, so consumers pin exact versions.
- **Commit messages and PR titles** follow Conventional Commits (`fix:`,
  `feat:`, `test:`, `chore:`, `docs:`).
- Never commit tokens, webhook URLs or other secrets, including in examples and
  tests.
