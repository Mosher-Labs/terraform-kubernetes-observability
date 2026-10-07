# Run from modules/datadog: terraform init -backend=false && terraform test.
# SLOs from modules/slo become a metric SLO and a burn-rate monitor per tier.
# These runs apply against the mock provider: the monitor query holds the SLO ID,
# which is only known after apply.
mock_provider "datadog" {}

variables {
  cluster_name         = "homelab"
  notification_handles = ["@slack-homelab"]
  slos = {
    dns = {
      denominator = "sum:dns.replies{*}.as_count()"
      group       = "slo"
      name        = "DNS replies"
      numerator   = "sum:dns.replies{status:ok}.as_count()"
      target      = 99.9
      timeframe   = "30d"
      tiers = {
        fast = {
          burn_rate    = 14.4
          long_window  = "1h"
          severity     = "critical"
          short_window = "5m"
          summary      = "DNS replies is burning budget fast."
        }
        slow = {
          burn_rate    = 3
          long_window  = "1d"
          severity     = "warning"
          short_window = "2h"
          summary      = "DNS replies is burning budget slowly."
        }
      }
    }
  }
}

run "slo_and_burn_rate_monitors" {
  command = apply

  assert {
    condition     = datadog_service_level_objective.this["dns"].type == "metric" && datadog_service_level_objective.this["dns"].thresholds[0].target == 99.9 && datadog_service_level_objective.this["dns"].thresholds[0].timeframe == "30d"
    error_message = "The SLO should be a 99.9% metric SLO over 30d."
  }

  assert {
    condition     = length(datadog_monitor.slo) == 2 && datadog_monitor.slo["dns_burn_fast"].type == "slo alert"
    error_message = "Expected a slo alert monitor for each tier."
  }

  assert {
    condition     = endswith(datadog_monitor.slo["dns_burn_fast"].query, ".over(\"30d\").long_window(\"1h\").short_window(\"5m\") > 14.4") && startswith(datadog_monitor.slo["dns_burn_fast"].query, "burn_rate(\"")
    error_message = "The fast monitor should alert on a burn rate over 14.4 across 1h and 5m."
  }

  assert {
    condition     = datadog_monitor.slo["dns_burn_fast"].monitor_thresholds[0].critical == "14.4" && datadog_monitor.slo["dns_burn_fast"].priority == "1" && datadog_monitor.slo["dns_burn_slow"].priority == "3"
    error_message = "The threshold should match the query, critical is priority 1 and warning is priority 3."
  }

  assert {
    condition     = endswith(datadog_monitor.slo["dns_burn_fast"].message, "@slack-homelab") && strcontains(datadog_monitor.slo["dns_burn_fast"].message, "burning budget fast")
    error_message = "The monitor should carry the summary and notify the handles."
  }
}

run "disabled_rules_skips_a_tier" {
  command = apply

  variables {
    disabled_rules = ["dns_burn_slow"]
  }

  assert {
    condition     = keys(datadog_monitor.slo) == ["dns_burn_fast"]
    error_message = "A disabled SLO rule should have no monitor."
  }
}
