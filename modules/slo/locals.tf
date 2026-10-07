locals {
  # The three alert tiers, with the windows and burn rates Datadog recommends
  # for a 30-day SLO. Datadog's long window tops out at 48 hours, so the slow
  # tier is 3x over 1 day, which spends the same 10% of the budget as the
  # SRE Workbook's 1x over 3 days. Grafana uses the same tiers, so the two
  # backends match. `budget` is the share of the error budget the tier may
  # spend in its long window; the burn rate follows from it.
  tiers = {
    fast = {
      budget     = 0.02
      long       = "1h"
      long_hours = 1
      severity   = "critical"
      short      = "5m"
    }
    medium = {
      budget     = 0.05
      long       = "6h"
      long_hours = 6
      severity   = "critical"
      short      = "30m"
    }
    slow = {
      budget     = 0.10
      long       = "1d"
      long_hours = 24
      severity   = "warning"
      short      = "2h"
    }
  }

  # The allowed error ratio, 1 minus the target, without float noise.
  budget = { for id, slo in var.slos : id => format("%.10g", 1 - slo.target) }

  # burn rate = budget share * window hours / long window hours
  burn_rate = {
    for id, slo in var.slos : id => {
      for name, tier in local.tiers : name => floor(tier.budget * slo.window_days * 24 / tier.long_hours * 100 + 0.5) / 100
    }
  }

  # Each SLO's burn rate for one window, as PromQL.
  burn = {
    for id, slo in var.slos : id => {
      for window in distinct(flatten([for t in local.tiers : [t.long, t.short]])) : window => "((${templatestring(slo.grafana.error_ratio, { window = window })}) / ${local.budget[id]})"
    } if slo.grafana != null
  }

  rules = merge([
    for slo_id, slo in var.slos : {
      for tier in slo.tiers : "${slo_id}_burn_${tier}" => {
        # Both windows must be over the threshold, so the rule compares the
        # smaller of the two burn rates: the long window shows the problem is
        # real, the short one makes the alert clear soon after it stops. min()
        # ignores a window with no data or NaN, so the `and` guard keeps the
        # rule quiet unless both windows have a value.
        expr = format(
          "min(label_replace(%s, \"window\", \"long\", \"\", \"\") or label_replace(%s, \"window\", \"short\", \"\", \"\")) and on() ((%s == %s) and on() (%s == %s))",
          local.burn[slo_id][local.tiers[tier].long],
          local.burn[slo_id][local.tiers[tier].short],
          local.burn[slo_id][local.tiers[tier].long],
          local.burn[slo_id][local.tiers[tier].long],
          local.burn[slo_id][local.tiers[tier].short],
          local.burn[slo_id][local.tiers[tier].short],
        )
        group          = slo.group
        operator       = "gt"
        pending_period = "0s"
        severity       = local.tiers[tier].severity
        subject        = "SLO: ${slo.title}"
        summary        = local.summaries[slo_id][tier]
        threshold      = local.burn_rate[slo_id][tier]
        title          = "${slo.title}: ${tier} error budget burn"
      }
    } if slo.grafana != null
  ]...)

  # The text both backends show when an alert fires.
  summaries = {
    for id, slo in var.slos : id => {
      for name, tier in local.tiers : name => "${slo.title} is spending its error budget at ${local.burn_rate[id][name]}x the rate the ${format("%g", slo.target * 100)}% SLO allows, over the last ${tier.long} and ${tier.short}. At this rate the ${slo.window_days}-day budget is gone in ${format("%g", slo.window_days * 24 / local.burn_rate[id][name])} hours."
    }
  }

  # What modules/datadog needs: the SLO, and each tier's burn-rate alert.
  datadog_slos = {
    for id, slo in var.slos : id => {
      denominator = slo.datadog.total
      group       = slo.group
      name        = slo.title
      numerator   = slo.datadog.good
      # Datadog takes the target as a percentage.
      target    = floor(slo.target * 1000000 + 0.5) / 10000
      timeframe = "${slo.window_days}d"
      tiers = {
        for tier in slo.tiers : tier => {
          burn_rate    = local.burn_rate[id][tier]
          long_window  = local.tiers[tier].long
          severity     = local.tiers[tier].severity
          short_window = local.tiers[tier].short
          summary      = local.summaries[id][tier]
        }
      }
    } if slo.datadog != null
  }
}
