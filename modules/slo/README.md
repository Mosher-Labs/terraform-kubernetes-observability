# modules/slo

Turns SLO definitions into burn-rate alerts for both backends, using the
multiwindow, multi-burn-rate alerts from the
[SRE Workbook](https://sre.google/workbook/alerting-on-slos/). It has no
providers and creates nothing. Its `custom_rules` output goes into
`modules/alerts` (Grafana), and its `datadog_slos` output goes into
`modules/datadog`.

## Use

```hcl
module "slo" {
  source = "github.com/Mosher-Labs/terraform-kubernetes-observability//modules/slo?ref=<commit-sha>"  # vX.Y.Z

  slos = {
    dns = {
      title  = "DNS replies"
      target = 0.999

      # Grafana: the fraction of bad events over $${window}, from 0 to 1, as
      # one series.
      grafana = {
        error_ratio = "sum(increase(dns_replies_failed_total[$${window}])) / sum(increase(dns_replies_total[$${window}]))"
      }
      # Datadog: the good events and all valid events.
      datadog = {
        good  = "sum:dns.replies{status:ok}.as_count()"
        total = "sum:dns.replies{*}.as_count()"
      }
    }
    sync = {
      title       = "Sync imports"
      target      = 0.99
      grafana     = { error_ratio = "1 - (sum(increase(imported_in_time_total[$${window}])) / sum(increase(valid_events_total[$${window}])))" }
      # Too quiet to page on: only the slow-burn ticket.
      tiers = ["slow"]
    }
  }
}

module "observability" {
  # ...
  alerts = { custom_rules = module.slo.custom_rules }
}

# Or, on Datadog:
module "datadog" {
  # ...
  slos = module.slo.datadog_slos
}
```

Each SLO needs a `grafana` block, a `datadog` block, or both. An SLO with one
block only creates alerts on that backend.

## Alerts

For a 30-day window and a 99.9% target, the allowed error ratio is 0.1%. Burn
rate is the actual error ratio divided by that. Each tier fires when both of
its windows are over the threshold. Both backends use the same tiers, which are
Datadog's recommended ones. Datadog's long window tops out at 48 hours, so the
slow tier is 3x over 1 day. That spends the same 10% of the budget as the SRE
Workbook's 1x over 3 days.

| Tier | Burn rate | Windows (long / short) | Budget spent in the long window | Severity |
| --- | --- | --- | --- | --- |
| `fast` | 14.4 | 1h / 5m | 2% | critical |
| `medium` | 6 | 6h / 30m | 5% | critical |
| `slow` | 3 | 1d / 2h | 10% | warning |

The thresholds come from the budget share, `share * window hours / long window
hours`, and `window_days` is 7, 30 or 90 (Datadog's choices).

- **Grafana:** the rule returns the smaller of the two burn rates, so a
  threshold override in `modules/alerts` still applies to both windows. A
  window with no data or NaN keeps the rule quiet.
- **Datadog:** `modules/datadog` creates a metric SLO and a `slo alert` monitor
  for each tier, and Datadog evaluates both windows itself.

## What each backend gets

| | Grafana | Datadog |
| --- | --- | --- |
| SLO definition | `slos` entry with a `grafana` block | the same entry, with a `datadog` block |
| Burn-rate alerts | `custom_rules` for `modules/alerts`, three tiers | `slo alert` monitors in `modules/datadog`, three tiers |
| Same thresholds, severities and text | yes | yes |
| SLO view with the error budget left | a dashboard row per SLO in `modules/dashboards` (SLI, budget left, burn rates). Grafana without the Cloud SLO app has no SLO object | the metric SLO, which Datadog shows with its budget |
| `overrides`: threshold, severity, paused | `modules/alerts` | `modules/datadog` |
| `disabled_rules` | yes | yes |

For the Grafana dashboard rows, pass `dashboard_slos` to `modules/dashboards`
(or to the root module as `dashboards.slos`):

```hcl
module "observability" {
  # ...
  alerts     = { custom_rules = module.slo.custom_rules }
  dashboards = { slos = module.slo.dashboard_slos }
}
```

The SLI and the budget left are computed over `window_days`, so Prometheus
needs that much data. Datadog keeps its metrics for 15 months. With a 14-day
Prometheus retention, a 30-day SLO shows the budget for the data it has, so
raise the retention to match the window.

## Writing the queries

- Define events at the input: valid events are everything the service is
  responsible for. Leave failed events in the count.
- Grafana `error_ratio` needs `$${window}` where the range goes, and must return
  a single series. Aggregate it with `sum()`. Several series would be collapsed
  into one.
- For a service that exposes gauges over a fixed window, such as Pi-hole's
  24-hour statistics, the share reacts too slowly for the short windows. Use a
  probe, such as `1 - avg_over_time(probe_success{...}[$${window}])`.
- If the SLI has no data, nothing fires. Keep an alert on the scrape target or
  the probe itself.
- A service with few events cannot use the fast tiers. At 12 events a month,
  one failure is an 8% error rate. A probe once a minute has the same problem
  at 99.9%: one failed probe in an hour is a burn rate of 16.7. Use
  `tiers = ["medium", "slow"]` or `["slow"]`.
- A counter `increase()` over 1d is cheap, but at larger scale consider a
  recording rule for the ratio.

Templates for the SLO document and the error budget policy are in
[docs/templates](../../docs/templates).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.15.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| slos | Your SLOs, keyed by an ID that becomes part of each rule ID. For each one:  - `title`: what the SLO covers, in a few words, such as "Pi-hole DNS replies". - `target`: the objective as a fraction, such as 0.999 for 99.9%. - `window_days`: the SLO window: 7, 30 or 90 (Datadog's choices). Default 30. - `tiers`: which burn-rate alerts to create, out of `fast` (14.4x over 1h and 5m, critical), `medium` (6x over 6h and 30m, critical) and `slow` (3x over 1d and 2h, warning). Default is all three. Use `["slow"]` for a service too quiet to page on. - `group`: the rule group. Default `slo`. - `grafana`: for the Grafana backend, `error_ratio`, a PromQL expression for the fraction of events that were bad over `${window}`, a value from 0 to 1. Write `${window}` where the range goes; it is filled in for each alert window. It must return a single series, so aggregate it with `sum()` or similar. - `datadog`: for the Datadog backend, `good` and `total`, the metric queries that count good events and all valid events (`sum:my.metric{...}.as_count()`).  Each SLO needs at least one backend block. The burn-rate thresholds come from the share of the error budget each tier may spend, so they stay correct for every window. | ```map(object({ datadog = optional(object({ good = string total = string })) grafana = optional(object({ error_ratio = string })) group = optional(string, "slo") target = number tiers = optional(list(string), ["fast", "medium", "slow"]) title = string window_days = optional(number, 30) }))``` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| burn\_rates | The burn-rate threshold of each tier for each SLO, for the SLO document. |
| custom\_rules | Burn-rate alert rules for the SLOs with a `grafana` block, in the shape `modules/alerts` takes as `custom_rules`, keyed `<slo>_burn_<tier>`. |
| dashboard\_slos | The SLOs with a `grafana` block, in the shape `modules/dashboards` takes as `slos`: the SLI, the error budget left, and the burn rates, as PromQL. |
| datadog\_slos | The SLOs with a `datadog` block, in the shape `modules/datadog` takes as `slos`. |
<!-- END_TF_DOCS -->
