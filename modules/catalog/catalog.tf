# The alert catalog. Each rule is written once, here: the fields every backend
# shares sit at the top of the rule, and each backend has a block of its own.
#
#   pod_crash_looping = {
#     datadog = { query = "...", summary = "...", window = "last_15m" }
#     grafana = { expr = "...", pending_period = "1m", subject = "...", summary = "..." }
#     group     = "pods"
#     operator  = "gt"
#     severity  = "critical"
#     threshold = 5
#     title     = "Pod crash looping"
#     workload  = true
#   }
#
# Shared fields: group, operator, severity, threshold and title are required.
# `requires` names what turns the rule on (apiserver, etcd, apm, or a backing
# service). `workload = true` marks a rule the workload scope applies to.
#
# A backend block holds that backend's query, summary and timing:
#   grafana: expr (PromQL, evaluated as an instant query), pending_period,
#            subject, summary
#   datadog: query, summary, window, and where needed type ("service check"),
#            require_full_window and on_missing_data
# The threshold stays out of the query, so overrides can change it. Datadog
# queries stop before the comparison: the renderer adds the operator and the
# threshold.
#
# A block may repeat a shared field to replace it for that backend. Say why in
# a comment, and add the rule to the list in tests/catalog.tftest.hcl.
#
# A backend that can't express a rule gets `skip = "reason"` in place of a
# query. Every rule needs a block or a skip for both backends: the check in
# checks.tf and the tests fail otherwise.
#
# Placeholders in queries and text, filled in by locals.tf:
#   __SEL__    workload scope (grafana), in the forms {__SEL__} and ,__SEL__}
#   __BSEL__   backing-service scope (grafana), same forms
#   __SCOPE__  cluster tag plus the workload or backing-service scope (datadog)
#   __WINDOW__ the window after overrides (datadog)
#   __TAGS__, __LAST__  service checks: the cluster tag, and the number of
#              check runs to look back over, which is the threshold plus one
# The APM rules add placeholders of their own, listed in catalog_apm.tf.
#
# Rule IDs are part of the interface: callers use them in `overrides` and
# `disabled_rules`. Renaming or removing one is a breaking change.
#
# Keep the threshold out of the query, so no data counts as healthy, and
# prefer increase() or rate() over cumulative counters. Rules are alphabetical
# within each section.
locals {
  core_rules = {
    # ── Pods ──────────────────────────────────────────────────────────────
    container_oom_killed = {
      datadog = {
        query               = "sum(__WINDOW__):default_zero(diff(max:kubernetes_state.container.restarts{__SCOPE__} by {kube_namespace,pod_name,kube_container_name})) * default_zero(max:kubernetes.containers.last_state.terminated{reason:oomkilled AND __SCOPE__} by {kube_namespace,pod_name,kube_container_name})"
        require_full_window = false
        summary             = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) was OOM killed in the last 15 minutes. Raise its memory limit or find the leak."
        window              = "last_15m"
      }
      grafana = {
        expr           = "sum by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total{__SEL__}[15m]) > 0 and on (namespace, pod, container) kube_pod_container_status_last_terminated_reason{reason=\"OOMKilled\",__SEL__} == 1)"
        pending_period = "0s"
        subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) was OOM killed in the last 15 minutes. Raise its memory limit or find the leak."
      }
      group     = "pods"
      operator  = "gt"
      severity  = "warning"
      threshold = 0
      title     = "Container OOM killed"
      workload  = true
    }
    pod_crash_looping = {
      datadog = {
        query               = "sum(__WINDOW__):default_zero(diff(max:kubernetes_state.container.restarts{__SCOPE__} by {kube_namespace,pod_name,kube_container_name}))"
        require_full_window = false
        summary             = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) restarted {{value}} times in 15 minutes."
        window              = "last_15m"
      }
      grafana = {
        expr           = "sum by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total{__SEL__}[15m]))"
        pending_period = "1m"
        subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) restarted more than 5 times in 15 minutes."
      }
      group     = "pods"
      operator  = "gt"
      severity  = "critical"
      threshold = 5
      title     = "Pod crash looping"
      workload  = true
    }
    pod_not_ready = {
      # Running pods that fail their readiness check, so they get no traffic.
      datadog = {
        query   = "min(__WINDOW__):default_zero(max:kubernetes_state.pod.ready{condition:false AND __SCOPE__} by {kube_namespace,pod_name}) * default_zero(max:kubernetes_state.pod.status_phase{pod_phase:running AND __SCOPE__} by {kube_namespace,pod_name})"
        summary = "{{kube_namespace.name}}/{{pod_name.name}} is running but has failed its readiness check for 15 minutes, so it gets no traffic."
        window  = "last_15m"
      }
      grafana = {
        # Running pods only: completed Job pods are never Ready, and pending or
        # failing-to-start pods have their own rules.
        expr           = "max by (namespace, pod) (kube_pod_status_ready{condition=\"false\",__SEL__}) * on (namespace, pod) max by (namespace, pod) (kube_pod_status_phase{phase=\"Running\",__SEL__})"
        pending_period = "15m"
        subject        = "{{ $labels.pod }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.pod }} is running but has failed its readiness check for 15 minutes, so it gets no traffic."
      }
      group     = "pods"
      operator  = "gt"
      severity  = "warning"
      threshold = 0
      title     = "Pod not ready"
      workload  = true
    }
    pod_pending = {
      datadog = {
        query   = "min(__WINDOW__):default_zero(max:kubernetes_state.pod.status_phase{pod_phase:pending AND __SCOPE__} by {kube_namespace,pod_name})"
        summary = "{{kube_namespace.name}}/{{pod_name.name}} has been pending for 5 minutes. Check for unschedulable resources, taints or unbound volumes."
        window  = "last_5m"
      }
      grafana = {
        expr           = "max by (namespace, pod) (kube_pod_status_phase{phase=\"Pending\",__SEL__})"
        pending_period = "5m"
        subject        = "{{ $labels.pod }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.pod }} has been pending for 5 minutes. Check for unschedulable resources, taints or unbound volumes."
      }
      group     = "pods"
      operator  = "gt"
      severity  = "warning"
      threshold = 0
      title     = "Pod stuck pending"
      workload  = true
    }
    pod_waiting_failure = {
      datadog = {
        query   = "min(__WINDOW__):default_zero(max:kubernetes_state.container.status_report.count.waiting{reason IN (crashloopbackoff,imagepullbackoff,errimagepull,createcontainerconfigerror,invalidimagename) AND __SCOPE__} by {kube_namespace,pod_name,kube_container_name,reason})"
        summary = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) has been waiting in {{reason.name}} for 5 minutes."
        window  = "last_5m"
      }
      grafana = {
        expr           = "max by (namespace, pod, container, reason) (kube_pod_container_status_waiting_reason{reason=~\"CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|InvalidImageName\",__SEL__})"
        pending_period = "5m"
        subject        = "{{ $labels.container }} in {{ $labels.namespace }} ({{ $labels.reason }})"
        summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) has been waiting in {{ $labels.reason }} for 5 minutes."
      }
      group     = "pods"
      operator  = "gt"
      severity  = "critical"
      threshold = 0
      title     = "Pod cannot start"
      workload  = true
    }

    # ── Workloads ─────────────────────────────────────────────────────────
    daemonset_not_ready = {
      datadog = {
        query   = "min(__WINDOW__):max:kubernetes_state.daemonset.desired{__SCOPE__} by {kube_namespace,kube_daemon_set} - max:kubernetes_state.daemonset.ready{__SCOPE__} by {kube_namespace,kube_daemon_set}"
        summary = "{{kube_namespace.name}}/{{kube_daemon_set.name}} has had pods not ready for 15 minutes."
        window  = "last_15m"
      }
      grafana = {
        expr           = "max by (namespace, daemonset) (kube_daemonset_status_desired_number_scheduled{__SEL__} - kube_daemonset_status_number_ready{__SEL__})"
        pending_period = "15m"
        subject        = "{{ $labels.daemonset }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.daemonset }} has had pods not ready for 15 minutes."
      }
      group     = "workloads"
      operator  = "gt"
      severity  = "warning"
      threshold = 0
      title     = "DaemonSet pods not ready"
      workload  = true
    }
    deployment_rollout_stuck = {
      datadog = {
        query   = "min(__WINDOW__):default_zero(max:kubernetes_state.deployment.condition{condition:progressing AND status:false AND __SCOPE__} by {kube_namespace,kube_deployment})"
        summary = "{{kube_namespace.name}}/{{kube_deployment.name}} passed its progress deadline without finishing the rollout."
        window  = "last_5m"
      }
      grafana = {
        expr           = "max by (namespace, deployment) (kube_deployment_status_condition{condition=\"Progressing\",status=\"false\",__SEL__})"
        pending_period = "5m"
        subject        = "{{ $labels.deployment }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.deployment }} passed its progress deadline without finishing the rollout."
      }
      group     = "workloads"
      operator  = "gt"
      severity  = "warning"
      threshold = 0
      title     = "Deployment rollout stuck"
      workload  = true
    }
    deployment_unavailable = {
      # The fraction of desired replicas that are unavailable: 1 when none are
      # available. A deployment scaled to zero divides by zero and has no data.
      datadog = {
        query   = "min(__WINDOW__):(max:kubernetes_state.deployment.replicas_desired{__SCOPE__} by {kube_namespace,kube_deployment} - max:kubernetes_state.deployment.replicas_available{__SCOPE__} by {kube_namespace,kube_deployment}) / max:kubernetes_state.deployment.replicas_desired{__SCOPE__} by {kube_namespace,kube_deployment}"
        summary = "{{kube_namespace.name}}/{{kube_deployment.name}} wants replicas but has none available."
        # The fraction of desired replicas that are unavailable, so 1 means none are
        # available.
        threshold = 0.99
        window    = "last_5m"
      }
      grafana = {
        expr           = "max by (namespace, deployment) (kube_deployment_spec_replicas{__SEL__} > 0 unless on (namespace, deployment) kube_deployment_status_replicas_available{__SEL__} > 0)"
        pending_period = "5m"
        subject        = "{{ $labels.deployment }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.deployment }} wants replicas but has none available."
      }
      group     = "workloads"
      operator  = "gt"
      severity  = "critical"
      threshold = 0
      title     = "Deployment has no available replicas"
      workload  = true
    }
    deployment_under_replicated = {
      datadog = {
        query   = "min(__WINDOW__):max:kubernetes_state.deployment.replicas_desired{__SCOPE__} by {kube_namespace,kube_deployment} - max:kubernetes_state.deployment.replicas_available{__SCOPE__} by {kube_namespace,kube_deployment}"
        summary = "{{kube_namespace.name}}/{{kube_deployment.name}} has had fewer available replicas than desired for 10 minutes."
        window  = "last_10m"
      }
      grafana = {
        expr           = "max by (namespace, deployment) (kube_deployment_spec_replicas{__SEL__} - kube_deployment_status_replicas_available{__SEL__})"
        pending_period = "10m"
        subject        = "{{ $labels.deployment }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.deployment }} has had fewer available replicas than desired for 10 minutes."
      }
      group     = "workloads"
      operator  = "gt"
      severity  = "warning"
      threshold = 0
      title     = "Deployment under-replicated"
      workload  = true
    }
    hpa_at_max = {
      datadog = {
        query   = "min(__WINDOW__):max:kubernetes_state.hpa.current_replicas{__SCOPE__} by {kube_namespace,horizontalpodautoscaler} / max:kubernetes_state.hpa.max_replicas{__SCOPE__} by {kube_namespace,horizontalpodautoscaler}"
        summary = "{{kube_namespace.name}}/{{horizontalpodautoscaler.name}} has run at its maximum replicas for 30 minutes and can't scale further."
        window  = "last_30m"
      }
      grafana = {
        expr           = "max by (namespace, horizontalpodautoscaler) (kube_horizontalpodautoscaler_status_current_replicas{__SEL__} / kube_horizontalpodautoscaler_spec_max_replicas{__SEL__})"
        pending_period = "30m"
        subject        = "{{ $labels.horizontalpodautoscaler }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.horizontalpodautoscaler }} has run at its maximum replicas for 30 minutes and can't scale further."
      }
      group     = "workloads"
      operator  = "gt"
      severity  = "warning"
      threshold = 0.999
      title     = "HPA pinned at max replicas"
      workload  = true
    }
    job_failed = {
      datadog = {
        query               = "max(__WINDOW__):default_zero(max:kubernetes_state.job.completion.failed{__SCOPE__} by {kube_namespace,kube_job})"
        require_full_window = false
        summary             = "Job {{kube_namespace.name}}/{{kube_job.name}} failed. Check its pods' logs; it stays failed until the Job is deleted or rerun."
        window              = "last_5m"
      }
      grafana = {
        expr           = "max by (namespace, job_name) (kube_job_failed{condition=\"true\",__SEL__})"
        pending_period = "0s"
        subject        = "{{ $labels.job_name }} in {{ $labels.namespace }}"
        summary        = "Job {{ $labels.namespace }}/{{ $labels.job_name }} failed. Check its pods' logs; it stays failed until the Job is deleted or rerun."
      }
      group     = "workloads"
      operator  = "gt"
      severity  = "warning"
      threshold = 0
      title     = "Job failed"
      workload  = true
    }
    job_not_completed = {
      # Multiplying by active / active keeps the duration while the Job has
      # active pods and leaves a gap once it finishes.
      datadog = {
        query               = "max(__WINDOW__):max:kubernetes_state.job.duration{__SCOPE__} by {kube_namespace,kube_job} * max:kubernetes_state.job.active{__SCOPE__} by {kube_namespace,kube_job} / max:kubernetes_state.job.active{__SCOPE__} by {kube_namespace,kube_job}"
        require_full_window = false
        summary             = "Job {{kube_namespace.name}}/{{kube_job.name}} has been running for {{value}}s. It may be stuck."
        window              = "last_5m"
      }
      grafana = {
        expr           = "max by (namespace, job_name) (time() - kube_job_status_start_time{__SEL__} and on (namespace, job_name) kube_job_status_active{__SEL__} > 0)"
        pending_period = "0s"
        subject        = "{{ $labels.job_name }} in {{ $labels.namespace }}"
        summary        = "Job {{ $labels.namespace }}/{{ $labels.job_name }} has been running for {{ humanizeDuration $values.A.Value }}. It may be stuck."
      }
      group     = "workloads"
      operator  = "gt"
      severity  = "warning"
      threshold = 43200
      title     = "Job running too long"
      workload  = true
    }
    statefulset_under_replicated = {
      datadog = {
        query   = "min(__WINDOW__):max:kubernetes_state.statefulset.replicas_desired{__SCOPE__} by {kube_namespace,kube_stateful_set} - max:kubernetes_state.statefulset.replicas_ready{__SCOPE__} by {kube_namespace,kube_stateful_set}"
        summary = "{{kube_namespace.name}}/{{kube_stateful_set.name}} has had fewer ready replicas than desired for 15 minutes."
        window  = "last_15m"
      }
      grafana = {
        expr           = "max by (namespace, statefulset) (kube_statefulset_replicas{__SEL__} - kube_statefulset_status_replicas_ready{__SEL__})"
        pending_period = "15m"
        subject        = "{{ $labels.statefulset }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.statefulset }} has had fewer ready replicas than desired for 15 minutes."
      }
      group     = "workloads"
      operator  = "gt"
      severity  = "warning"
      threshold = 0
      title     = "StatefulSet under-replicated"
      workload  = true
    }

    # ── Resources ─────────────────────────────────────────────────────────
    container_cpu_near_limit_critical = {
      # kubernetes.cpu.usage.total is in nanocores and kubernetes.cpu.limits in
      # cores.
      datadog = {
        query   = "min(__WINDOW__):100 * max:kubernetes.cpu.usage.total{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} / (max:kubernetes.cpu.limits{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} * 1000000000)"
        summary = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) is using {{value}}% of its CPU limit."
        window  = "last_15m"
      }
      grafana = {
        expr           = "100 * max by (namespace, pod, container) (rate(container_cpu_usage_seconds_total{container!=\"\",__SEL__}[5m]) / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"cpu\",__SEL__})"
        pending_period = "15m"
        subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its CPU limit."
      }
      group     = "resources"
      operator  = "gt"
      severity  = "critical"
      threshold = 90
      title     = "Container CPU at limit"
      workload  = true
    }
    container_cpu_near_limit_warning = {
      datadog = {
        query   = "min(__WINDOW__):100 * max:kubernetes.cpu.usage.total{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} / (max:kubernetes.cpu.limits{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} * 1000000000)"
        summary = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) is using {{value}}% of its CPU limit."
        window  = "last_15m"
      }
      grafana = {
        expr           = "100 * max by (namespace, pod, container) (rate(container_cpu_usage_seconds_total{container!=\"\",__SEL__}[5m]) / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"cpu\",__SEL__})"
        pending_period = "15m"
        subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its CPU limit."
      }
      group     = "resources"
      operator  = "gt"
      severity  = "warning"
      threshold = 80
      title     = "Container CPU near limit"
      workload  = true
    }
    container_cpu_throttled = {
      datadog = {
        query   = "min(__WINDOW__):100 * max:kubernetes.cpu.cfs.throttled.periods{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} / max:kubernetes.cpu.cfs.periods{__SCOPE__} by {kube_namespace,pod_name,kube_container_name}"
        summary = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) was throttled in {{value}}% of CPU periods."
        window  = "last_15m"
      }
      # Average usage hides throttling: a container can sit well under its
      # limit on average and still be throttled in most scheduler periods.
      grafana = {
        expr           = "100 * max by (namespace, pod, container) (increase(container_cpu_cfs_throttled_periods_total{container!=\"\",__SEL__}[5m]) / increase(container_cpu_cfs_periods_total{container!=\"\",__SEL__}[5m]))"
        pending_period = "15m"
        subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) was throttled in {{ humanize $values.A.Value }}% of CPU periods."
      }
      group     = "resources"
      operator  = "gt"
      severity  = "warning"
      threshold = 25
      title     = "Container CPU throttled"
      workload  = true
    }
    container_ephemeral_storage_near_limit = {
      # The kubelet reports ephemeral storage per pod, not per container.
      datadog = {
        query   = "min(__WINDOW__):100 * max:kubernetes.ephemeral_storage.usage{__SCOPE__} by {kube_namespace,pod_name} / max:kubernetes.ephemeral_storage.limits{__SCOPE__} by {kube_namespace,pod_name}"
        summary = "{{kube_namespace.name}}/{{pod_name.name}} is using {{value}}% of its ephemeral storage limit. The kubelet evicts it at 100%."
        window  = "last_5m"
      }
      grafana = {
        expr           = "100 * max by (namespace, pod, container) (container_fs_usage_bytes{container!=\"\",__SEL__} / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"ephemeral_storage\",__SEL__})"
        pending_period = "5m"
        subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its ephemeral storage limit. The kubelet evicts it at 100%."
      }
      group     = "resources"
      operator  = "gt"
      severity  = "critical"
      threshold = 80
      title     = "Container ephemeral storage near limit"
      workload  = true
    }
    container_memory_near_limit_critical = {
      datadog = {
        query   = "min(__WINDOW__):100 * max:kubernetes.memory.working_set{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} / max:kubernetes.memory.limits{__SCOPE__} by {kube_namespace,pod_name,kube_container_name}"
        summary = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) is using {{value}}% of its memory limit and will be OOM killed at 100%."
        window  = "last_5m"
      }
      grafana = {
        expr           = "100 * max by (namespace, pod, container) (container_memory_working_set_bytes{container!=\"\",__SEL__} / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"memory\",__SEL__})"
        pending_period = "5m"
        subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its memory limit and will be OOM killed at 100%."
      }
      group     = "resources"
      operator  = "gt"
      severity  = "critical"
      threshold = 90
      title     = "Container memory at limit"
      workload  = true
    }
    container_memory_near_limit_warning = {
      datadog = {
        query   = "min(__WINDOW__):100 * max:kubernetes.memory.working_set{__SCOPE__} by {kube_namespace,pod_name,kube_container_name} / max:kubernetes.memory.limits{__SCOPE__} by {kube_namespace,pod_name,kube_container_name}"
        summary = "{{kube_namespace.name}}/{{pod_name.name}} ({{kube_container_name.name}}) is using {{value}}% of its memory limit."
        window  = "last_10m"
      }
      grafana = {
        expr           = "100 * max by (namespace, pod, container) (container_memory_working_set_bytes{container!=\"\",__SEL__} / on (namespace, pod, container) group_left kube_pod_container_resource_limits{resource=\"memory\",__SEL__})"
        pending_period = "10m"
        subject        = "{{ $labels.container }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is using {{ humanize $values.A.Value }}% of its memory limit."
      }
      group     = "resources"
      operator  = "gt"
      severity  = "warning"
      threshold = 80
      title     = "Container memory near limit"
      workload  = true
    }
    persistent_volume_errors = {
      # PersistentVolumes are cluster-wide, so workload_scope doesn't apply.
      datadog = {
        query   = "min(__WINDOW__):default_zero(max:kubernetes_state.persistentvolume.by_phase{phase IN (failed,pending) AND __SCOPE__} by {persistentvolume,phase})"
        summary = "PersistentVolume {{persistentvolume.name}} has been {{phase.name}} for 5 minutes. Pods that use it can't start."
        window  = "last_5m"
      }
      grafana = {
        expr           = "max by (persistentvolume, phase) (kube_persistentvolume_status_phase{phase=~\"Failed|Pending\"})"
        pending_period = "5m"
        subject        = "{{ $labels.persistentvolume }} ({{ $labels.phase }})"
        summary        = "PersistentVolume {{ $labels.persistentvolume }} has been {{ $labels.phase }} for 5 minutes. Pods that use it can't start."
      }
      group     = "resources"
      operator  = "gt"
      severity  = "critical"
      threshold = 0
      title     = "PersistentVolume failed"
    }
    pvc_inodes_near_full = {
      datadog = {
        query   = "min(__WINDOW__):100 * max:kubernetes.kubelet.volume.stats.inodes_used{__SCOPE__} by {kube_namespace,persistentvolumeclaim} / max:kubernetes.kubelet.volume.stats.inodes{__SCOPE__} by {kube_namespace,persistentvolumeclaim}"
        summary = "PVC {{kube_namespace.name}}/{{persistentvolumeclaim.name}} has used {{value}}% of its inodes. New files fail at 100% even with free space."
        window  = "last_10m"
      }
      grafana = {
        expr           = "max by (namespace, persistentvolumeclaim) (100 * kubelet_volume_stats_inodes_used{__SEL__} / kubelet_volume_stats_inodes{__SEL__})"
        pending_period = "10m"
        subject        = "{{ $labels.persistentvolumeclaim }} in {{ $labels.namespace }}"
        summary        = "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} has used {{ humanize $values.A.Value }}% of its inodes. New files fail at 100% even with free space."
      }
      group     = "resources"
      operator  = "gt"
      severity  = "warning"
      threshold = 90
      title     = "PVC running out of inodes"
      workload  = true
    }
    pvc_near_full_critical = {
      datadog = {
        query   = "min(__WINDOW__):100 * max:kubernetes.kubelet.volume.stats.used_bytes{__SCOPE__} by {kube_namespace,persistentvolumeclaim} / max:kubernetes.kubelet.volume.stats.capacity_bytes{__SCOPE__} by {kube_namespace,persistentvolumeclaim}"
        summary = "{{kube_namespace.name}}/{{persistentvolumeclaim.name}} is {{value}}% full."
        window  = "last_5m"
      }
      grafana = {
        expr           = "100 * max by (namespace, persistentvolumeclaim) (kubelet_volume_stats_used_bytes{__SEL__} / kubelet_volume_stats_capacity_bytes{__SEL__})"
        pending_period = "5m"
        subject        = "{{ $labels.persistentvolumeclaim }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is {{ humanize $values.A.Value }}% full."
      }
      group     = "resources"
      operator  = "gt"
      severity  = "critical"
      threshold = 90
      title     = "PersistentVolumeClaim critically full"
      workload  = true
    }
    pvc_near_full_warning = {
      datadog = {
        query   = "min(__WINDOW__):100 * max:kubernetes.kubelet.volume.stats.used_bytes{__SCOPE__} by {kube_namespace,persistentvolumeclaim} / max:kubernetes.kubelet.volume.stats.capacity_bytes{__SCOPE__} by {kube_namespace,persistentvolumeclaim}"
        summary = "{{kube_namespace.name}}/{{persistentvolumeclaim.name}} is {{value}}% full."
        window  = "last_10m"
      }
      grafana = {
        expr           = "100 * max by (namespace, persistentvolumeclaim) (kubelet_volume_stats_used_bytes{__SEL__} / kubelet_volume_stats_capacity_bytes{__SEL__})"
        pending_period = "10m"
        subject        = "{{ $labels.persistentvolumeclaim }} in {{ $labels.namespace }}"
        summary        = "{{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is {{ humanize $values.A.Value }}% full."
      }
      group     = "resources"
      operator  = "gt"
      severity  = "warning"
      threshold = 80
      title     = "PersistentVolumeClaim almost full"
      workload  = true
    }

    # ── Nodes ─────────────────────────────────────────────────────────────
    kubelet_certificate_expiring = {
      datadog = {
        query   = "max(__WINDOW__):min:kubernetes.kubelet.certificate_manager.client_ttl{__SCOPE__} by {host}"
        summary = "The kubelet's client certificate on {{host.name}} expires in {{value}}s."
        window  = "last_15m"
      }
      grafana = {
        # Needs the kubelet's certificate manager metrics. k3s doesn't expose
        # them, so there this rule has no data and stays quiet.
        expr           = "min by (node) (kubelet_certificate_manager_client_ttl_seconds or kubelet_certificate_manager_server_ttl_seconds)"
        pending_period = "15m"
        subject        = "{{ $labels.node }}"
        summary        = "A kubelet certificate on {{ $labels.node }} expires in {{ humanizeDuration $values.A.Value }}."
      }
      group     = "nodes"
      operator  = "lt"
      severity  = "warning"
      threshold = 604800
      title     = "Kubelet certificate expiring"
    }
    node_clock_not_synchronising = {
      # The Agent's NTP check is on by default and reports the offset from its
      # NTP servers.
      datadog = {
        query   = "\"ntp.in_sync\".over(__TAGS__).by(\"host\").last(__LAST__).count_by_status()"
        summary = "{{host.name}}'s clock is out of sync with NTP."
        type    = "service check"
      }
      grafana = {
        expr           = "min by (instance) (node_timex_sync_status)"
        pending_period = "10m"
        subject        = "{{ $labels.instance }}"
        summary        = "{{ $labels.instance }} isn't synchronising its clock with NTP."
      }
      group     = "nodes"
      operator  = "lt"
      severity  = "warning"
      threshold = 1
      title     = "Node clock not synchronising"
    }
    node_clock_skew = {
      datadog = {
        query = "min(__WINDOW__):abs(max:ntp.offset{__SCOPE__} by {host})"
        # The NTP check runs every 15 minutes, so a shorter window never fills.
        require_full_window = false
        summary             = "{{host.name}}'s clock is {{value}}s off. Skew breaks TLS, tokens and log ordering; check NTP."
        window              = "last_30m"
      }
      grafana = {
        expr           = "max by (instance) (abs(node_timex_offset_seconds))"
        pending_period = "10m"
        subject        = "{{ $labels.instance }}"
        summary        = "{{ $labels.instance }}'s clock is {{ humanize $values.A.Value }}s off. Skew breaks TLS, tokens and log ordering; check NTP."
      }
      group     = "nodes"
      operator  = "gt"
      severity  = "warning"
      threshold = 0.05
      title     = "Node clock skewed"
    }
    node_disk_full = {
      datadog = {
        query   = "min(__WINDOW__):100 * max:system.disk.in_use{__SCOPE__} by {host,device}"
        summary = "{{device.name}} on {{host.name}} is {{value}}% full."
        window  = "last_10m"
      }
      grafana = {
        expr           = "100 * max by (instance, mountpoint) (1 - node_filesystem_avail_bytes{fstype!~\"tmpfs|overlay|squashfs|ramfs\"} / node_filesystem_size_bytes{fstype!~\"tmpfs|overlay|squashfs|ramfs\"})"
        pending_period = "10m"
        subject        = "{{ $labels.mountpoint }} on {{ $labels.instance }}"
        summary        = "{{ $labels.mountpoint }} on {{ $labels.instance }} is {{ humanize $values.A.Value }}% full."
      }
      group     = "nodes"
      operator  = "gt"
      severity  = "critical"
      threshold = 85
      title     = "Node disk almost full"
    }
    node_inodes_low = {
      datadog = {
        query   = "min(__WINDOW__):100 * max:system.fs.inodes.in_use{__SCOPE__} by {host,device}"
        summary = "{{device.name}} on {{host.name}} has used {{value}}% of its inodes. New files fail at 100% even with free space."
        window  = "last_10m"
      }
      grafana = {
        expr           = "max by (instance, mountpoint) (100 * (1 - node_filesystem_files_free{fstype!~\"tmpfs|overlay|squashfs|nsfs|ramfs\"} / (node_filesystem_files{fstype!~\"tmpfs|overlay|squashfs|nsfs|ramfs\"} > 0)))"
        pending_period = "10m"
        subject        = "{{ $labels.instance }} {{ $labels.mountpoint }}"
        summary        = "{{ $labels.mountpoint }} on {{ $labels.instance }} has used {{ humanize $values.A.Value }}% of its inodes. New files fail at 100% even with free space."
      }
      group     = "nodes"
      operator  = "gt"
      severity  = "warning"
      threshold = 90
      title     = "Node running out of inodes"
    }
    node_memory_high = {
      datadog = {
        query   = "min(__WINDOW__):100 * (1 - max:system.mem.usable{__SCOPE__} by {host} / max:system.mem.total{__SCOPE__} by {host})"
        summary = "{{host.name}} is using {{value}}% of its memory."
        window  = "last_10m"
      }
      grafana = {
        expr           = "100 * max by (instance) (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)"
        pending_period = "10m"
        subject        = "{{ $labels.instance }}"
        summary        = "{{ $labels.instance }} is using {{ humanize $values.A.Value }}% of its memory."
      }
      group     = "nodes"
      operator  = "gt"
      severity  = "warning"
      threshold = 90
      title     = "Node memory high"
    }
    node_network_errors = {
      datadog = {
        query   = "min(__WINDOW__):max:system.net.packets_in.error{__SCOPE__} by {host,device} + max:system.net.packets_out.error{__SCOPE__} by {host,device}"
        summary = "{{device.name}} on {{host.name}} has {{value}} receive/transmit errors per second."
        window  = "last_10m"
      }
      grafana = {
        expr           = "max by (instance, device) (rate(node_network_receive_errs_total[5m]) + rate(node_network_transmit_errs_total[5m]))"
        pending_period = "10m"
        subject        = "{{ $labels.device }} on {{ $labels.instance }}"
        summary        = "{{ $labels.device }} on {{ $labels.instance }} has {{ humanize $values.A.Value }} receive/transmit errors per second."
      }
      group     = "nodes"
      operator  = "gt"
      severity  = "warning"
      threshold = 1
      title     = "Node network errors"
    }
    node_not_ready = {
      datadog = {
        query   = "min(__WINDOW__):default_zero(max:kubernetes_state.node.by_condition{condition:ready AND status IN (false,unknown) AND __SCOPE__} by {node})"
        summary = "Node {{node.name}} has not been Ready for 5 minutes."
        window  = "last_5m"
      }
      grafana = {
        expr           = "max by (node) (kube_node_status_condition{condition=\"Ready\",status=~\"false|unknown\"})"
        pending_period = "2m"
        subject        = "{{ $labels.node }}"
        summary        = "Node {{ $labels.node }} has not been Ready for 2 minutes."
      }
      group     = "nodes"
      operator  = "gt"
      severity  = "critical"
      threshold = 0
      title     = "Node not ready"
    }
    node_pressure = {
      datadog = {
        query   = "min(__WINDOW__):default_zero(max:kubernetes_state.node.by_condition{condition IN (memorypressure,diskpressure,pidpressure) AND status:true AND __SCOPE__} by {node,condition})"
        summary = "Node {{node.name}} reports {{condition.name}}. The kubelet may start evicting pods."
        window  = "last_5m"
      }
      grafana = {
        expr           = "max by (node, condition) (kube_node_status_condition{condition=~\"MemoryPressure|DiskPressure|PIDPressure\",status=\"true\"})"
        pending_period = "5m"
        subject        = "{{ $labels.node }} ({{ $labels.condition }})"
        summary        = "Node {{ $labels.node }} reports {{ $labels.condition }}. The kubelet may start evicting pods."
      }
      group     = "nodes"
      operator  = "gt"
      severity  = "warning"
      threshold = 0
      title     = "Node under resource pressure"
    }
    node_readiness_flapping = {
      # Counts changes of the Ready condition, as modules/alerts does with
      # changes().
      datadog = {
        query               = "sum(__WINDOW__):abs(diff(max:kubernetes_state.node.by_condition{condition:ready AND status:true AND __SCOPE__} by {node}))"
        require_full_window = false
        summary             = "Node {{node.name}} changed Ready state {{value}} times in 15 minutes. Check its network and kubelet."
        window              = "last_15m"
      }
      grafana = {
        expr           = "sum by (node) (changes(kube_node_status_condition{condition=\"Ready\",status=\"true\"}[15m]))"
        pending_period = "0s"
        subject        = "{{ $labels.node }}"
        summary        = "Node {{ $labels.node }} changed Ready state {{ humanize $values.A.Value }} times in 15 minutes. Check its network and kubelet."
      }
      group     = "nodes"
      operator  = "gt"
      severity  = "warning"
      threshold = 2
      title     = "Node readiness flapping"
    }
    node_systemd_service_failed = {
      # Needs the Agent's systemd check, which isn't on by default. Without it
      # there's no data and the monitor stays quiet.
      datadog = {
        query   = "\"systemd.unit.state\".over(__TAGS__).by(\"host\",\"unit\").last(__LAST__).count_by_status()"
        summary = "systemd unit {{unit.name}} on {{host.name}} has failed."
        # A service check's threshold counts consecutive failed runs, not a value. The
        # Agent runs each check every 15 seconds, so 20 is about 5 minutes.
        threshold = 20
        type      = "service check"
      }
      grafana = {
        # Needs node-exporter's systemd collector (--collector.systemd), which
        # is off by default. Without it this rule has no data and stays quiet.
        expr           = "max by (instance, name) (node_systemd_unit_state{state=\"failed\"})"
        pending_period = "5m"
        subject        = "{{ $labels.name }} on {{ $labels.instance }}"
        summary        = "systemd unit {{ $labels.name }} on {{ $labels.instance }} has failed."
      }
      group     = "nodes"
      operator  = "gt"
      severity  = "warning"
      threshold = 0
      title     = "systemd service failed"
    }
    scrape_target_down = {
      # The closest match to Prometheus' `up`: an Agent check (an integration
      # or an OpenMetrics endpoint) that keeps failing.
      datadog = {
        query   = "\"datadog.agent.check_status\".over(__TAGS__).by(\"check\",\"host\").last(__LAST__).count_by_status()"
        summary = "The Agent's {{check.name}} check on {{host.name}} has failed for 10 minutes. Alerts that depend on it go quiet."
        # A service check's threshold counts consecutive failed runs, not a value. The
        # Agent runs each check every 15 seconds, so 40 is about 10 minutes.
        threshold = 40
        type      = "service check"
      }
      grafana = {
        expr           = "min by (job, namespace, instance) (up)"
        pending_period = "10m"
        subject        = "{{ $labels.job }}"
        summary        = "Prometheus can't scrape {{ $labels.job }} at {{ $labels.instance }}. Alerts that depend on it go quiet."
      }
      group     = "nodes"
      operator  = "lt"
      severity  = "warning"
      threshold = 1
      title     = "Metrics target down"
    }

    # ── Synthetics (blackbox exporter probes) ─────────────────────────────
    synthetic_check_failing = {
      datadog = {
        skip = "Datadog Synthetics, tracked in an issue."
      }
      # These need blackbox exporter probes, such as modules/stack's
      # blackbox_exporter.targets. With no probes they have no data and stay quiet.
      grafana = {
        expr           = "min by (target, instance) (probe_success)"
        pending_period = "2m"
        subject        = "{{ $labels.target }}"
        summary        = "{{ $labels.target }} ({{ $labels.instance }}) has failed its synthetic check for 2 minutes."
      }
      group     = "synthetics"
      operator  = "lt"
      severity  = "critical"
      threshold = 1
      title     = "Synthetic check failing"
    }
    synthetic_check_slow = {
      datadog = {
        skip = "Datadog Synthetics, tracked in an issue."
      }
      grafana = {
        expr           = "max by (target, instance) (probe_duration_seconds)"
        pending_period = "10m"
        subject        = "{{ $labels.target }}"
        summary        = "{{ $labels.target }} ({{ $labels.instance }}) is taking {{ humanize $values.A.Value }}s to answer its synthetic check."
      }
      group     = "synthetics"
      operator  = "gt"
      severity  = "warning"
      threshold = 5
      title     = "Synthetic check slow"
    }
    tls_certificate_expiring_critical = {
      datadog = {
        skip = "Datadog Synthetics, tracked in an issue."
      }
      grafana = {
        expr           = "min by (target, instance) ((probe_ssl_earliest_cert_expiry - time()) / 86400)"
        pending_period = "1h"
        subject        = "{{ $labels.target }}"
        summary        = "The TLS certificate for {{ $labels.target }} ({{ $labels.instance }}) expires in {{ humanize $values.A.Value }} days."
      }
      group     = "synthetics"
      operator  = "lt"
      severity  = "critical"
      threshold = 3
      title     = "TLS certificate about to expire"
    }
    tls_certificate_expiring_warning = {
      datadog = {
        skip = "Datadog Synthetics, tracked in an issue."
      }
      grafana = {
        expr           = "min by (target, instance) ((probe_ssl_earliest_cert_expiry - time()) / 86400)"
        pending_period = "1h"
        subject        = "{{ $labels.target }}"
        summary        = "The TLS certificate for {{ $labels.target }} ({{ $labels.instance }}) expires in {{ humanize $values.A.Value }} days. Check that renewal is working."
      }
      group     = "synthetics"
      operator  = "lt"
      severity  = "warning"
      threshold = 14
      title     = "TLS certificate expiring soon"
    }

    # ── Alerting (the notification pipeline itself) ───────────────────────
    notification_delivery_failing = {
      datadog = {
        skip = "Watches Grafana's notification pipeline. Datadog reports its own delivery failures."
      }
      # Grafana counts failed deliveries per integration. With more than one
      # channel, a failure in one is reported through the others.
      grafana = {
        expr           = "sum by (integration) (increase(grafana_alerting_notifications_failed_total[15m]))"
        pending_period = "0s"
        subject        = "{{ $labels.integration }}"
        summary        = "Grafana failed to deliver {{ humanize $values.A.Value }} notifications through {{ $labels.integration }} in the last 15 minutes. Check that channel's URL or token."
      }
      group     = "alerting"
      operator  = "gt"
      severity  = "warning"
      threshold = 0
      title     = "Notification delivery failing"
    }
    prometheus_config_reload_failed = {
      datadog = {
        skip = "Prometheus' own health. This backend has no Prometheus; cluster_not_reporting catches the Agent going quiet."
      }
      # Prometheus health. The heartbeat queries vector(1), which still works
      # when Prometheus stops ingesting, so these catch what it can't.
      grafana = {
        expr           = "min by (instance) (prometheus_config_last_reload_successful)"
        pending_period = "10m"
        subject        = "{{ $labels.instance }}"
        summary        = "Prometheus {{ $labels.instance }} failed to reload its configuration and is running the previous one."
      }
      group     = "alerting"
      operator  = "lt"
      severity  = "critical"
      threshold = 1
      title     = "Prometheus config reload failed"
    }
    prometheus_not_ingesting = {
      datadog = {
        skip = "Prometheus' own health. This backend has no Prometheus; cluster_not_reporting catches the Agent going quiet."
      }
      grafana = {
        expr           = "sum by (instance) (rate(prometheus_tsdb_head_samples_appended_total[5m]))"
        pending_period = "10m"
        subject        = "{{ $labels.instance }}"
        summary        = "Prometheus {{ $labels.instance }} has stopped ingesting samples. Every metric alert is blind."
      }
      group     = "alerting"
      operator  = "lt"
      severity  = "critical"
      threshold = 1
      title     = "Prometheus not ingesting"
    }
    prometheus_rule_failures = {
      datadog = {
        skip = "Prometheus' own health. This backend has no Prometheus; cluster_not_reporting catches the Agent going quiet."
      }
      grafana = {
        expr           = "sum by (instance, rule_group) (increase(prometheus_rule_evaluation_failures_total[5m]))"
        pending_period = "15m"
        subject        = "{{ $labels.rule_group }}"
        summary        = "Prometheus rules in {{ $labels.rule_group }} are failing to evaluate, so the recording rules they feed are stale."
      }
      group     = "alerting"
      operator  = "gt"
      severity  = "warning"
      threshold = 0
      title     = "Prometheus rule failures"
    }

    # ── Control plane (self-managed clusters only) ────────────────────────
    apiserver_client_certificate_expiring = {
      # Requests made with a client certificate that expires within 7 days, from
      # the kube_apiserver_metrics histogram's bucket. Datadog can't take a
      # quantile of it, so the threshold is a request count.
      datadog = {
        # Counts requests that used a certificate expiring within 7 days, because
        # Datadog can't take a quantile of the bucket histogram.
        operator            = "gt"
        query               = "sum(__WINDOW__):default_zero(sum:kube_apiserver.apiserver_client_certificate_expiration_seconds.bucket{upper_bound:604800.0 AND __SCOPE__}.as_count())"
        require_full_window = false
        summary             = "{{value}} API server requests in the last 15 minutes used a client certificate that expires within 7 days."
        # Counts requests that used a certificate expiring within 7 days, because
        # Datadog can't take a quantile of the bucket histogram.
        threshold = 0
        window    = "last_15m"
      }
      grafana = {
        # The soonest-expiring 1% of certificates clients presented to the API
        # server. k3s rotates its certificates on restart within 90 days of
        # expiry.
        expr           = "histogram_quantile(0.01, sum by (job, le) (rate(apiserver_client_certificate_expiration_seconds_bucket[5m])))"
        pending_period = "15m"
        subject        = "API server clients"
        summary        = "A client certificate used with the API server expires in {{ humanizeDuration $values.A.Value }}."
      }
      group     = "control-plane"
      operator  = "lt"
      requires  = "apiserver"
      severity  = "warning"
      threshold = 604800
      title     = "Client certificate expiring"
    }
    apiserver_errors = {
      datadog = {
        query   = "avg(__WINDOW__):100 * sum:kube_apiserver.apiserver_request_total.count{code:5* AND __SCOPE__}.as_rate() / sum:kube_apiserver.apiserver_request_total.count{__SCOPE__}.as_rate()"
        summary = "{{value}}% of API server requests are failing with 5xx."
        window  = "last_10m"
      }
      grafana = {
        expr           = "100 * sum(rate(apiserver_request_total{code=~\"5..\"}[5m])) / sum(rate(apiserver_request_total[5m]))"
        pending_period = "10m"
        subject        = "API server"
        summary        = "{{ humanize $values.A.Value }}% of API server requests are failing with 5xx."
      }
      group     = "control-plane"
      operator  = "gt"
      requires  = "apiserver"
      severity  = "critical"
      threshold = 5
      title     = "API server error rate high"
    }
    etcd_no_leader = {
      datadog = {
        query   = "max(__WINDOW__):min:etcd.server.has_leader{__SCOPE__} by {host}"
        summary = "etcd member {{host.name}} has no leader and can't serve requests."
        window  = "last_1m"
      }
      grafana = {
        expr           = "min by (instance) (etcd_server_has_leader)"
        pending_period = "1m"
        subject        = "{{ $labels.instance }}"
        summary        = "etcd member {{ $labels.instance }} has no leader and can't serve requests."
      }
      group     = "control-plane"
      operator  = "lt"
      requires  = "etcd"
      severity  = "critical"
      threshold = 1
      title     = "etcd member has no leader"
    }

    # ── Datadog only ──────────────────────────────────────────────────────
    cluster_not_reporting = {
      # The heartbeat's job on this backend: Datadog runs outside the cluster,
      # so it can alert when the cluster stops sending data at all.
      datadog = {
        on_missing_data = "show_and_notify_no_data"
        query           = "max(__WINDOW__):sum:kubernetes_state.node.count{__SCOPE__}"
        summary         = "The cluster has stopped sending Kubernetes metrics to Datadog for 10 minutes. The Agent, its network path or the whole cluster may be down."
        window          = "last_10m"
      }
      grafana = {
        skip = "Datadog runs outside the cluster, so it can alert when the cluster stops sending data. On Grafana, the heartbeat covers this (heartbeat_enabled)."
      }
      group     = "nodes"
      operator  = "lt"
      severity  = "critical"
      threshold = 1
      title     = "Cluster not reporting"
    }
  }
}
