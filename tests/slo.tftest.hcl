# modules/slo turns SLO definitions into burn-rate alert rules for modules/alerts.
# It has no providers, so these runs only plan.
variables {
  slos = {
    dns = {
      error_ratio = "sum(increase(bad[$${window}])) / sum(increase(total[$${window}]))"
      target      = 0.999
      title       = "DNS replies"
    }
  }
}

run "three_tiers_with_workbook_thresholds" {
  command = plan

  module {
    source = "./modules/slo"
  }

  assert {
    condition     = length(output.custom_rules) == 3
    error_message = "Expected a fast, medium and slow rule."
  }

  assert {
    condition     = output.custom_rules["dns_burn_fast"].threshold == 14.4 && output.custom_rules["dns_burn_medium"].threshold == 6 && output.custom_rules["dns_burn_slow"].threshold == 1
    error_message = "Thresholds should be 14.4, 6 and 1 for a 30-day window."
  }

  assert {
    condition     = output.custom_rules["dns_burn_fast"].severity == "critical" && output.custom_rules["dns_burn_slow"].severity == "warning"
    error_message = "Fast burns page, the slow burn opens a ticket."
  }
}

run "expression_uses_both_windows_and_the_budget" {
  command = plan

  module {
    source = "./modules/slo"
  }

  assert {
    condition     = strcontains(output.custom_rules["dns_burn_fast"].expr, "increase(bad[1h])") && strcontains(output.custom_rules["dns_burn_fast"].expr, "increase(bad[5m])")
    error_message = "The fast rule should use a 1h and a 5m window."
  }

  assert {
    condition     = strcontains(output.custom_rules["dns_burn_fast"].expr, "/ 0.001")
    error_message = "The ratio should be divided by the 0.1% budget."
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
        error_ratio = "sum(increase(bad[$${window}])) / sum(increase(total[$${window}]))"
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
    condition     = strcontains(output.custom_rules["dns_burn_fast"].expr, "/ 0.01")
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
        error_ratio = "1 - (sum(increase(good[$${window}])) / sum(increase(total[$${window}])))"
        target      = 0.99
        tiers       = ["slow"]
        title       = "Sync imports"
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
        error_ratio = "sum(increase(bad[$${window}])) / sum(increase(total[$${window}]))"
        target      = 1
        title       = "DNS replies"
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
        error_ratio = "sum(bad) / sum(total)"
        target      = 0.999
        title       = "DNS replies"
      }
    }
  }

  expect_failures = [var.slos]
}

run "rules_fit_the_alerts_module" {
  command = plan

  module {
    source = "./modules/alerts"
  }

  variables {
    cluster_name              = "t"
    prometheus_datasource_uid = "prometheus"
    custom_rules              = run.three_tiers_with_workbook_thresholds.custom_rules
  }

  assert {
    condition     = length(output.rule_ids) > 0
    error_message = "modules/alerts should accept the rendered rules."
  }
}
