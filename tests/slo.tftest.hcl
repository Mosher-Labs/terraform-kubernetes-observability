# modules/slo turns SLO definitions into burn-rate alerts for both backends.
# It has no providers, so these runs only plan.
variables {
  slos = {
    dns = {
      datadog = {
        good  = "sum:dns.replies{status:ok}.as_count()"
        total = "sum:dns.replies{*}.as_count()"
      }
      grafana = {
        error_ratio = "sum(increase(bad[$${window}])) / sum(increase(total[$${window}]))"
      }
      target = 0.999
      title  = "DNS replies"
    }
  }
}

run "three_tiers_with_the_same_thresholds_on_both_backends" {
  command = plan

  module {
    source = "./modules/slo"
  }

  assert {
    condition     = length(output.custom_rules) == 3 && length(output.datadog_slos["dns"].tiers) == 3
    error_message = "Expected a fast, medium and slow alert on each backend."
  }

  assert {
    condition     = output.custom_rules["dns_burn_fast"].threshold == 14.4 && output.custom_rules["dns_burn_medium"].threshold == 6 && output.custom_rules["dns_burn_slow"].threshold == 3
    error_message = "Thresholds should be 14.4, 6 and 3 for a 30-day window."
  }

  assert {
    condition     = alltrue([for t in ["fast", "medium", "slow"] : output.datadog_slos["dns"].tiers[t].burn_rate == output.custom_rules["dns_burn_${t}"].threshold && output.datadog_slos["dns"].tiers[t].severity == output.custom_rules["dns_burn_${t}"].severity && output.datadog_slos["dns"].tiers[t].summary == output.custom_rules["dns_burn_${t}"].summary])
    error_message = "Both backends must use the same burn rates, severities and text."
  }

  assert {
    condition     = output.custom_rules["dns_burn_fast"].severity == "critical" && output.custom_rules["dns_burn_slow"].severity == "warning"
    error_message = "Fast burns page, the slow burn opens a ticket."
  }

  assert {
    condition     = output.datadog_slos["dns"].tiers["slow"].long_window == "1d" && output.datadog_slos["dns"].tiers["slow"].short_window == "2h"
    error_message = "The slow tier is 1d and 2h, inside Datadog's 48 hour limit."
  }
}

run "grafana_expression_needs_both_windows" {
  command = plan

  module {
    source = "./modules/slo"
  }

  variables {
    slos = {
      dns = {
        grafana = {
          error_ratio = "1 - avg_over_time(up[$${window}])"
        }
        target = 0.999
        title  = "DNS replies"
        tiers  = ["fast"]
      }
    }
  }

  assert {
    condition     = output.custom_rules["dns_burn_fast"].expr == "min(label_replace(((1 - avg_over_time(up[1h])) / 0.001), \"window\", \"long\", \"\", \"\") or label_replace(((1 - avg_over_time(up[5m])) / 0.001), \"window\", \"short\", \"\", \"\")) and on() ((((1 - avg_over_time(up[1h])) / 0.001) == ((1 - avg_over_time(up[1h])) / 0.001)) and on() (((1 - avg_over_time(up[5m])) / 0.001) == ((1 - avg_over_time(up[5m])) / 0.001)))"
    error_message = "The fast rule should compare the smaller of the 1h and 5m burn rates, and only when both have a value."
  }
}

run "datadog_gets_a_percentage_target_and_the_queries" {
  command = plan

  module {
    source = "./modules/slo"
  }

  assert {
    condition     = output.datadog_slos["dns"].target == 99.9 && output.datadog_slos["dns"].timeframe == "30d"
    error_message = "A 0.999 target is 99.9 over 30d."
  }

  assert {
    condition     = output.datadog_slos["dns"].numerator == "sum:dns.replies{status:ok}.as_count()" && output.datadog_slos["dns"].denominator == "sum:dns.replies{*}.as_count()"
    error_message = "The good and total queries should pass through."
  }
}

run "an_slo_with_one_backend_only_renders_for_that_backend" {
  command = plan

  module {
    source = "./modules/slo"
  }

  variables {
    slos = {
      dns = {
        grafana = {
          error_ratio = "1 - avg_over_time(up[$${window}])"
        }
        target = 0.999
        title  = "DNS replies"
      }
      sync = {
        datadog = {
          good  = "sum:sync.ok{*}.as_count()"
          total = "sum:sync.all{*}.as_count()"
        }
        target = 0.99
        title  = "Sync imports"
      }
    }
  }

  assert {
    condition     = length(output.custom_rules) == 3 && !contains(keys(output.custom_rules), "sync_burn_fast") && keys(output.datadog_slos) == ["sync"]
    error_message = "dns is Grafana only, sync is Datadog only."
  }
}

run "window_days_scales_the_thresholds" {
  command = plan

  module {
    source = "./modules/slo"
  }

  variables {
    slos = {
      dns = {
        grafana = {
          error_ratio = "1 - avg_over_time(up[$${window}])"
        }
        target      = 0.99
        title       = "DNS replies"
        window_days = 7
      }
    }
  }

  assert {
    condition     = output.burn_rates["dns"]["fast"] == 3.36 && output.custom_rules["dns_burn_fast"].threshold == 3.36
    error_message = "For a 7-day window the fast burn is 0.02 * 7 * 24 / 1 = 3.36."
  }

  assert {
    condition     = strcontains(output.custom_rules["dns_burn_fast"].expr, "/ 0.01)")
    error_message = "A 99% target has a 1% budget."
  }
}

run "tiers_can_be_limited_for_quiet_services" {
  command = plan

  module {
    source = "./modules/slo"
  }

  variables {
    slos = {
      sync = {
        grafana = {
          error_ratio = "1 - (sum(increase(good[$${window}])) / sum(increase(total[$${window}])))"
        }
        target = 0.99
        tiers  = ["slow"]
        title  = "Sync imports"
      }
    }
  }

  assert {
    condition     = keys(output.custom_rules) == ["sync_burn_slow"]
    error_message = "Only the slow tier should be created."
  }
}

run "rejects_a_target_of_one_hundred_percent" {
  command = plan

  module {
    source = "./modules/slo"
  }

  variables {
    slos = {
      dns = {
        grafana = { error_ratio = "1 - avg_over_time(up[$${window}])" }
        target  = 1
        title   = "DNS replies"
      }
    }
  }

  expect_failures = [var.slos]
}

run "rejects_an_error_ratio_without_a_window" {
  command = plan

  module {
    source = "./modules/slo"
  }

  variables {
    slos = {
      dns = {
        grafana = { error_ratio = "sum(bad) / sum(total)" }
        target  = 0.999
        title   = "DNS replies"
      }
    }
  }

  expect_failures = [var.slos]
}

run "rejects_a_window_datadog_cannot_use" {
  command = plan

  module {
    source = "./modules/slo"
  }

  variables {
    slos = {
      dns = {
        grafana     = { error_ratio = "1 - avg_over_time(up[$${window}])" }
        target      = 0.999
        title       = "DNS replies"
        window_days = 28
      }
    }
  }

  expect_failures = [var.slos]
}

run "rejects_an_slo_with_no_backend" {
  command = plan

  module {
    source = "./modules/slo"
  }

  variables {
    slos = {
      dns = {
        target = 0.999
        title  = "DNS replies"
      }
    }
  }

  expect_failures = [var.slos]
}

run "alerts_module_creates_the_rendered_rules" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name              = "t"
    prometheus_datasource_uid = "prometheus"
    custom_rules              = run.three_tiers_with_the_same_thresholds_on_both_backends.custom_rules
  }

  assert {
    condition     = contains(output.rule_ids, "dns_burn_fast") && contains(output.rule_ids, "dns_burn_medium") && contains(output.rule_ids, "dns_burn_slow")
    error_message = "modules/alerts should create the three burn-rate rules."
  }
}

run "alerts_module_rejects_an_slo_id_that_reuses_a_catalog_id" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name              = "t"
    prometheus_datasource_uid = "prometheus"
    custom_rules              = { pod_crash_looping = run.three_tiers_with_the_same_thresholds_on_both_backends.custom_rules["dns_burn_fast"] }
  }

  expect_failures = [grafana_folder.this]
}
