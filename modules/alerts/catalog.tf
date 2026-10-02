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
    pod_crash_looping = {
      group     = "pods"
      title     = "Pod crash looping"
      expr      = "sum by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total{__SEL__}[15m]))"
      operator  = "gt"
      threshold = 5
      for       = "1m"
      severity  = "critical"
      summary   = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) restarted more than 5 times in 15 minutes."
    }
    container_oom_killed = {
      group     = "pods"
      title     = "Container OOM killed"
      expr      = "sum by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total{__SEL__}[15m]) > 0 and on (namespace, pod, container) kube_pod_container_status_last_terminated_reason{reason=\"OOMKilled\",__SEL__} == 1)"
      operator  = "gt"
      threshold = 0
      for       = "0s"
      severity  = "warning"
      summary   = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) was OOM killed in the last 15 minutes. Raise its memory limit or find the leak."
    }
    pod_waiting_failure = {
      group     = "pods"
      title     = "Pod cannot start"
      expr      = "max by (namespace, pod, container, reason) (kube_pod_container_status_waiting_reason{reason=~\"CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|InvalidImageName\",__SEL__})"
      operator  = "gt"
      threshold = 0
      for       = "5m"
      severity  = "critical"
      summary   = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) has been waiting in {{ $labels.reason }} for 5 minutes."
    }
    pod_pending = {
      group     = "pods"
      title     = "Pod stuck pending"
      expr      = "max by (namespace, pod) (kube_pod_status_phase{phase=\"Pending\",__SEL__})"
      operator  = "gt"
      threshold = 0
      for       = "5m"
      severity  = "warning"
      summary   = "{{ $labels.namespace }}/{{ $labels.pod }} has been pending for 5 minutes. Check for unschedulable resources, taints or unbound volumes."
    }

    # ── Workloads ─────────────────────────────────────────────────────────
    deployment_unavailable = {
      group     = "workloads"
      title     = "Deployment has no available replicas"
      expr      = "max by (namespace, deployment) (kube_deployment_spec_replicas{__SEL__} > 0 unless on (namespace, deployment) kube_deployment_status_replicas_available{__SEL__} > 0)"
      operator  = "gt"
      threshold = 0
      for       = "5m"
      severity  = "critical"
      summary   = "{{ $labels.namespace }}/{{ $labels.deployment }} wants replicas but has none available."
    }
    deployment_under_replicated = {
      group     = "workloads"
      title     = "Deployment under-replicated"
      expr      = "max by (namespace, deployment) (kube_deployment_spec_replicas{__SEL__} - kube_deployment_status_replicas_available{__SEL__})"
      operator  = "gt"
      threshold = 0
      for       = "10m"
      severity  = "warning"
      summary   = "{{ $labels.namespace }}/{{ $labels.deployment }} has had fewer available replicas than desired for 10 minutes."
    }
    deployment_rollout_stuck = {
      group     = "workloads"
      title     = "Deployment rollout stuck"
      expr      = "max by (namespace, deployment) (kube_deployment_status_condition{condition=\"Progressing\",status=\"false\",__SEL__})"
      operator  = "gt"
      threshold = 0
      for       = "5m"
      severity  = "warning"
      summary   = "{{ $labels.namespace }}/{{ $labels.deployment }} passed its progress deadline without finishing the rollout."
    }
    statefulset_under_replicated = {
      group     = "workloads"
      title     = "StatefulSet under-replicated"
      expr      = "max by (namespace, statefulset) (kube_statefulset_replicas{__SEL__} - kube_statefulset_status_replicas_ready{__SEL__})"
      operator  = "gt"
      threshold = 0
      for       = "15m"
      severity  = "warning"
      summary   = "{{ $labels.namespace }}/{{ $labels.statefulset }} has had fewer ready replicas than desired for 15 minutes."
    }
    daemonset_not_ready = {
      group     = "workloads"
      title     = "DaemonSet pods not ready"
      expr      = "max by (namespace, daemonset) (kube_daemonset_status_desired_number_scheduled{__SEL__} - kube_daemonset_status_number_ready{__SEL__})"
      operator  = "gt"
      threshold = 0
      for       = "15m"
      severity  = "warning"
      summary   = "{{ $labels.namespace }}/{{ $labels.daemonset }} has had pods not ready for 15 minutes."
    }
    hpa_at_max = {
      group     = "workloads"
      title     = "HPA pinned at max replicas"
      expr      = "max by (namespace, horizontalpodautoscaler) (kube_horizontalpodautoscaler_status_current_replicas{__SEL__} / kube_horizontalpodautoscaler_spec_max_replicas{__SEL__})"
      operator  = "gt"
      threshold = 0.999
      for       = "30m"
      severity  = "warning"
      summary   = "{{ $labels.namespace }}/{{ $labels.horizontalpodautoscaler }} has run at its maximum replicas for 30 minutes and can't scale further."
    }

    # ── Resources ─────────────────────────────────────────────────────────
    container_memory_near_limit_warning = {
      group     = "resources"
      title     = "Container memory near limit"
      expr      = "100 * max by (namespace, pod, container) (container_memory_working_set_bytes{container!=\"\",__SEL__} / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"memory\",__SEL__})"
      operator  = "gt"
      threshold = 80
      for       = "10m"
      severity  = "warning"
      summary   = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its memory limit."
    }
    container_memory_near_limit_critical = {
      group     = "resources"
      title     = "Container memory at limit"
      expr      = "100 * max by (namespace, pod, container) (container_memory_working_set_bytes{container!=\"\",__SEL__} / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"memory\",__SEL__})"
      operator  = "gt"
      threshold = 90
      for       = "5m"
      severity  = "critical"
      summary   = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its memory limit and will be OOM killed at 100%."
    }
    container_cpu_near_limit_warning = {
      group     = "resources"
      title     = "Container CPU near limit"
      expr      = "100 * max by (namespace, pod, container) (rate(container_cpu_usage_seconds_total{container!=\"\",__SEL__}[5m]) / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"cpu\",__SEL__})"
      operator  = "gt"
      threshold = 80
      for       = "15m"
      severity  = "warning"
      summary   = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its CPU limit."
    }
    container_cpu_near_limit_critical = {
      group     = "resources"
      title     = "Container CPU at limit"
      expr      = "100 * max by (namespace, pod, container) (rate(container_cpu_usage_seconds_total{container!=\"\",__SEL__}[5m]) / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"cpu\",__SEL__})"
      operator  = "gt"
      threshold = 90
      for       = "15m"
      severity  = "critical"
      summary   = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its CPU limit."
    }
    # Average usage hides throttling: a container can sit well under its
    # limit on average and still be throttled in most scheduler periods.
    container_cpu_throttled = {
      group     = "resources"
      title     = "Container CPU throttled"
      expr      = "100 * max by (namespace, pod, container) (increase(container_cpu_cfs_throttled_periods_total{container!=\"\",__SEL__}[5m]) / increase(container_cpu_cfs_periods_total{container!=\"\",__SEL__}[5m]))"
      operator  = "gt"
      threshold = 25
      for       = "15m"
      severity  = "warning"
      summary   = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) was throttled in {{ humanize $values.A.Value }}% of CPU periods."
    }
    container_ephemeral_storage_near_limit = {
      group     = "resources"
      title     = "Container ephemeral storage near limit"
      expr      = "100 * max by (namespace, pod, container) (container_fs_usage_bytes{container!=\"\",__SEL__} / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"ephemeral_storage\",__SEL__})"
      operator  = "gt"
      threshold = 80
      for       = "5m"
      severity  = "critical"
      summary   = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its ephemeral storage limit. The kubelet evicts it at 100%."
    }
    pvc_near_full_warning = {
      group     = "resources"
      title     = "PersistentVolumeClaim almost full"
      expr      = "100 * max by (namespace, persistentvolumeclaim) (kubelet_volume_stats_used_bytes{__SEL__} / kubelet_volume_stats_capacity_bytes{__SEL__})"
      operator  = "gt"
      threshold = 80
      for       = "10m"
      severity  = "warning"
      summary   = "{{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is {{ humanize $values.A.Value }}% full."
    }
    pvc_near_full_critical = {
      group     = "resources"
      title     = "PersistentVolumeClaim critically full"
      expr      = "100 * max by (namespace, persistentvolumeclaim) (kubelet_volume_stats_used_bytes{__SEL__} / kubelet_volume_stats_capacity_bytes{__SEL__})"
      operator  = "gt"
      threshold = 90
      for       = "5m"
      severity  = "critical"
      summary   = "{{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is {{ humanize $values.A.Value }}% full."
    }

    # ── Nodes ─────────────────────────────────────────────────────────────
    node_not_ready = {
      group     = "nodes"
      title     = "Node not ready"
      expr      = "max by (node) (kube_node_status_condition{condition=\"Ready\",status=~\"false|unknown\"})"
      operator  = "gt"
      threshold = 0
      for       = "2m"
      severity  = "critical"
      summary   = "Node {{ $labels.node }} has not been Ready for 2 minutes."
    }
    node_pressure = {
      group     = "nodes"
      title     = "Node under resource pressure"
      expr      = "max by (node, condition) (kube_node_status_condition{condition=~\"MemoryPressure|DiskPressure|PIDPressure\",status=\"true\"})"
      operator  = "gt"
      threshold = 0
      for       = "5m"
      severity  = "warning"
      summary   = "Node {{ $labels.node }} reports {{ $labels.condition }}. The kubelet may start evicting pods."
    }
    node_disk_full = {
      group     = "nodes"
      title     = "Node disk almost full"
      expr      = "100 * max by (instance, mountpoint) (1 - node_filesystem_avail_bytes{fstype!~\"tmpfs|overlay|squashfs|ramfs\"} / node_filesystem_size_bytes{fstype!~\"tmpfs|overlay|squashfs|ramfs\"})"
      operator  = "gt"
      threshold = 85
      for       = "10m"
      severity  = "critical"
      summary   = "{{ $labels.mountpoint }} on {{ $labels.instance }} is {{ humanize $values.A.Value }}% full."
    }
    node_memory_high = {
      group     = "nodes"
      title     = "Node memory high"
      expr      = "100 * max by (instance) (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)"
      operator  = "gt"
      threshold = 90
      for       = "10m"
      severity  = "warning"
      summary   = "{{ $labels.instance }} is using {{ humanize $values.A.Value }}% of its memory."
    }
    node_network_errors = {
      group     = "nodes"
      title     = "Node network errors"
      expr      = "max by (instance, device) (rate(node_network_receive_errs_total[5m]) + rate(node_network_transmit_errs_total[5m]))"
      operator  = "gt"
      threshold = 1
      for       = "10m"
      severity  = "warning"
      summary   = "{{ $labels.device }} on {{ $labels.instance }} has {{ humanize $values.A.Value }} receive/transmit errors per second."
    }
    scrape_target_down = {
      group     = "nodes"
      title     = "Metrics target down"
      expr      = "min by (job, namespace, instance) (up)"
      operator  = "lt"
      threshold = 1
      for       = "10m"
      severity  = "warning"
      summary   = "Prometheus can't scrape {{ $labels.job }} at {{ $labels.instance }}. Alerts that depend on it go quiet."
    }

    # ── Control plane (self-managed clusters only) ────────────────────────
    apiserver_errors = {
      group     = "control-plane"
      title     = "API server error rate high"
      expr      = "100 * sum(rate(apiserver_request_total{code=~\"5..\"}[5m])) / sum(rate(apiserver_request_total[5m]))"
      operator  = "gt"
      threshold = 5
      for       = "10m"
      severity  = "critical"
      summary   = "{{ humanize $values.A.Value }}% of API server requests are failing with 5xx."
      requires  = "apiserver"
    }
    etcd_no_leader = {
      group     = "control-plane"
      title     = "etcd member has no leader"
      expr      = "min by (instance) (etcd_server_has_leader)"
      operator  = "lt"
      threshold = 1
      for       = "1m"
      severity  = "critical"
      summary   = "etcd member {{ $labels.instance }} has no leader and can't serve requests."
      requires  = "etcd"
    }
  }
}
