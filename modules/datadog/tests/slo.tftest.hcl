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

run "overrides_apply_to_slo_monitors" {
  command = apply

  variables {
    overrides = {
      dns_burn_fast = { paused = true, severity = "warning", threshold = 10 }
    }
  }

  assert {
    condition     = datadog_monitor.slo["dns_burn_fast"].draft_status == "draft" && datadog_monitor.slo["dns_burn_fast"].priority == "3" && datadog_monitor.slo["dns_burn_fast"].monitor_thresholds[0].critical == "10" && endswith(datadog_monitor.slo["dns_burn_fast"].query, "> 10")
    error_message = "A paused, lowered or re-prioritised SLO rule should change its monitor, as it does on Grafana."
  }

  assert {
    condition     = datadog_monitor.slo["dns_burn_slow"].draft_status == "published" && endswith(datadog_monitor.slo["dns_burn_slow"].query, "> 3")
    error_message = "Rules without an override should not change."
  }
}

run "runbooks_add_a_line_to_the_message" {
  command = apply

  variables {
    runbooks = {
      base_url = "https://example.com/runbooks/"
      rule_ids = ["dns_burn_fast", "node_not_ready"]
    }
  }

  assert {
    condition     = strcontains(datadog_monitor.slo["dns_burn_fast"].message, "burning budget fast.\n\nRunbook: https://example.com/runbooks/dns_burn_fast.md\n\n@slack-homelab")
    error_message = "An SLO monitor with a runbook should have a Runbook line between the summary and the handles."
  }

  assert {
    condition     = strcontains(datadog_monitor.this["node_not_ready"].message, "Runbook: https://example.com/runbooks/node_not_ready.md") && !strcontains(datadog_monitor.this["pod_pending"].message, "Runbook:")
    error_message = "Only monitors with a runbook should get a Runbook line."
  }

  assert {
    condition     = !contains(output.rules_without_runbook, "dns_burn_fast") && !contains(output.rules_without_runbook, "dns_burn_slow") && contains(output.rules_without_runbook, "pod_crash_looping") == (datadog_monitor.this["pod_crash_looping"].priority == "1")
    error_message = "rules_without_runbook should list critical monitors with no link, and leave out warnings."
  }
}

run "runbooks_reject_unknown_rule_ids" {
  command = plan

  variables {
    runbooks = { urls = { no_such_rule = "https://example.com/x" } }
  }

  # Both monitor resources check the IDs.
  expect_failures = [datadog_monitor.slo, datadog_monitor.this]
}
