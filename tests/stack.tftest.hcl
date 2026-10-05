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

run "opentelemetry_installs_operator_collector_and_instrumentation" {
  command = plan

  module {
    source = "./modules/stack"
  }

  variables {
    kube_prometheus_stack = { enabled = true }
    opentelemetry         = { enabled = true }
  }

  assert {
    condition     = length(helm_release.opentelemetry) == 1 && contains(output.installed, "opentelemetry")
    error_message = "opentelemetry should install the kube-stack chart."
  }

  assert {
    condition     = output.opentelemetry_instrumentation == "monitoring/opentelemetry"
    error_message = "The Instrumentation should be <namespace>/<release_name>."
  }

  assert {
    condition     = yamldecode(helm_release.opentelemetry[0].values[0]).instrumentation.exporter.endpoint == "http://opentelemetry-collector.monitoring.svc.cluster.local:4318"
    error_message = "Apps should export to the collector's Service."
  }

  assert {
    condition     = !yamldecode(helm_release.opentelemetry[0].values[0]).crds.installPrometheus && !yamldecode(helm_release.opentelemetry[0].values[0]).collectors.daemon.enabled
    error_message = "The chart must not install the Prometheus CRDs (kube-prometheus-stack owns them) or its default daemonset collector."
  }

  assert {
    condition     = yamldecode(helm_release.opentelemetry[0].values[0]).instrumentation.java.image != ""
    error_message = "Agent images must be set explicitly; the webhook can't default them at install time."
  }

  assert {
    condition     = yamldecode(helm_release.opentelemetry[0].values[0]).extraObjects[0].metadata.labels.release == "kube-prometheus-stack"
    error_message = "The ServiceMonitor needs kube-prometheus-stack's release label to be scraped."
  }

  assert {
    condition     = !yamldecode(helm_release.opentelemetry[0].values[0])["opentelemetry-operator"].manager.autoInstrumentation.go.enabled
    error_message = "Go eBPF auto-instrumentation should be off by default."
  }
}

run "opentelemetry_without_kube_prometheus_stack_has_no_servicemonitor" {
  command = plan

  module {
    source = "./modules/stack"
  }

  variables {
    opentelemetry = { enabled = true }
  }

  assert {
    condition     = length(yamldecode(helm_release.opentelemetry[0].values[0]).extraObjects) == 0
    error_message = "Without kube-prometheus-stack there is no ServiceMonitor CRD, so the module shouldn't create one."
  }
}

run "datadog_agent_base_values" {
  command = plan

  module {
    source = "./modules/stack"
  }

  variables {
    datadog_agent = { enabled = true, api_key_secret_name = "datadog-secret" }
  }

  assert {
    condition     = length(output.installed) == 1 && contains(output.installed, "datadog_agent")
    error_message = "Only the Datadog Agent should be installed."
  }

  assert {
    condition     = helm_release.datadog_agent[0].repository == "https://helm.datadoghq.com" && helm_release.datadog_agent[0].version == "3.251.1"
    error_message = "The Agent should come from Datadog's chart repository at the pinned version."
  }

  assert {
    condition     = yamldecode(helm_release.datadog_agent[0].values[0]).datadog.clusterName == "test" && yamldecode(helm_release.datadog_agent[0].values[0]).datadog.apiKeyExistingSecret == "datadog-secret"
    error_message = "The Agent should take the cluster name and the existing API key Secret."
  }

  assert {
    condition     = yamldecode(helm_release.datadog_agent[0].values[0]).datadog.kubeStateMetricsCore.enabled && yamldecode(helm_release.datadog_agent[0].values[0]).datadog.apm.portEnabled && yamldecode(helm_release.datadog_agent[0].values[0]).clusterAgent.enabled
    error_message = "kubernetes_state_core, APM and the Cluster Agent should be on."
  }

  assert {
    condition     = !yamldecode(helm_release.datadog_agent[0].values[0]).datadog.logs.enabled
    error_message = "Logs should be off unless asked for."
  }

  assert {
    condition     = helm_release.datadog_agent[0].set_sensitive == null
    error_message = "With an existing Secret, no API key should be passed to Helm."
  }
}

run "datadog_agent_needs_an_api_key" {
  command = plan

  module {
    source = "./modules/stack"
  }

  variables {
    datadog_agent = { enabled = true }
  }

  expect_failures = [helm_release.datadog_agent]
}

run "datadog_agent_on_k3s_with_control_plane_checks" {
  command = plan

  module {
    source = "./modules/stack"
  }

  variables {
    cluster_type    = "k3s"
    datadog_api_key = "not-a-real-key"
    datadog_agent = {
      control_plane_checks = { enabled = true, etcd_prometheus_url = "http://10.0.0.1:2381/metrics" }
      enabled              = true
      logs                 = true
    }
  }

  assert {
    condition     = contains([for e in yamldecode(helm_release.datadog_agent[0].values[0]).datadog.env : "${e.name}=${e.value}"], "DD_INTEGRATION_CHECK_STATUS_ENABLED=true")
    error_message = "The Agent must send datadog.agent.check_status, which the scrape_target_down monitor reads and new Agents turn off by default."
  }

  assert {
    condition     = yamldecode(helm_release.datadog_agent[0].values[1]).datadog.criSocketPath == "/run/k3s/containerd/containerd.sock" && !yamldecode(helm_release.datadog_agent[0].values[1]).datadog.kubelet.tlsVerify
    error_message = "k3s should use its own containerd socket and skip kubelet TLS verification."
  }

  assert {
    condition     = contains(keys(yamldecode(helm_release.datadog_agent[0].values[2]).clusterAgent.confd), "kube_apiserver_metrics.yaml") && yamldecode(yamldecode(helm_release.datadog_agent[0].values[2]).clusterAgent.confd["etcd.yaml"]).instances[0].prometheus_url == "http://10.0.0.1:2381/metrics"
    error_message = "Control-plane checks should add kube_apiserver_metrics and etcd cluster checks."
  }

  assert {
    condition     = yamldecode(helm_release.datadog_agent[0].values[0]).datadog.logs.enabled && yamldecode(helm_release.datadog_agent[0].values[0]).datadog.logs.containerCollectAll
    error_message = "logs should collect every container's logs."
  }

  assert {
    condition     = length(helm_release.datadog_agent[0].set_sensitive) == 1 && helm_release.datadog_agent[0].set_sensitive[0].name == "datadog.apiKey"
    error_message = "Without a Secret, the API key should be passed to Helm as a sensitive value."
  }
}

run "datadog_agent_values_per_cluster_type" {
  command = plan

  module {
    source = "./modules/stack"
  }

  variables {
    cluster_type  = "eks"
    datadog_agent = { enabled = true, api_key_secret_name = "datadog-secret", control_plane_checks = { enabled = true } }
  }

  assert {
    condition     = yamldecode(helm_release.datadog_agent[0].values[2]).providers.eks.controlPlaneMonitoring && !can(yamldecode(helm_release.datadog_agent[0].values[2]).clusterAgent)
    error_message = "On EKS, control-plane checks should use the chart's EKS control-plane monitoring instead of a cluster check."
  }

  assert {
    condition     = yamldecode(local.datadog_cluster_values["gke-autopilot"]).providers.gke.autopilot && yamldecode(local.datadog_cluster_values["aks"]).providers.aks.enabled
    error_message = "GKE Autopilot and AKS should turn on the chart's provider settings."
  }

  assert {
    condition     = yamldecode(local.datadog_cluster_values["openshift"]).agents.podSecurity.securityContextConstraints.create && yamldecode(local.datadog_cluster_values["openshift"]).datadog.criSocketPath == "/var/run/crio/crio.sock"
    error_message = "OpenShift should create SCCs and use CRI-O's socket."
  }
}
