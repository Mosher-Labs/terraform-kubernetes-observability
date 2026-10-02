# The alert catalog. Each rule is a PromQL query, evaluated as an instant
# query, and a Grafana threshold on its value. Keeping the threshold out of
# the PromQL lets callers override it without rewriting queries.
#
# `__SEL__` marks where var.workload_selector goes, in the forms `{__SEL__}`
# and `,__SEL__}`. Only workload rules take it; node and control-plane
# metrics have no namespace to scope by.
#
# `requires` names the capability a rule needs, checked against
# local.capabilities: "apiserver" and "etcd" are control-plane metrics that
# managed clusters (EKS, AKS, GKE) don't expose.
locals {
  catalog = {
    # ── Pods ──────────────────────────────────────────────────────────────
    container_oom_killed = {
      expr           = "sum by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total{__SEL__}[15m]) > 0 and on (namespace, pod, container) kube_pod_container_status_last_terminated_reason{reason=\"OOMKilled\",__SEL__} == 1)"
      group          = "pods"
      operator       = "gt"
      pending_period = "0s"
      severity       = "warning"
      subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) was OOM killed in the last 15 minutes. Raise its memory limit or find the leak."
      threshold      = 0
      title          = "Container OOM killed"
    }
    pod_crash_looping = {
      expr           = "sum by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total{__SEL__}[15m]))"
      group          = "pods"
      operator       = "gt"
      pending_period = "1m"
      severity       = "critical"
      subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) restarted more than 5 times in 15 minutes."
      threshold      = 5
      title          = "Pod crash looping"
    }
    pod_pending = {
      expr           = "max by (namespace, pod) (kube_pod_status_phase{phase=\"Pending\",__SEL__})"
      group          = "pods"
      operator       = "gt"
      pending_period = "5m"
      severity       = "warning"
      subject        = "{{ $labels.pod }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.pod }} has been pending for 5 minutes. Check for unschedulable resources, taints or unbound volumes."
      threshold      = 0
      title          = "Pod stuck pending"
    }
    pod_waiting_failure = {
      expr           = "max by (namespace, pod, container, reason) (kube_pod_container_status_waiting_reason{reason=~\"CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|InvalidImageName\",__SEL__})"
      group          = "pods"
      operator       = "gt"
      pending_period = "5m"
      severity       = "critical"
      subject        = "{{ $labels.container }} in {{ $labels.namespace }} ({{ $labels.reason }})"
      summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) has been waiting in {{ $labels.reason }} for 5 minutes."
      threshold      = 0
      title          = "Pod cannot start"
    }

    # ── Workloads ─────────────────────────────────────────────────────────
    daemonset_not_ready = {
      expr           = "max by (namespace, daemonset) (kube_daemonset_status_desired_number_scheduled{__SEL__} - kube_daemonset_status_number_ready{__SEL__})"
      group          = "workloads"
      operator       = "gt"
      pending_period = "15m"
      severity       = "warning"
      subject        = "{{ $labels.daemonset }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.daemonset }} has had pods not ready for 15 minutes."
      threshold      = 0
      title          = "DaemonSet pods not ready"
    }
    deployment_rollout_stuck = {
      expr           = "max by (namespace, deployment) (kube_deployment_status_condition{condition=\"Progressing\",status=\"false\",__SEL__})"
      group          = "workloads"
      operator       = "gt"
      pending_period = "5m"
      severity       = "warning"
      subject        = "{{ $labels.deployment }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.deployment }} passed its progress deadline without finishing the rollout."
      threshold      = 0
      title          = "Deployment rollout stuck"
    }
    deployment_unavailable = {
      expr           = "max by (namespace, deployment) (kube_deployment_spec_replicas{__SEL__} > 0 unless on (namespace, deployment) kube_deployment_status_replicas_available{__SEL__} > 0)"
      group          = "workloads"
      operator       = "gt"
      pending_period = "5m"
      severity       = "critical"
      subject        = "{{ $labels.deployment }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.deployment }} wants replicas but has none available."
      threshold      = 0
      title          = "Deployment has no available replicas"
    }
    deployment_under_replicated = {
      expr           = "max by (namespace, deployment) (kube_deployment_spec_replicas{__SEL__} - kube_deployment_status_replicas_available{__SEL__})"
      group          = "workloads"
      operator       = "gt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ $labels.deployment }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.deployment }} has had fewer available replicas than desired for 10 minutes."
      threshold      = 0
      title          = "Deployment under-replicated"
    }
    hpa_at_max = {
      expr           = "max by (namespace, horizontalpodautoscaler) (kube_horizontalpodautoscaler_status_current_replicas{__SEL__} / kube_horizontalpodautoscaler_spec_max_replicas{__SEL__})"
      group          = "workloads"
      operator       = "gt"
      pending_period = "30m"
      severity       = "warning"
      subject        = "{{ $labels.horizontalpodautoscaler }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.horizontalpodautoscaler }} has run at its maximum replicas for 30 minutes and can't scale further."
      threshold      = 0.999
      title          = "HPA pinned at max replicas"
    }
    statefulset_under_replicated = {
      expr           = "max by (namespace, statefulset) (kube_statefulset_replicas{__SEL__} - kube_statefulset_status_replicas_ready{__SEL__})"
      group          = "workloads"
      operator       = "gt"
      pending_period = "15m"
      severity       = "warning"
      subject        = "{{ $labels.statefulset }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.statefulset }} has had fewer ready replicas than desired for 15 minutes."
      threshold      = 0
      title          = "StatefulSet under-replicated"
    }

    # ── Resources ─────────────────────────────────────────────────────────
    container_cpu_near_limit_critical = {
      expr           = "100 * max by (namespace, pod, container) (rate(container_cpu_usage_seconds_total{container!=\"\",__SEL__}[5m]) / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"cpu\",__SEL__})"
      group          = "resources"
      operator       = "gt"
      pending_period = "15m"
      severity       = "critical"
      subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its CPU limit."
      threshold      = 90
      title          = "Container CPU at limit"
    }
    container_cpu_near_limit_warning = {
      expr           = "100 * max by (namespace, pod, container) (rate(container_cpu_usage_seconds_total{container!=\"\",__SEL__}[5m]) / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"cpu\",__SEL__})"
      group          = "resources"
      operator       = "gt"
      pending_period = "15m"
      severity       = "warning"
      subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its CPU limit."
      threshold      = 80
      title          = "Container CPU near limit"
    }
    # Average usage hides throttling: a container can sit well under its
    # limit on average and still be throttled in most scheduler periods.
    container_cpu_throttled = {
      expr           = "100 * max by (namespace, pod, container) (increase(container_cpu_cfs_throttled_periods_total{container!=\"\",__SEL__}[5m]) / increase(container_cpu_cfs_periods_total{container!=\"\",__SEL__}[5m]))"
      group          = "resources"
      operator       = "gt"
      pending_period = "15m"
      severity       = "warning"
      subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) was throttled in {{ humanize $values.A.Value }}% of CPU periods."
      threshold      = 25
      title          = "Container CPU throttled"
    }
    container_ephemeral_storage_near_limit = {
      expr           = "100 * max by (namespace, pod, container) (container_fs_usage_bytes{container!=\"\",__SEL__} / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"ephemeral_storage\",__SEL__})"
      group          = "resources"
      operator       = "gt"
      pending_period = "5m"
      severity       = "critical"
      subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its ephemeral storage limit. The kubelet evicts it at 100%."
      threshold      = 80
      title          = "Container ephemeral storage near limit"
    }
    container_memory_near_limit_critical = {
      expr           = "100 * max by (namespace, pod, container) (container_memory_working_set_bytes{container!=\"\",__SEL__} / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"memory\",__SEL__})"
      group          = "resources"
      operator       = "gt"
      pending_period = "5m"
      severity       = "critical"
      subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its memory limit and will be OOM killed at 100%."
      threshold      = 90
      title          = "Container memory at limit"
    }
    container_memory_near_limit_warning = {
      expr           = "100 * max by (namespace, pod, container) (container_memory_working_set_bytes{container!=\"\",__SEL__} / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"memory\",__SEL__})"
      group          = "resources"
      operator       = "gt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its memory limit."
      threshold      = 80
      title          = "Container memory near limit"
    }
    pvc_near_full_critical = {
      expr           = "100 * max by (namespace, persistentvolumeclaim) (kubelet_volume_stats_used_bytes{__SEL__} / kubelet_volume_stats_capacity_bytes{__SEL__})"
      group          = "resources"
      operator       = "gt"
      pending_period = "5m"
      severity       = "critical"
      subject        = "{{ $labels.persistentvolumeclaim }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is {{ humanize $values.A.Value }}% full."
      threshold      = 90
      title          = "PersistentVolumeClaim critically full"
    }
    pvc_near_full_warning = {
      expr           = "100 * max by (namespace, persistentvolumeclaim) (kubelet_volume_stats_used_bytes{__SEL__} / kubelet_volume_stats_capacity_bytes{__SEL__})"
      group          = "resources"
      operator       = "gt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ $labels.persistentvolumeclaim }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is {{ humanize $values.A.Value }}% full."
      threshold      = 80
      title          = "PersistentVolumeClaim almost full"
    }

    # ── Nodes ─────────────────────────────────────────────────────────────
    node_disk_full = {
      expr           = "100 * max by (instance, mountpoint) (1 - node_filesystem_avail_bytes{fstype!~\"tmpfs|overlay|squashfs|ramfs\"} / node_filesystem_size_bytes{fstype!~\"tmpfs|overlay|squashfs|ramfs\"})"
      group          = "nodes"
      operator       = "gt"
      pending_period = "10m"
      severity       = "critical"
      subject        = "{{ $labels.mountpoint }} on {{ $labels.instance }}"
      summary        = "{{ $labels.mountpoint }} on {{ $labels.instance }} is {{ humanize $values.A.Value }}% full."
      threshold      = 85
      title          = "Node disk almost full"
    }
    node_memory_high = {
      expr           = "100 * max by (instance) (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)"
      group          = "nodes"
      operator       = "gt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ $labels.instance }}"
      summary        = "{{ $labels.instance }} is using {{ humanize $values.A.Value }}% of its memory."
      threshold      = 90
      title          = "Node memory high"
    }
    node_network_errors = {
      expr           = "max by (instance, device) (rate(node_network_receive_errs_total[5m]) + rate(node_network_transmit_errs_total[5m]))"
      group          = "nodes"
      operator       = "gt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ $labels.device }} on {{ $labels.instance }}"
      summary        = "{{ $labels.device }} on {{ $labels.instance }} has {{ humanize $values.A.Value }} receive/transmit errors per second."
      threshold      = 1
      title          = "Node network errors"
    }
    node_not_ready = {
      expr           = "max by (node) (kube_node_status_condition{condition=\"Ready\",status=~\"false|unknown\"})"
      group          = "nodes"
      operator       = "gt"
      pending_period = "2m"
      severity       = "critical"
      subject        = "{{ $labels.node }}"
      summary        = "Node {{ $labels.node }} has not been Ready for 2 minutes."
      threshold      = 0
      title          = "Node not ready"
    }
    node_pressure = {
      expr           = "max by (node, condition) (kube_node_status_condition{condition=~\"MemoryPressure|DiskPressure|PIDPressure\",status=\"true\"})"
      group          = "nodes"
      operator       = "gt"
      pending_period = "5m"
      severity       = "warning"
      subject        = "{{ $labels.node }} ({{ $labels.condition }})"
      summary        = "Node {{ $labels.node }} reports {{ $labels.condition }}. The kubelet may start evicting pods."
      threshold      = 0
      title          = "Node under resource pressure"
    }
    scrape_target_down = {
      expr           = "min by (job, namespace, instance) (up)"
      group          = "nodes"
      operator       = "lt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ $labels.job }}"
      summary        = "Prometheus can't scrape {{ $labels.job }} at {{ $labels.instance }}. Alerts that depend on it go quiet."
      threshold      = 1
      title          = "Metrics target down"
    }

    # ── Synthetics (blackbox exporter probes) ─────────────────────────────
    # These need blackbox exporter probes, such as modules/stack's
    # blackbox_exporter.targets. With no probes they have no data and stay quiet.
    synthetic_check_failing = {
      expr           = "min by (target, instance) (probe_success)"
      group          = "synthetics"
      operator       = "lt"
      pending_period = "2m"
      severity       = "critical"
      subject        = "{{ $labels.target }}"
      summary        = "{{ $labels.target }} ({{ $labels.instance }}) has failed its synthetic check for 2 minutes."
      threshold      = 1
      title          = "Synthetic check failing"
    }
    synthetic_check_slow = {
      expr           = "max by (target, instance) (probe_duration_seconds)"
      group          = "synthetics"
      operator       = "gt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ $labels.target }}"
      summary        = "{{ $labels.target }} ({{ $labels.instance }}) is taking {{ humanize $values.A.Value }}s to answer its synthetic check."
      threshold      = 5
      title          = "Synthetic check slow"
    }
    tls_certificate_expiring_critical = {
      expr           = "min by (target, instance) ((probe_ssl_earliest_cert_expiry - time()) / 86400)"
      group          = "synthetics"
      operator       = "lt"
      pending_period = "1h"
      severity       = "critical"
      subject        = "{{ $labels.target }}"
      summary        = "The TLS certificate for {{ $labels.target }} ({{ $labels.instance }}) expires in {{ humanize $values.A.Value }} days."
      threshold      = 3
      title          = "TLS certificate about to expire"
    }
    tls_certificate_expiring_warning = {
      expr           = "min by (target, instance) ((probe_ssl_earliest_cert_expiry - time()) / 86400)"
      group          = "synthetics"
      operator       = "lt"
      pending_period = "1h"
      severity       = "warning"
      subject        = "{{ $labels.target }}"
      summary        = "The TLS certificate for {{ $labels.target }} ({{ $labels.instance }}) expires in {{ humanize $values.A.Value }} days. Check that renewal is working."
      threshold      = 14
      title          = "TLS certificate expiring soon"
    }

    # ── Control plane (self-managed clusters only) ────────────────────────
    apiserver_errors = {
      expr           = "100 * sum(rate(apiserver_request_total{code=~\"5..\"}[5m])) / sum(rate(apiserver_request_total[5m]))"
      group          = "control-plane"
      operator       = "gt"
      pending_period = "10m"
      requires       = "apiserver"
      severity       = "critical"
      subject        = "API server"
      summary        = "{{ humanize $values.A.Value }}% of API server requests are failing with 5xx."
      threshold      = 5
      title          = "API server error rate high"
    }
    etcd_no_leader = {
      expr           = "min by (instance) (etcd_server_has_leader)"
      group          = "control-plane"
      operator       = "lt"
      pending_period = "1m"
      requires       = "etcd"
      severity       = "critical"
      subject        = "{{ $labels.instance }}"
      summary        = "etcd member {{ $labels.instance }} has no leader and can't serve requests."
      threshold      = 1
      title          = "etcd member has no leader"
    }
  }
}
