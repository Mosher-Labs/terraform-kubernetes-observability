# Backing-service rules, one opt-in section per technology in
# var.backing_services. Each reads the metrics of that technology's standard
# Prometheus exporter, named in the README. Rules are keyed by the exporter's
# `instance` label, which `__BSEL__` (var.backing_services.selector) can scope,
# for example to one namespace.
locals {
  backing_catalog_raw = {
    mongodb = {
      mongodb_connections_high = {
        expr           = "100 * max by (instance) (mongodb_ss_connections{conn_type=\"current\",__BSEL__}) / (max by (instance) (mongodb_ss_connections{conn_type=\"current\",__BSEL__}) + max by (instance) (mongodb_ss_connections{conn_type=\"available\",__BSEL__}))"
        operator       = "gt"
        pending_period = "10m"
        severity       = "warning"
        subject        = "MongoDB {{ $labels.instance }}"
        summary        = "MongoDB {{ $labels.instance }} is using {{ humanize $values.A.Value }}% of its connections."
        threshold      = var.backing_services.mongodb.connections_percent
        title          = "MongoDB connections high"
      }
      mongodb_down = {
        expr           = "min by (instance) (mongodb_up{__BSEL__})"
        operator       = "lt"
        pending_period = "2m"
        severity       = "critical"
        subject        = "MongoDB {{ $labels.instance }}"
        summary        = "The exporter can't reach MongoDB {{ $labels.instance }}."
        threshold      = 1
        title          = "MongoDB down"
      }
      mongodb_replication_lag = {
        expr           = "max by (instance, set) ((max by (instance, set) (mongodb_rs_members_optimeDate{member_state=\"PRIMARY\",__BSEL__}) - on (instance, set) group_right min by (instance, set, name) (mongodb_rs_members_optimeDate{member_state=\"SECONDARY\",__BSEL__})) / 1000)"
        operator       = "gt"
        pending_period = "5m"
        severity       = "warning"
        subject        = "MongoDB {{ $labels.instance }}"
        summary        = "A secondary in replica set {{ $labels.set }} is {{ humanizeDuration $values.A.Value }} behind the primary."
        threshold      = var.backing_services.mongodb.replication_lag_seconds
        title          = "MongoDB replication lag"
      }
    }
    mysql = {
      mysql_connections_high = {
        expr           = "100 * max by (instance) (mysql_global_status_threads_connected{__BSEL__}) / max by (instance) (mysql_global_variables_max_connections{__BSEL__})"
        operator       = "gt"
        pending_period = "10m"
        severity       = "warning"
        subject        = "MySQL {{ $labels.instance }}"
        summary        = "MySQL {{ $labels.instance }} is using {{ humanize $values.A.Value }}% of max_connections."
        threshold      = var.backing_services.mysql.connections_percent
        title          = "MySQL connections high"
      }
      mysql_down = {
        expr           = "min by (instance) (mysql_up{__BSEL__})"
        operator       = "lt"
        pending_period = "2m"
        severity       = "critical"
        subject        = "MySQL {{ $labels.instance }}"
        summary        = "The exporter can't reach MySQL {{ $labels.instance }}."
        threshold      = 1
        title          = "MySQL down"
      }
      mysql_replication_lag = {
        expr           = "max by (instance) (mysql_slave_status_seconds_behind_master{__BSEL__})"
        operator       = "gt"
        pending_period = "5m"
        severity       = "warning"
        subject        = "MySQL {{ $labels.instance }}"
        summary        = "MySQL replica {{ $labels.instance }} is {{ humanizeDuration $values.A.Value }} behind its source."
        threshold      = var.backing_services.mysql.replication_lag_seconds
        title          = "MySQL replication lag"
      }
    }
    postgres = {
      postgres_connections_high = {
        expr           = "100 * sum by (instance) (pg_stat_activity_count{__BSEL__}) / max by (instance) (pg_settings_max_connections{__BSEL__})"
        operator       = "gt"
        pending_period = "10m"
        severity       = "warning"
        subject        = "Postgres {{ $labels.instance }}"
        summary        = "Postgres {{ $labels.instance }} is using {{ humanize $values.A.Value }}% of max_connections."
        threshold      = var.backing_services.postgres.connections_percent
        title          = "Postgres connections high"
      }
      postgres_deadlocks = {
        expr           = "sum by (instance, datname) (increase(pg_stat_database_deadlocks{__BSEL__}[10m]))"
        operator       = "gt"
        pending_period = "0s"
        severity       = "warning"
        subject        = "Postgres {{ $labels.instance }} {{ $labels.datname }}"
        summary        = "{{ humanize $values.A.Value }} deadlocks in database {{ $labels.datname }} on {{ $labels.instance }} in the last 10 minutes."
        threshold      = 0
        title          = "Postgres deadlocks"
      }
      postgres_down = {
        expr           = "min by (instance) (pg_up{__BSEL__})"
        operator       = "lt"
        pending_period = "2m"
        severity       = "critical"
        subject        = "Postgres {{ $labels.instance }}"
        summary        = "The exporter can't reach Postgres {{ $labels.instance }}."
        threshold      = 1
        title          = "Postgres down"
      }
      postgres_replication_lag = {
        expr           = "max by (instance) (pg_replication_lag_seconds{__BSEL__})"
        operator       = "gt"
        pending_period = "5m"
        severity       = "warning"
        subject        = "Postgres {{ $labels.instance }}"
        summary        = "Postgres replica {{ $labels.instance }} is {{ humanizeDuration $values.A.Value }} behind its primary."
        threshold      = var.backing_services.postgres.replication_lag_seconds
        title          = "Postgres replication lag"
      }
    }
    rabbitmq = {
      rabbitmq_alarm = {
        expr           = "max by (instance) ({__name__=~\"rabbitmq_alarms_(memory_used_watermark|free_disk_space_watermark|file_descriptor_limit)\",__BSEL__})"
        operator       = "gt"
        pending_period = "1m"
        severity       = "critical"
        subject        = "RabbitMQ {{ $labels.instance }}"
        summary        = "RabbitMQ {{ $labels.instance }} has a resource alarm (memory, disk or file descriptors), so publishers are blocked."
        threshold      = 0
        title          = "RabbitMQ resource alarm"
      }
      rabbitmq_queue_backlog = {
        expr           = "sum by (instance) (rabbitmq_queue_messages_ready{__BSEL__})"
        operator       = "gt"
        pending_period = "15m"
        severity       = "warning"
        subject        = "RabbitMQ {{ $labels.instance }}"
        summary        = "{{ humanize $values.A.Value }} messages are waiting for consumers on RabbitMQ {{ $labels.instance }}."
        threshold      = var.backing_services.rabbitmq.queue_depth
        title          = "RabbitMQ queue backlog"
      }
      rabbitmq_unacked_high = {
        expr           = "sum by (instance) (rabbitmq_queue_messages_unacked{__BSEL__})"
        operator       = "gt"
        pending_period = "15m"
        severity       = "warning"
        subject        = "RabbitMQ {{ $labels.instance }}"
        summary        = "{{ humanize $values.A.Value }} messages are delivered but not acknowledged on RabbitMQ {{ $labels.instance }}. Consumers may be stuck."
        threshold      = var.backing_services.rabbitmq.unacked_messages
        title          = "RabbitMQ unacknowledged messages high"
      }
    }
    redis = {
      redis_down = {
        expr           = "min by (instance) (redis_up{__BSEL__})"
        operator       = "lt"
        pending_period = "2m"
        severity       = "critical"
        subject        = "Redis {{ $labels.instance }}"
        summary        = "The exporter can't reach Redis {{ $labels.instance }}."
        threshold      = 1
        title          = "Redis down"
      }
      redis_memory_high = {
        expr           = "100 * max by (instance) (redis_memory_used_bytes{__BSEL__}) / max by (instance) (redis_memory_max_bytes{__BSEL__} > 0)"
        operator       = "gt"
        pending_period = "10m"
        severity       = "warning"
        subject        = "Redis {{ $labels.instance }}"
        summary        = "Redis {{ $labels.instance }} is using {{ humanize $values.A.Value }}% of maxmemory, so it will start evicting or refusing writes."
        threshold      = var.backing_services.redis.memory_percent
        title          = "Redis memory high"
      }
      redis_rejected_connections = {
        expr           = "sum by (instance) (increase(redis_rejected_connections_total{__BSEL__}[10m]))"
        operator       = "gt"
        pending_period = "0s"
        severity       = "warning"
        subject        = "Redis {{ $labels.instance }}"
        summary        = "Redis {{ $labels.instance }} rejected {{ humanize $values.A.Value }} connections in the last 10 minutes (maxclients reached)."
        threshold      = 0
        title          = "Redis rejecting connections"
      }
    }
  }

  # Enabled sections only, flattened to rule ID => rule, with the group set
  # and the selector filled in.
  backing_catalog = merge([
    for tech, rules in local.backing_catalog_raw : {
      for id, r in rules : id => merge(r, {
        expr = replace(
          replace(r.expr, ",__BSEL__}", var.backing_services.selector == "" ? "}" : ",${var.backing_services.selector}}"),
          "{__BSEL__}", var.backing_services.selector == "" ? "" : "{${var.backing_services.selector}}",
        )
        group = "backing-services"
      })
    } if var.backing_services[tech].enabled
  ]...)

  # Every backing-service rule ID, enabled or not.
  backing_rule_ids = flatten([for tech, rules in local.backing_catalog_raw : keys(rules)])
}
