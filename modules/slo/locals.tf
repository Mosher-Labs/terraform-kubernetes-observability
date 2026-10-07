locals {
  # The three alert tiers from the SRE Workbook's multiwindow, multi-burn-rate
  # alerts. `budget` is the share of the error budget the tier may spend in its
  # long window; the burn-rate threshold follows from it.
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
      long       = "3d"
      long_hours = 72
      severity   = "warning"
      short      = "6h"
    }
  }

  rules = merge([
    for slo_id, slo in var.slos : {
      for tier in slo.tiers : "${slo_id}_burn_${tier}" => {
        # Both windows must be over the threshold, so the rule compares the
        # smaller of the two burn rates: the long window shows the problem is
        # real, the short one makes the alert clear soon after it stops.
        expr = format(
          "min(label_replace(%s, \"window\", \"long\", \"\", \"\") or label_replace(%s, \"window\", \"short\", \"\", \"\"))",
          "(${templatestring(slo.error_ratio, { window = local.tiers[tier].long })}) / ${local.budget[slo_id]}",
          "(${templatestring(slo.error_ratio, { window = local.tiers[tier].short })}) / ${local.budget[slo_id]}",
        )
        group          = slo.group
        operator       = "gt"
        pending_period = "0s"
        severity       = local.tiers[tier].severity
        subject        = "SLO: ${slo.title}"
        summary        = "${slo.title} is spending its error budget at ${local.burn_rate[slo_id][tier]}x the rate the ${format("%g", slo.target * 100)}% SLO allows, over the last ${local.tiers[tier].long} and ${local.tiers[tier].short}. At this rate the ${slo.window_days}-day budget is gone in ${format("%.1f", slo.window_days * 24 / local.burn_rate[slo_id][tier])} hours."
        threshold      = local.burn_rate[slo_id][tier]
        title          = "${slo.title}: ${tier} error budget burn"
      }
    }
  ]...)

  # The allowed error ratio, 1 minus the target, without float noise.
  budget = { for id, slo in var.slos : id => format("%.10g", 1 - slo.target) }

  # burn rate = budget share * window hours / long window hours
  burn_rate = {
    for id, slo in var.slos : id => {
      for name, tier in local.tiers : name => floor(tier.budget * slo.window_days * 24 / tier.long_hours * 100 + 0.5) / 100
    }
  }
}
