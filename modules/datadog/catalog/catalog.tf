# The alert catalog as Datadog metric monitors. Rule IDs, titles, groups,
# severities and default thresholds match modules/alerts/catalog.tf, so the
# same overrides and disabled_rules work on either backend. Queries read the
# metrics the Datadog Agent collects: its kubernetes_state_core check
# (kubernetes_state.*), the kubelet check (kubernetes.*) and host metrics
# (system.*).
#
# `query` is the monitor query without its comparison: the module appends
# the operator and threshold, so the threshold in the query always matches
# the critical threshold. `__SCOPE__` is replaced with the cluster tag and,
# for workload rules, var.workload_scope, joined with AND. `window` replaces
# `__WINDOW__` and plays the part of Grafana's pending period: `min()` over
# the window for gt rules means the condition held for the whole window.
#
# Rules where zero means healthy wrap their metric in default_zero(), so a
# series that stops reporting (a deleted pod) evaluates as 0 and resolves.
# None of them use on_missing_data = "resolve", which would hide a real
# outage when data stops.
#
# Service-check rules (`type = "service check"`) work differently: the query
# counts check statuses, `__TAGS__` is replaced with the cluster tag, and the
# threshold is how many consecutive check runs must fail. The Agent runs each
# check every 15 seconds, so 8 is about 2 minutes.
#
# `requires` names what a rule needs, checked against local.enabled: the
# control-plane checks are off by default because managed clusters don't
# expose them.
#
# skipped_rules lists the catalog rules that have no Datadog equivalent here.
locals {
  catalog = {
    # ── Pods ──────────────────────────────────────────────────────────────
    container_oom_killed = {
      group               = "pods"
      operator            = "gt"
      query               = "sum(__WINDOW__):default_zero(diff(max:kubernetes_state.container.restarts{__SCOPE__} by {kube_namespace,pod_name,kube_container_name})) * default_zero(max:kubernetes.containers.last_state.terminated{reason:oomkilled AND __SCOPE__} by {kube_namespace,pod_name,kube_container_name})"
      require_full_window = false
      severity            = "warning"
      summary             = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) was OOM killed in the last 15 minutes. Raise its memory limit or find the leak."
      threshold           = 0
      title               = "Container OOM killed"
      window              = "last_15m"
      workload            = true
    }
    pod_crash_looping = {
      group               = "pods"
      operator            = "gt"
      query               = "sum(__WINDOW__):default_zero(diff(max:kubernetes_state.container.restarts{__SCOPE__} by {kube_namespace,pod_name,kube_container_name}))"
      require_full_window = false
      severity            = "critical"
      summary             = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) restarted {{value}} times in 15 minutes."
      threshold           = 5
      title               = "Pod crash looping"
      window              = "last_15m"
      workload            = true
    }
    # Running pods that fail their readiness check, so they get no traffic.
    pod_not_ready = {
      group     = "pods"
      operator  = "gt"
      query     = "min(__WINDOW__):default_zero(max:kubernetes_state.pod.ready{condition:false AND __SCOPE__} by {kube_namespace,pod_name}) * default_zero(max:kubernetes_state.pod.status_phase{pod_phase:running AND __SCOPE__} by {kube_namespace,pod_name})"
      severity  = "warning"
      summary   = "{{kube_namespace.name}}/{{pod_name.name}} is running but has failed its readiness check for 15 minutes, so it gets no traffic."
      threshold = 0
      title     = "Pod not ready"
      window    = "last_15m"
      workload  = true
    }
    pod_pending = {
      group     = "pods"
      operator  = "gt"
      query     = "min(__WINDOW__):default_zero(max:kubernetes_state.pod.status_phase{pod_phase:pending AND __SCOPE__} by {kube_namespace,pod_name})"
      severity  = "warning"
      summary   = "{{kube_namespace.name}}/{{pod_name.name}} has been pending for 5 minutes. Check for unschedulable resources, taints or unbound volumes."
      threshold = 0
      title     = "Pod stuck pending"
      window    = "last_5m"
      workload  = true
    }
    pod_waiting_failure = {
      group     = "pods"
      operator  = "gt"
      query     = "min(__WINDOW__):default_zero(max:kubernetes_state.container.status_report.count.waiting{reason IN (crashloopbackoff,imagepullbackoff,errimagepull,createcontainerconfigerror,invalidimagename) AND __SCOPE__} by {kube_namespace,pod_name,kube_container_name,reason})"
      severity  = "critical"
      summary   = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) has been waiting in {{reason.name}} for 5 minutes."
      threshold = 0
      title     = "Pod cannot start"
      window    = "last_5m"
      workload  = true
    }

    # ── Workloads ─────────────────────────────────────────────────────────
    daemonset_not_ready = {
      group     = "workloads"
      operator  = "gt"
      query     = "min(__WINDOW__):max:kubernetes_state.daemonset.desired{__SCOPE__} by {kube_namespace,kube_daemon_set} - max:kubernetes_state.daemonset.ready{__SCOPE__} by {kube_namespace,kube_daemon_set}"
      severity  = "warning"
      summary   = "{{kube_namespace.name}}/{{kube_daemon_set.name}} has had pods not ready for 15 minutes."
      threshold = 0
      title     = "DaemonSet pods not ready"
      window    = "last_15m"
      workload  = true
    }
    deployment_rollout_stuck = {
      group     = "workloads"
      operator  = "gt"
      query     = "min(__WINDOW__):default_zero(max:kubernetes_state.deployment.condition{condition:progressing AND status:false AND __SCOPE__} by {kube_namespace,kube_deployment})"
      severity  = "warning"
      summary   = "{{kube_namespace.name}}/{{kube_deployment.name}} passed its progress deadline without finishing the rollout."
      threshold = 0
      title     = "Deployment rollout stuck"
      window    = "last_5m"
      workload  = true
    }
    # The fraction of desired replicas that are unavailable: 1 when none are
    # available. A deployment scaled to zero divides by zero and has no data.
    deployment_unavailable = {
      group     = "workloads"
      operator  = "gt"
      query     = "min(__WINDOW__):(max:kubernetes_state.deployment.replicas_desired{__SCOPE__} by {kube_namespace,kube_deployment} - max:kubernetes_state.deployment.replicas_available{__SCOPE__} by {kube_namespace,kube_deployment}) / max:kubernetes_state.deployment.replicas_desired{__SCOPE__} by {kube_namespace,kube_deployment}"
      severity  = "critical"
      summary   = "{{kube_namespace.name}}/{{kube_deployment.name}} wants replicas but has none available."
      threshold = 0.99
      title     = "Deployment has no available replicas"
      window    = "last_5m"
      workload  = true
    }
    deployment_under_replicated = {
      group     = "workloads"
      operator  = "gt"
      query     = "min(__WINDOW__):max:kubernetes_state.deployment.replicas_desired{__SCOPE__} by {kube_namespace,kube_deployment} - max:kubernetes_state.deployment.replicas_available{__SCOPE__} by {kube_namespace,kube_deployment}"
      severity  = "warning"
      summary   = "{{kube_namespace.name}}/{{kube_deployment.name}} has had fewer available replicas than desired for 10 minutes."
      threshold = 0
      title     = "Deployment under-replicated"
      window    = "last_10m"
      workload  = true
    }
    hpa_at_max = {
      group     = "workloads"
      operator  = "gt"
      query     = "min(__WINDOW__):max:kubernetes_state.hpa.current_replicas{__SCOPE__} by {kube_namespace,horizontalpodautoscaler} / max:kubernetes_state.hpa.max_replicas{__SCOPE__} by {kube_namespace,horizontalpodautoscaler}"
      severity  = "warning"
      summary   = "{{kube_namespace.name}}/{{horizontalpodautoscaler.name}} has run at its maximum replicas for 30 minutes and can't scale further."
      threshold = 0.999
      title     = "HPA pinned at max replicas"
      window    = "last_30m"
      workload  = true
    }
    job_failed = {
      group               = "workloads"
      operator            = "gt"
      query               = "max(__WINDOW__):default_zero(max:kubernetes_state.job.completion.failed{__SCOPE__} by {kube_namespace,kube_job})"
      require_full_window = false
      severity            = "warning"
      summary             = "Job {{kube_namespace.name}}/{{kube_job.name}} failed. Check its pods' logs; it stays failed until the Job is deleted or rerun."
      threshold           = 0
      title               = "Job failed"
      window              = "last_5m"
      workload            = true
    }
    # Multiplying by active / active keeps the duration while the Job has
    # active pods and leaves a gap once it finishes.
    job_not_completed = {
      group               = "workloads"
      operator            = "gt"
      query               = "max(__WINDOW__):max:kubernetes_state.job.duration{__SCOPE__} by {kube_namespace,kube_job} * max:kubernetes_state.job.active{__SCOPE__} by {kube_namespace,kube_job} / max:kubernetes_state.job.active{__SCOPE__} by {kube_namespace,kube_job}"
      require_full_window = false
      severity            = "warning"
      summary             = "Job {{kube_namespace.name}}/{{kube_job.name}} has been running for {{value}}s. It may be stuck."
      threshold           = 43200
      title               = "Job running too long"
      window              = "last_5m"
      workload            = true
    }
    statefulset_under_replicated = {
      group     = "workloads"
      operator  = "gt"
      query     = "min(__WINDOW__):max:kubernetes_state.statefulset.replicas_desired{__SCOPE__} by {kube_namespace,kube_stateful_set} - max:kubernetes_state.statefulset.replicas_ready{__SCOPE__} by {kube_namespace,kube_stateful_set}"
      severity  = "warning"
      summary   = "{{kube_namespace.name}}/{{kube_stateful_set.name}} has had fewer ready replicas than desired for 15 minutes."
      threshold = 0
      title     = "StatefulSet under-replicated"
      window    = "last_15m"
      workload  = true
    }

    # ── Resources ─────────────────────────────────────────────────────────
    # kubernetes.cpu.usage.total is in nanocores and kubernetes.cpu.limits in
    # cores.
    container_cpu_near_limit_critical = {
      group     = "resources"
      operator  = "gt"
      query     = "min(__WINDOW__):100 * max:kubernetes.cpu.usage.total{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} / (max:kubernetes.cpu.limits{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} * 1000000000)"
      severity  = "critical"
      summary   = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) is using {{value}}% of its CPU limit."
      threshold = 90
      title     = "Container CPU at limit"
      window    = "last_15m"
      workload  = true
    }
    container_cpu_near_limit_warning = {
      group     = "resources"
      operator  = "gt"
      query     = "min(__WINDOW__):100 * max:kubernetes.cpu.usage.total{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} / (max:kubernetes.cpu.limits{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} * 1000000000)"
      severity  = "warning"
      summary   = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) is using {{value}}% of its CPU limit."
      threshold = 80
      title     = "Container CPU near limit"
      window    = "last_15m"
      workload  = true
    }
    container_cpu_throttled = {
      group     = "resources"
      operator  = "gt"
      query     = "min(__WINDOW__):100 * max:kubernetes.cpu.cfs.throttled.periods{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} / max:kubernetes.cpu.cfs.periods{__SCOPE__} by {kube_namespace,pod_name,kube_container_name}"
      severity  = "warning"
      summary   = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) was throttled in {{value}}% of CPU periods."
      threshold = 25
      title     = "Container CPU throttled"
      window    = "last_15m"
      workload  = true
    }
    # The kubelet reports ephemeral storage per pod, not per container.
    container_ephemeral_storage_near_limit = {
      group     = "resources"
      operator  = "gt"
      query     = "min(__WINDOW__):100 * max:kubernetes.ephemeral_storage.usage{__SCOPE__} by {kube_namespace,pod_name} / max:kubernetes.ephemeral_storage.limits{__SCOPE__} by {kube_namespace,pod_name}"
      severity  = "critical"
      summary   = "{{kube_namespace.name}}/{{pod_name.name}} is using {{value}}% of its ephemeral storage limit. The kubelet evicts it at 100%."
      threshold = 80
      title     = "Container ephemeral storage near limit"
      window    = "last_5m"
      workload  = true
    }
    container_memory_near_limit_critical = {
      group     = "resources"
      operator  = "gt"
      query     = "min(__WINDOW__):100 * max:kubernetes.memory.working_set{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} / max:kubernetes.memory.limits{__SCOPE__} by {kube_namespace,pod_name,kube_container_name}"
      severity  = "critical"
      summary   = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) is using {{value}}% of its memory limit and will be OOM killed at 100%."
      threshold = 90
      title     = "Container memory at limit"
      window    = "last_5m"
      workload  = true
    }
    container_memory_near_limit_warning = {
      group     = "resources"
      operator  = "gt"
      query     = "min(__WINDOW__):100 * max:kubernetes.memory.working_set{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} / max:kubernetes.memory.limits{__SCOPE__} by {kube_namespace,pod_name,kube_container_name}"
      severity  = "warning"
      summary   = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) is using {{value}}% of its memory limit."
      threshold = 80
      title     = "Container memory near limit"
      window    = "last_10m"
      workload  = true
    }
    # PersistentVolumes are cluster-wide, so workload_scope doesn't apply.
    persistent_volume_errors = {
      group     = "resources"
      operator  = "gt"
      query     = "min(__WINDOW__):default_zero(max:kubernetes_state.persistentvolume.by_phase{phase IN (failed,pending) AND __SCOPE__} by {persistentvolume,phase})"
      severity  = "critical"
      summary   = "PersistentVolume {{persistentvolume.name}} has been {{phase.name}} for 5 minutes. Pods that use it can't start."
      threshold = 0
      title     = "PersistentVolume failed"
      window    = "last_5m"
    }
    pvc_inodes_near_full = {
      group     = "resources"
      operator  = "gt"
      query     = "min(__WINDOW__):100 * max:kubernetes.kubelet.volume.stats.inodes_used{__SCOPE__} by {kube_namespace,persistentvolumeclaim} / max:kubernetes.kubelet.volume.stats.inodes{__SCOPE__} by {kube_namespace,persistentvolumeclaim}"
      severity  = "warning"
      summary   = "PVC {{kube_namespace.name}}/{{persistentvolumeclaim.name}} has used {{value}}% of its inodes. New files fail at 100% even with free space."
      threshold = 90
      title     = "PVC running out of inodes"
      window    = "last_10m"
      workload  = true
    }
    pvc_near_full_critical = {
      group     = "resources"
      operator  = "gt"
      query     = "min(__WINDOW__):100 * max:kubernetes.kubelet.volume.stats.used_bytes{__SCOPE__} by {kube_namespace,persistentvolumeclaim} / max:kubernetes.kubelet.volume.stats.capacity_bytes{__SCOPE__} by {kube_namespace,persistentvolumeclaim}"
      severity  = "critical"
      summary   = "{{kube_namespace.name}}/{{persistentvolumeclaim.name}} is {{value}}% full."
      threshold = 90
      title     = "PersistentVolumeClaim critically full"
      window    = "last_5m"
      workload  = true
    }
    pvc_near_full_warning = {
      group     = "resources"
      operator  = "gt"
      query     = "min(__WINDOW__):100 * max:kubernetes.kubelet.volume.stats.used_bytes{__SCOPE__} by {kube_namespace,persistentvolumeclaim} / max:kubernetes.kubelet.volume.stats.capacity_bytes{__SCOPE__} by {kube_namespace,persistentvolumeclaim}"
      severity  = "warning"
      summary   = "{{kube_namespace.name}}/{{persistentvolumeclaim.name}} is {{value}}% full."
      threshold = 80
      title     = "PersistentVolumeClaim almost full"
      window    = "last_10m"
      workload  = true
    }

    # ── Nodes ─────────────────────────────────────────────────────────────
    kubelet_certificate_expiring = {
      group     = "nodes"
      operator  = "lt"
      query     = "max(__WINDOW__):min:kubernetes.kubelet.certificate_manager.client_ttl{__SCOPE__} by {host}"
      severity  = "warning"
      summary   = "The kubelet's client certificate on {{host.name}} expires in {{value}}s."
      threshold = 604800
      title     = "Kubelet certificate expiring"
      window    = "last_15m"
    }
    # The Agent's NTP check is on by default and reports the offset from its
    # NTP servers.
    node_clock_not_synchronising = {
      group     = "nodes"
      query     = "\"ntp.in_sync\".over(__TAGS__).by(\"host\").last(__LAST__).count_by_status()"
      severity  = "warning"
      summary   = "{{host.name}}'s clock is out of sync with NTP."
      threshold = 1
      title     = "Node clock not synchronising"
      type      = "service check"
    }
    node_clock_skew = {
      group     = "nodes"
      operator  = "gt"
      query     = "min(__WINDOW__):abs(max:ntp.offset{__SCOPE__} by {host})"
      severity  = "warning"
      summary   = "{{host.name}}'s clock is {{value}}s off. Skew breaks TLS, tokens and log ordering; check NTP."
      threshold = 0.05
      title     = "Node clock skewed"
      # The NTP check runs every 15 minutes, so a shorter window never fills.
      require_full_window = false
      window              = "last_30m"
    }
    node_disk_full = {
      group     = "nodes"
      operator  = "gt"
      query     = "min(__WINDOW__):100 * max:system.disk.in_use{__SCOPE__} by {host,device}"
      severity  = "critical"
      summary   = "{{device.name}} on {{host.name}} is {{value}}% full."
      threshold = 85
      title     = "Node disk almost full"
      window    = "last_10m"
    }
    node_inodes_low = {
      group     = "nodes"
      operator  = "gt"
      query     = "min(__WINDOW__):100 * max:system.fs.inodes.in_use{__SCOPE__} by {host,device}"
      severity  = "warning"
      summary   = "{{device.name}} on {{host.name}} has used {{value}}% of its inodes. New files fail at 100% even with free space."
      threshold = 90
      title     = "Node running out of inodes"
      window    = "last_10m"
    }
    node_memory_high = {
      group     = "nodes"
      operator  = "gt"
      query     = "min(__WINDOW__):100 * (1 - max:system.mem.usable{__SCOPE__} by {host} / max:system.mem.total{__SCOPE__} by {host})"
      severity  = "warning"
      summary   = "{{host.name}} is using {{value}}% of its memory."
      threshold = 90
      title     = "Node memory high"
      window    = "last_10m"
    }
    node_network_errors = {
      group     = "nodes"
      operator  = "gt"
      query     = "min(__WINDOW__):max:system.net.packets_in.error{__SCOPE__} by {host,device} + max:system.net.packets_out.error{__SCOPE__} by {host,device}"
      severity  = "warning"
      summary   = "{{device.name}} on {{host.name}} has {{value}} receive/transmit errors per second."
      threshold = 1
      title     = "Node network errors"
      window    = "last_10m"
    }
    node_not_ready = {
      group     = "nodes"
      operator  = "gt"
      query     = "min(__WINDOW__):default_zero(max:kubernetes_state.node.by_condition{condition:ready AND status IN (false,unknown) AND __SCOPE__} by {node})"
      severity  = "critical"
      summary   = "Node {{node.name}} has not been Ready for 5 minutes."
      threshold = 0
      title     = "Node not ready"
      window    = "last_5m"
    }
    node_pressure = {
      group     = "nodes"
      operator  = "gt"
      query     = "min(__WINDOW__):default_zero(max:kubernetes_state.node.by_condition{condition IN (memorypressure,diskpressure,pidpressure) AND status:true AND __SCOPE__} by {node,condition})"
      severity  = "warning"
      summary   = "Node {{node.name}} reports {{condition.name}}. The kubelet may start evicting pods."
      threshold = 0
      title     = "Node under resource pressure"
      window    = "last_5m"
    }

    # Counts changes of the Ready condition, as modules/alerts does with
    # changes().
    node_readiness_flapping = {
      group               = "nodes"
      operator            = "gt"
      query               = "sum(__WINDOW__):abs(diff(max:kubernetes_state.node.by_condition{condition:ready AND status:true AND __SCOPE__} by {node}))"
      require_full_window = false
      severity            = "warning"
      summary             = "Node {{node.name}} changed Ready state {{value}} times in 15 minutes. Check its network and kubelet."
      threshold           = 2
      title               = "Node readiness flapping"
      window              = "last_15m"
    }
    # Needs the Agent's systemd check, which isn't on by default. Without it
    # there's no data and the monitor stays quiet.
    node_systemd_service_failed = {
      group     = "nodes"
      query     = "\"systemd.unit.state\".over(__TAGS__).by(\"host\",\"unit\").last(__LAST__).count_by_status()"
      severity  = "warning"
      summary   = "systemd unit {{unit.name}} on {{host.name}} has failed."
      threshold = 20
      title     = "systemd service failed"
      type      = "service check"
    }
    # The closest match to Prometheus' `up`: an Agent check (an integration
    # or an OpenMetrics endpoint) that keeps failing.
    scrape_target_down = {
      group     = "nodes"
      query     = "\"datadog.agent.check_status\".over(__TAGS__).by(\"check\",\"host\").last(__LAST__).count_by_status()"
      severity  = "warning"
      summary   = "The Agent's {{check.name}} check on {{host.name}} has failed for 10 minutes. Alerts that depend on it go quiet."
      threshold = 40
      title     = "Metrics target down"
      type      = "service check"
    }

    # ── Control plane (self-managed clusters, or EKS/OpenShift control-plane monitoring) ──
    # Requests made with a client certificate that expires within 7 days, from
    # the kube_apiserver_metrics histogram's bucket. Datadog can't take a
    # quantile of it, so the threshold is a request count.
    apiserver_client_certificate_expiring = {
      group               = "control-plane"
      operator            = "gt"
      query               = "sum(__WINDOW__):default_zero(sum:kube_apiserver.apiserver_client_certificate_expiration_seconds.bucket{upper_bound:604800.0 AND __SCOPE__}.as_count())"
      require_full_window = false
      requires            = "apiserver"
      severity            = "warning"
      summary             = "{{value}} API server requests in the last 15 minutes used a client certificate that expires within 7 days."
      threshold           = 0
      title               = "Client certificate expiring"
      window              = "last_15m"
    }
    apiserver_errors = {
      group     = "control-plane"
      operator  = "gt"
      query     = "avg(__WINDOW__):100 * sum:kube_apiserver.apiserver_request_total.count{code:5* AND __SCOPE__}.as_rate() / sum:kube_apiserver.apiserver_request_total.count{__SCOPE__}.as_rate()"
      requires  = "apiserver"
      severity  = "critical"
      summary   = "{{value}}% of API server requests are failing with 5xx."
      threshold = 5
      title     = "API server error rate high"
      window    = "last_10m"
    }
    etcd_no_leader = {
      group     = "control-plane"
      operator  = "lt"
      query     = "max(__WINDOW__):min:etcd.server.has_leader{__SCOPE__} by {host}"
      requires  = "etcd"
      severity  = "critical"
      summary   = "etcd member {{host.name}} has no leader and can't serve requests."
      threshold = 1
      title     = "etcd member has no leader"
      window    = "last_1m"
    }

    # ── Datadog only ──────────────────────────────────────────────────────
    # The heartbeat's job on this backend: Datadog runs outside the cluster,
    # so it can alert when the cluster stops sending data at all.
    cluster_not_reporting = {
      group           = "nodes"
      on_missing_data = "show_and_notify_no_data"
      operator        = "lt"
      query           = "max(__WINDOW__):sum:kubernetes_state.node.count{__SCOPE__}"
      severity        = "critical"
      summary         = "The cluster has stopped sending Kubernetes metrics to Datadog for 10 minutes. The Agent, its network path or the whole cluster may be down."
      threshold       = 1
      title           = "Cluster not reporting"
      window          = "last_10m"
    }
  }

  # modules/alerts rules with no equivalent here, and why.
  # tests/datadog.tftest.hcl checks that every modules/alerts catalog rule is
  # either mapped or listed here.
  skipped_rules = {
    notification_delivery_failing     = "Watches Grafana's notification pipeline. Datadog reports its own delivery failures."
    prometheus_config_reload_failed   = "Prometheus' own health. This backend has no Prometheus; cluster_not_reporting catches the Agent going quiet."
    prometheus_not_ingesting          = "Prometheus' own health. This backend has no Prometheus; cluster_not_reporting catches the Agent going quiet."
    prometheus_rule_failures          = "Prometheus' own health. This backend has no Prometheus; cluster_not_reporting catches the Agent going quiet."
    synthetic_check_failing           = "Datadog Synthetics, tracked in an issue."
    synthetic_check_slow              = "Datadog Synthetics, tracked in an issue."
    tls_certificate_expiring_critical = "Datadog Synthetics, tracked in an issue."
    tls_certificate_expiring_warning  = "Datadog Synthetics, tracked in an issue."
  }
}
