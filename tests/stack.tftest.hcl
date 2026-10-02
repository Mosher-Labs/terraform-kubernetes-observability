mock_provider "helm" {}

variables {
  cluster_name = "test"
}

run "nothing_installed_by_default" {
  command = plan

  module {
    source = "./modules/stack"
  }

  assert {
    condition     = length(output.installed) == 0
    error_message = "Every component should be off unless its flag is set."
  }
}

run "each_flag_installs_only_its_component" {
  command = plan

  module {
    source = "./modules/stack"
  }

  variables {
    kube_prometheus_stack = { enabled = true }
  }

  assert {
    condition     = length(helm_release.kube_prometheus_stack) == 1 && length(helm_release.loki) == 0 && length(helm_release.alloy) == 0 && length(helm_release.blackbox_exporter) == 0
    error_message = "Only kube-prometheus-stack should be installed."
  }

  assert {
    condition     = output.prometheus_datasource_uid == "prometheus" && output.loki_datasource_uid == null
    error_message = "Grafana should get the Prometheus datasource, and no Loki datasource without Loki."
  }
}

run "loki_is_wired_into_grafana_and_alloy" {
  command = plan

  module {
    source = "./modules/stack"
  }

  variables {
    alloy                 = { enabled = true }
    kube_prometheus_stack = { enabled = true }
    loki                  = { enabled = true }
  }

  assert {
    condition     = strcontains(helm_release.kube_prometheus_stack[0].values[0], "http://loki.monitoring.svc.cluster.local:3100")
    error_message = "Grafana should get a Loki datasource pointing at the in-cluster Loki."
  }

  assert {
    condition     = strcontains(helm_release.alloy[0].values[0], "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push") && strcontains(helm_release.alloy[0].values[0], "cluster = \"test\"")
    error_message = "Alloy should push to the in-cluster Loki with the cluster label."
  }

  assert {
    condition     = output.loki_datasource_uid == "loki"
    error_message = "The Loki datasource UID should be output."
  }
}

run "alloy_needs_a_loki" {
  command = plan

  module {
    source = "./modules/stack"
  }

  variables {
    alloy = { enabled = true }
  }

  expect_failures = [helm_release.alloy]
}

run "alloy_can_use_an_external_loki" {
  command = plan

  module {
    source = "./modules/stack"
  }

  variables {
    alloy = { enabled = true, push_url = "https://logs.example.com/loki/api/v1/push" }
  }

  assert {
    condition     = strcontains(helm_release.alloy[0].values[0], "https://logs.example.com/loki/api/v1/push")
    error_message = "Alloy should use push_url when Loki isn't installed here."
  }
}

run "synthetic_targets_are_scraped_by_prometheus" {
  command = plan

  module {
    source = "./modules/stack"
  }

  variables {
    blackbox_exporter = {
      enabled = true
      targets = [{ name = "homepage", url = "https://example.com" }]
    }
    kube_prometheus_stack = { enabled = true }
  }

  assert {
    condition     = strcontains(helm_release.blackbox_exporter[0].values[0], "https://example.com") && strcontains(helm_release.blackbox_exporter[0].values[0], "http_2xx")
    error_message = "Each target should be probed with http_2xx by default."
  }

  assert {
    condition     = yamldecode(helm_release.blackbox_exporter[0].values[0]).serviceMonitor.defaults.labels.release == "kube-prometheus-stack"
    error_message = "The ServiceMonitor needs kube-prometheus-stack's release label to be scraped."
  }
}

run "caller_values_come_after_the_modules" {
  command = plan

  module {
    source = "./modules/stack"
  }

  variables {
    loki = { enabled = true, values = ["singleBinary:\n  replicas: 2\n"] }
  }

  assert {
    condition     = length(helm_release.loki[0].values) == 2 && strcontains(helm_release.loki[0].values[1], "replicas: 2")
    error_message = "Caller values should be applied after the module's, so they win."
  }
}
