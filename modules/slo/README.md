# modules/slo

Turns SLO definitions into burn-rate alert rules, using the multiwindow,
multi-burn-rate alerts from the
[SRE Workbook](https://sre.google/workbook/alerting-on-slos/). It has no
providers and creates nothing. Its `custom_rules` output goes straight into
`modules/alerts` (or the root module's `alerts.custom_rules`).

## Use

```hcl
module "slo" {
  source = "github.com/Mosher-Labs/terraform-kubernetes-observability//modules/slo?ref=<commit-sha>"  # vX.Y.Z

  slos = {
    dns = {
      title  = "DNS replies"
      target = 0.999
      # The fraction of bad events over $${window}, from 0 to 1.
      error_ratio = "sum(increase(dns_replies_failed_total[$${window}])) / sum(increase(dns_replies_total[$${window}]))"
    }
    sync = {
      title       = "Sync imports"
      target      = 0.99
      error_ratio = "1 - (sum(increase(imported_in_time_total[$${window}])) / sum(increase(valid_events_total[$${window}])))"
      # Too quiet to page on: only the slow-burn ticket.
      tiers = ["slow"]
    }
  }
}

module "observability" {
  # ...
  alerts = { custom_rules = module.slo.custom_rules }
}
```

## Alerts

For a 30-day window and a 99.9% target, the allowed error ratio is 0.1%. Burn
rate is the actual error ratio divided by that. Each tier fires when both of
its windows are over the threshold:

| Tier | Burn rate | Windows (long / short) | Budget spent in the long window | Severity |
| --- | --- | --- | --- | --- |
| `fast` | 14.4 | 1h / 5m | 2% | critical |
| `medium` | 6 | 6h / 30m | 5% | critical |
| `slow` | 1 | 3d / 6h | 10% | warning |

The thresholds come from the budget share, `share * window hours / long window
hours`, so they stay correct if you change `window_days`. The rule's expression
returns the smaller of the two burn rates, so a threshold override in
`modules/alerts` still applies to both windows.

## Writing `error_ratio`

- Use `$${window}` where the range goes. It is filled in for each alert window.
- Define events at the input: valid events are everything the service is
  responsible for. Leave failed events in the count.
- For a service that exposes gauges over a fixed window, such as Pi-hole's
  24-hour statistics, use `avg_over_time(...[$${window}])` on the ratio.
- A service with few events cannot use the fast tiers. At 12 events a month,
  one failure is an 8% error rate. Use `tiers = ["slow"]` and send a scheduled
  probe event through the real path.

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
| slos | Your SLOs, keyed by an ID that becomes part of each rule ID. For each one:  - `title`: what the SLO covers, in a few words, such as "Pi-hole DNS replies". - `target`: the objective as a fraction, such as 0.999 for 99.9%. - `error_ratio`: a PromQL expression for the fraction of events that were bad over `${window}`, a value from 0 to 1. Write `${window}` where the range goes; it is filled in for each alert window. - `window_days`: the SLO window. Default 30. - `tiers`: which burn-rate alerts to create, out of `fast` (14.4x over 1h and 5m, critical), `medium` (6x over 6h and 30m, critical) and `slow` (1x over 3d and 6h, warning). Default is all three. Use `["slow"]` for a service too quiet to page on. - `group`: the rule group. Default `slo`.  The burn-rate thresholds come from the share of the error budget each tier may spend, so they stay correct if you change `window_days`. | ```map(object({ error_ratio = string group = optional(string, "slo") target = number tiers = optional(list(string), ["fast", "medium", "slow"]) title = string window_days = optional(number, 30) }))``` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| burn\_rates | The burn-rate threshold of each tier for each SLO, for the SLO document. |
| custom\_rules | Burn-rate alert rules in the shape `modules/alerts` takes as `custom_rules`, keyed `<slo>_burn_<tier>`. |
<!-- END_TF_DOCS -->
