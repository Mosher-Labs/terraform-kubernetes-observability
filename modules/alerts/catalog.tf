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
    pod_not_ready = {
      # Running pods only: completed Job pods are never Ready, and pending or
      # failing-to-start pods have their own rules.
      expr           = "max by (namespace, pod) (kube_pod_status_ready{condition=\"false\",__SEL__}) * on (namespace, pod) max by (namespace, pod) (kube_pod_status_phase{phase=\"Running\",__SEL__})"
      group          = "pods"
      operator       = "gt"
      pending_period = "15m"
      severity       = "warning"
      subject        = "{{ $labels.pod }} in {{ $labels.namespace }}"
      summary        = "{{ $labels.namespace }}/{{ $labels.pod }} is running but has failed its readiness check for 15 minutes, so it gets no traffic."
      threshold      = 0
      title          = "Pod not ready"
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
    job_failed = {
      expr           = "max by (namespace, job_name) (kube_job_failed{condition=\"true\",__SEL__})"
      group          = "workloads"
      operator       = "gt"
      pending_period = "0s"
      severity       = "warning"
      subject        = "{{ $labels.job_name }} in {{ $labels.namespace }}"
      summary        = "Job {{ $labels.namespace }}/{{ $labels.job_name }} failed. Check its pods' logs; it stays failed until the Job is deleted or rerun."
      threshold      = 0
      title          = "Job failed"
    }
    job_not_completed = {
      expr           = "max by (namespace, job_name) (time() - kube_job_status_start_time{__SEL__} and on (namespace, job_name) kube_job_status_active{__SEL__} > 0)"
      group          = "workloads"
      operator       = "gt"
      pending_period = "0s"
      severity       = "warning"
      subject        = "{{ $labels.job_name }} in {{ $labels.namespace }}"
      summary        = "Job {{ $labels.namespace }}/{{ $labels.job_name }} has been running for {{ humanizeDuration $values.A.Value }}. It may be stuck."
      threshold      = 43200
      title          = "Job running too long"
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
    persistent_volume_errors = {
      expr           = "max by (persistentvolume, phase) (kube_persistentvolume_status_phase{phase=~\"Failed|Pending\"})"
      group          = "resources"
      operator       = "gt"
      pending_period = "5m"
      severity       = "critical"
      subject        = "{{ $labels.persistentvolume }} ({{ $labels.phase }})"
      summary        = "PersistentVolume {{ $labels.persistentvolume }} has been {{ $labels.phase }} for 5 minutes. Pods that use it can't start."
      threshold      = 0
      title          = "PersistentVolume failed"
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
    pvc_inodes_near_full = {
      expr           = "max by (namespace, persistentvolumeclaim) (100 * kubelet_volume_stats_inodes_used{__SEL__} / kubelet_volume_stats_inodes{__SEL__})"
      group          = "resources"
      operator       = "gt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ $labels.persistentvolumeclaim }} in {{ $labels.namespace }}"
      summary        = "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} has used {{ humanize $values.A.Value }}% of its inodes. New files fail at 100% even with free space."
      threshold      = 90
      title          = "PVC running out of inodes"
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
    node_clock_skew = {
      expr           = "max by (instance) (abs(node_timex_offset_seconds))"
      group          = "nodes"
      operator       = "gt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ $labels.instance }}"
      summary        = "{{ $labels.instance }}'s clock is {{ humanize $values.A.Value }}s off. Skew breaks TLS, tokens and log ordering; check NTP."
      threshold      = 0.05
      title          = "Node clock skewed"
    }
    node_clock_not_synchronising = {
      expr           = "min by (instance) (node_timex_sync_status)"
      group          = "nodes"
      operator       = "lt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ $labels.instance }}"
      summary        = "{{ $labels.instance }} isn't synchronising its clock with NTP."
      threshold      = 1
      title          = "Node clock not synchronising"
    }
    node_inodes_low = {
      expr           = "max by (instance, mountpoint) (100 * (1 - node_filesystem_files_free{fstype!~\"tmpfs|overlay|squashfs|nsfs|ramfs\"} / (node_filesystem_files{fstype!~\"tmpfs|overlay|squashfs|nsfs|ramfs\"} > 0)))"
      group          = "nodes"
      operator       = "gt"
      pending_period = "10m"
      severity       = "warning"
      subject        = "{{ $labels.instance }} {{ $labels.mountpoint }}"
      summary        = "{{ $labels.mountpoint }} on {{ $labels.instance }} has used {{ humanize $values.A.Value }}% of its inodes. New files fail at 100% even with free space."
      threshold      = 90
      title          = "Node running out of inodes"
    }
    kubelet_certificate_expiring = {
      # Needs the kubelet's certificate manager metrics. k3s doesn't expose
      # them, so there this rule has no data and stays quiet.
      expr           = "min by (node) (kubelet_certificate_manager_client_ttl_seconds or kubelet_certificate_manager_server_ttl_seconds)"
      group          = "nodes"
      operator       = "lt"
      pending_period = "15m"
      severity       = "warning"
      subject        = "{{ $labels.node }}"
      summary        = "A kubelet certificate on {{ $labels.node }} expires in {{ humanizeDuration $values.A.Value }}."
      threshold      = 604800
      title          = "Kubelet certificate expiring"
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
    node_readiness_flapping = {
      expr           = "sum by (node) (changes(kube_node_status_condition{condition=\"Ready\",status=\"true\"}[15m]))"
      group          = "nodes"
      operator       = "gt"
      pending_period = "0s"
      severity       = "warning"
      subject        = "{{ $labels.node }}"
      summary        = "Node {{ $labels.node }} changed Ready state {{ humanize $values.A.Value }} times in 15 minutes. Check its network and kubelet."
      threshold      = 2
      title          = "Node readiness flapping"
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
    node_systemd_service_failed = {
      # Needs node-exporter's systemd collector (--collector.systemd), which
      # is off by default. Without it this rule has no data and stays quiet.
      expr           = "max by (instance, name) (node_systemd_unit_state{state=\"failed\"})"
      group          = "nodes"
      operator       = "gt"
      pending_period = "5m"
      severity       = "warning"
      subject        = "{{ $labels.name }} on {{ $labels.instance }}"
      summary        = "systemd unit {{ $labels.name }} on {{ $labels.instance }} has failed."
      threshold      = 0
      title          = "systemd service failed"
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

    # ── Alerting (the notification pipeline itself) ───────────────────────
    # Grafana counts failed deliveries per integration. With more than one
    # channel, a failure in one is reported through the others.
    notification_delivery_failing = {
      expr           = "sum by (integration) (increase(grafana_alerting_notifications_failed_total[15m]))"
      group          = "alerting"
      operator       = "gt"
      pending_period = "0s"
      severity       = "warning"
      subject        = "{{ $labels.integration }}"
      summary        = "Grafana failed to deliver {{ humanize $values.A.Value }} notifications through {{ $labels.integration }} in the last 15 minutes. Check that channel's URL or token."
      threshold      = 0
      title          = "Notification delivery failing"
    }
    # Prometheus health. The heartbeat queries vector(1), which still works
    # when Prometheus stops ingesting, so these catch what it can't.
    prometheus_config_reload_failed = {
      expr           = "min by (instance) (prometheus_config_last_reload_successful)"
      group          = "alerting"
      operator       = "lt"
      pending_period = "10m"
      severity       = "critical"
      subject        = "{{ $labels.instance }}"
      summary        = "Prometheus {{ $labels.instance }} failed to reload its configuration and is running the previous one."
      threshold      = 1
      title          = "Prometheus config reload failed"
    }
    prometheus_not_ingesting = {
      expr           = "sum by (instance) (rate(prometheus_tsdb_head_samples_appended_total[5m]))"
      group          = "alerting"
      operator       = "lt"
      pending_period = "10m"
      severity       = "critical"
      subject        = "{{ $labels.instance }}"
      summary        = "Prometheus {{ $labels.instance }} has stopped ingesting samples. Every metric alert is blind."
      threshold      = 1
      title          = "Prometheus not ingesting"
    }
    prometheus_rule_failures = {
      expr           = "sum by (instance, rule_group) (increase(prometheus_rule_evaluation_failures_total[5m]))"
      group          = "alerting"
      operator       = "gt"
      pending_period = "15m"
      severity       = "warning"
      subject        = "{{ $labels.rule_group }}"
      summary        = "Prometheus rules in {{ $labels.rule_group }} are failing to evaluate, so the recording rules they feed are stale."
      threshold      = 0
      title          = "Prometheus rule failures"
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
    apiserver_client_certificate_expiring = {
      # The soonest-expiring 1% of certificates clients presented to the API
      # server. k3s rotates its certificates on restart within 90 days of
      # expiry.
      expr           = "histogram_quantile(0.01, sum by (job, le) (rate(apiserver_client_certificate_expiration_seconds_bucket[5m])))"
      group          = "control-plane"
      operator       = "lt"
      pending_period = "15m"
      requires       = "apiserver"
      severity       = "warning"
      subject        = "API server clients"
      summary        = "A client certificate used with the API server expires in {{ humanizeDuration $values.A.Value }}."
      threshold      = 604800
      title          = "Client certificate expiring"
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
