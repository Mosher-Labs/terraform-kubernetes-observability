# Backing-service rules, one opt-in section per technology in
# var.backing_services. Grafana reads the metrics of the technology's standard
# Prometheus exporter, keyed by the exporter's `instance` label, which
# `${bsel}` can scope, for example to one namespace. Datadog reads the Agent's
# integrations, and `${scope}` adds the backing-service scope to the cluster
# tag. The `*_down` rules are service checks on each integration's can_connect
# check, like Datadog's recommended monitors. RabbitMQ metrics are from the
# integration's OpenMetrics mode (the rabbitmq_prometheus plugin, RabbitMQ 3.8+).
locals {
  backing_rules = {
    mongodb_connections_high = {
      datadog = {
        query   = "min($${window}):100 * max:mongodb.connections.current{$${scope}} by {host} / (max:mongodb.connections.current{$${scope}} by {host} + max:mongodb.connections.available{$${scope}} by {host})"
        summary = "MongoDB on {{host.name}} is using {{value}}% of its connections."
        window  = "last_10m"
      }
      grafana = {
        expr           = "100 * max by (instance) (mongodb_ss_connections{conn_type=\"current\"$${bsel_more}}) / (max by (instance) (mongodb_ss_connections{conn_type=\"current\"$${bsel_more}}) + max by (instance) (mongodb_ss_connections{conn_type=\"available\"$${bsel_more}}))"
        pending_period = "10m"
        subject        = "MongoDB {{ $labels.instance }}"
        summary        = "MongoDB {{ $labels.instance }} is using {{ humanize $values.A.Value }}% of its connections."
      }
      group     = "backing-services"
      operator  = "gt"
      requires  = "mongodb"
      severity  = "warning"
      threshold = var.backing_services.mongodb.connections_percent
      title     = "MongoDB connections high"
    }
    mongodb_down = {
      datadog = {
        query   = "\"mongodb.can_connect\".over($${tags}).by(\"host\").last($${last}).count_by_status()"
        summary = "The Agent on {{host.name}} can't reach MongoDB."
        # A service check's threshold counts consecutive failed runs, not a value. The
        # Agent runs each check every 15 seconds, so 8 is about 2 minutes.
        threshold = 8
        type      = "service check"
      }
      grafana = {
        expr           = "min by (instance) (mongodb_up$${bsel})"
        pending_period = "2m"
        subject        = "MongoDB {{ $labels.instance }}"
        summary        = "The exporter can't reach MongoDB {{ $labels.instance }}."
      }
      group     = "backing-services"
      operator  = "lt"
      requires  = "mongodb"
      severity  = "critical"
      threshold = 1
      title     = "MongoDB down"
    }
    mongodb_replication_lag = {
      datadog = {
        query   = "min($${window}):max:mongodb.replset.replicationlag{$${scope}} by {replset_name,host}"
        summary = "A secondary in replica set {{replset_name.name}} on {{host.name}} is {{value}}s behind the primary."
        window  = "last_5m"
      }
      grafana = {
        expr           = "max by (instance, set) ((max by (instance, set) (mongodb_rs_members_optimeDate{member_state=\"PRIMARY\"$${bsel_more}}) - on (instance, set) group_right min by (instance, set, name) (mongodb_rs_members_optimeDate{member_state=\"SECONDARY\"$${bsel_more}})) / 1000)"
        pending_period = "5m"
        subject        = "MongoDB {{ $labels.instance }}"
        summary        = "A secondary in replica set {{ $labels.set }} is {{ humanizeDuration $values.A.Value }} behind the primary."
      }
      group     = "backing-services"
      operator  = "gt"
      requires  = "mongodb"
      severity  = "warning"
      threshold = var.backing_services.mongodb.replication_lag_seconds
      title     = "MongoDB replication lag"
    }
    mysql_connections_high = {
      datadog = {
        query   = "min($${window}):100 * max:mysql.performance.threads_connected{$${scope}} by {host} / max:mysql.net.max_connections_available{$${scope}} by {host}"
        summary = "MySQL on {{host.name}} is using {{value}}% of max_connections."
        window  = "last_10m"
      }
      grafana = {
        expr           = "100 * max by (instance) (mysql_global_status_threads_connected$${bsel}) / max by (instance) (mysql_global_variables_max_connections$${bsel})"
        pending_period = "10m"
        subject        = "MySQL {{ $labels.instance }}"
        summary        = "MySQL {{ $labels.instance }} is using {{ humanize $values.A.Value }}% of max_connections."
      }
      group     = "backing-services"
      operator  = "gt"
      requires  = "mysql"
      severity  = "warning"
      threshold = var.backing_services.mysql.connections_percent
      title     = "MySQL connections high"
    }
    mysql_down = {
      datadog = {
        query   = "\"mysql.can_connect\".over($${tags}).by(\"host\").last($${last}).count_by_status()"
        summary = "The Agent on {{host.name}} can't reach MySQL."
        # A service check's threshold counts consecutive failed runs, not a value. The
        # Agent runs each check every 15 seconds, so 8 is about 2 minutes.
        threshold = 8
        type      = "service check"
      }
      grafana = {
        expr           = "min by (instance) (mysql_up$${bsel})"
        pending_period = "2m"
        subject        = "MySQL {{ $labels.instance }}"
        summary        = "The exporter can't reach MySQL {{ $labels.instance }}."
      }
      group     = "backing-services"
      operator  = "lt"
      requires  = "mysql"
      severity  = "critical"
      threshold = 1
      title     = "MySQL down"
    }
    mysql_replication_lag = {
      datadog = {
        query   = "min($${window}):max:mysql.replication.seconds_behind_master{$${scope}} by {host}"
        summary = "MySQL replica {{host.name}} is {{value}}s behind its source."
        window  = "last_5m"
      }
      grafana = {
        expr           = "max by (instance) (mysql_slave_status_seconds_behind_master$${bsel})"
        pending_period = "5m"
        subject        = "MySQL {{ $labels.instance }}"
        summary        = "MySQL replica {{ $labels.instance }} is {{ humanizeDuration $values.A.Value }} behind its source."
      }
      group     = "backing-services"
      operator  = "gt"
      requires  = "mysql"
      severity  = "warning"
      threshold = var.backing_services.mysql.replication_lag_seconds
      title     = "MySQL replication lag"
    }
    postgres_connections_high = {
      datadog = {
        query   = "min($${window}):100 * max:postgresql.percent_usage_connections{$${scope}} by {host}"
        summary = "Postgres on {{host.name}} is using {{value}}% of max_connections."
        window  = "last_10m"
      }
      grafana = {
        expr           = "100 * sum by (instance) (pg_stat_activity_count$${bsel}) / max by (instance) (pg_settings_max_connections$${bsel})"
        pending_period = "10m"
        subject        = "Postgres {{ $labels.instance }}"
        summary        = "Postgres {{ $labels.instance }} is using {{ humanize $values.A.Value }}% of max_connections."
      }
      group     = "backing-services"
      operator  = "gt"
      requires  = "postgres"
      severity  = "warning"
      threshold = var.backing_services.postgres.connections_percent
      title     = "Postgres connections high"
    }
    postgres_deadlocks = {
      datadog = {
        query               = "sum($${window}):default_zero(sum:postgresql.deadlocks{$${scope}} by {host,db}.as_count())"
        require_full_window = false
        summary             = "{{value}} deadlocks in database {{db.name}} on {{host.name}} in the last 10 minutes."
        window              = "last_10m"
      }
      grafana = {
        expr           = "sum by (instance, datname) (increase(pg_stat_database_deadlocks$${bsel}[10m]))"
        pending_period = "0s"
        subject        = "Postgres {{ $labels.instance }} {{ $labels.datname }}"
        summary        = "{{ humanize $values.A.Value }} deadlocks in database {{ $labels.datname }} on {{ $labels.instance }} in the last 10 minutes."
      }
      group     = "backing-services"
      operator  = "gt"
      requires  = "postgres"
      severity  = "warning"
      threshold = 0
      title     = "Postgres deadlocks"
    }
    postgres_down = {
      datadog = {
        query   = "\"postgres.can_connect\".over($${tags}).by(\"host\").last($${last}).count_by_status()"
        summary = "The Agent on {{host.name}} can't reach Postgres."
        # A service check's threshold counts consecutive failed runs, not a value. The
        # Agent runs each check every 15 seconds, so 8 is about 2 minutes.
        threshold = 8
        type      = "service check"
      }
      grafana = {
        expr           = "min by (instance) (pg_up$${bsel})"
        pending_period = "2m"
        subject        = "Postgres {{ $labels.instance }}"
        summary        = "The exporter can't reach Postgres {{ $labels.instance }}."
      }
      group     = "backing-services"
      operator  = "lt"
      requires  = "postgres"
      severity  = "critical"
      threshold = 1
      title     = "Postgres down"
    }
    postgres_replication_lag = {
      datadog = {
        query   = "min($${window}):max:postgresql.replication_delay{$${scope}} by {host}"
        summary = "Postgres replica {{host.name}} is {{value}}s behind its primary."
        window  = "last_5m"
      }
      grafana = {
        expr           = "max by (instance) (pg_replication_lag_seconds$${bsel})"
        pending_period = "5m"
        subject        = "Postgres {{ $labels.instance }}"
        summary        = "Postgres replica {{ $labels.instance }} is {{ humanizeDuration $values.A.Value }} behind its primary."
      }
      group     = "backing-services"
      operator  = "gt"
      requires  = "postgres"
      severity  = "warning"
      threshold = var.backing_services.postgres.replication_lag_seconds
      title     = "Postgres replication lag"
    }
    rabbitmq_alarm = {
      # default_zero() on each alarm, because one missing series would empty
      # the sum.
      datadog = {
        query   = "min($${window}):default_zero(max:rabbitmq.alarms.memory_used_watermark{$${scope}} by {host}) + default_zero(max:rabbitmq.alarms.free_disk_space_watermark{$${scope}} by {host}) + default_zero(max:rabbitmq.alarms.file_descriptor_limit{$${scope}} by {host})"
        summary = "RabbitMQ on {{host.name}} has a resource alarm (memory, disk or file descriptors), so publishers are blocked."
        window  = "last_1m"
      }
      grafana = {
        expr           = "max by (instance) ({__name__=~\"rabbitmq_alarms_(memory_used_watermark|free_disk_space_watermark|file_descriptor_limit)\"$${bsel_more}})"
        pending_period = "1m"
        subject        = "RabbitMQ {{ $labels.instance }}"
        summary        = "RabbitMQ {{ $labels.instance }} has a resource alarm (memory, disk or file descriptors), so publishers are blocked."
      }
      group     = "backing-services"
      operator  = "gt"
      requires  = "rabbitmq"
      severity  = "critical"
      threshold = 0
      title     = "RabbitMQ resource alarm"
    }
    rabbitmq_queue_backlog = {
      datadog = {
        query   = "min($${window}):sum:rabbitmq.queue.messages.ready{$${scope}} by {host}"
        summary = "{{value}} messages are waiting for consumers on RabbitMQ {{host.name}}."
        window  = "last_15m"
      }
      grafana = {
        expr           = "sum by (instance) (rabbitmq_queue_messages_ready$${bsel})"
        pending_period = "15m"
        subject        = "RabbitMQ {{ $labels.instance }}"
        summary        = "{{ humanize $values.A.Value }} messages are waiting for consumers on RabbitMQ {{ $labels.instance }}."
      }
      group     = "backing-services"
      operator  = "gt"
      requires  = "rabbitmq"
      severity  = "warning"
      threshold = var.backing_services.rabbitmq.queue_depth
      title     = "RabbitMQ queue backlog"
    }
    rabbitmq_unacked_high = {
      datadog = {
        query   = "min($${window}):sum:rabbitmq.queue.messages.unacked{$${scope}} by {host}"
        summary = "{{value}} messages are delivered but not acknowledged on RabbitMQ {{host.name}}. Consumers may be stuck."
        window  = "last_15m"
      }
      grafana = {
        expr           = "sum by (instance) (rabbitmq_queue_messages_unacked$${bsel})"
        pending_period = "15m"
        subject        = "RabbitMQ {{ $labels.instance }}"
        summary        = "{{ humanize $values.A.Value }} messages are delivered but not acknowledged on RabbitMQ {{ $labels.instance }}. Consumers may be stuck."
      }
      group     = "backing-services"
      operator  = "gt"
      requires  = "rabbitmq"
      severity  = "warning"
      threshold = var.backing_services.rabbitmq.unacked_messages
      title     = "RabbitMQ unacknowledged messages high"
    }
    redis_down = {
      datadog = {
        query   = "\"redis.can_connect\".over($${tags}).by(\"host\").last($${last}).count_by_status()"
        summary = "The Agent on {{host.name}} can't reach Redis."
        # A service check's threshold counts consecutive failed runs, not a value. The
        # Agent runs each check every 15 seconds, so 8 is about 2 minutes.
        threshold = 8
        type      = "service check"
      }
      grafana = {
        expr           = "min by (instance) (redis_up$${bsel})"
        pending_period = "2m"
        subject        = "Redis {{ $labels.instance }}"
        summary        = "The exporter can't reach Redis {{ $labels.instance }}."
      }
      group     = "backing-services"
      operator  = "lt"
      requires  = "redis"
      severity  = "critical"
      threshold = 1
      title     = "Redis down"
    }
    redis_memory_high = {
      # maxmemory 0 (no limit) divides by zero and has no data.
      datadog = {
        query   = "min($${window}):100 * max:redis.mem.used{$${scope}} by {host} / max:redis.mem.maxmemory{$${scope}} by {host}"
        summary = "Redis on {{host.name}} is using {{value}}% of maxmemory, so it will start evicting or refusing writes."
        window  = "last_10m"
      }
      grafana = {
        expr           = "100 * max by (instance) (redis_memory_used_bytes$${bsel}) / max by (instance) (redis_memory_max_bytes$${bsel} > 0)"
        pending_period = "10m"
        subject        = "Redis {{ $labels.instance }}"
        summary        = "Redis {{ $labels.instance }} is using {{ humanize $values.A.Value }}% of maxmemory, so it will start evicting or refusing writes."
      }
      group     = "backing-services"
      operator  = "gt"
      requires  = "redis"
      severity  = "warning"
      threshold = var.backing_services.redis.memory_percent
      title     = "Redis memory high"
    }
    redis_rejected_connections = {
      datadog = {
        query               = "sum($${window}):default_zero(diff(max:redis.net.rejected{$${scope}} by {host}))"
        require_full_window = false
        summary             = "Redis on {{host.name}} rejected {{value}} connections in the last 10 minutes (maxclients reached)."
        window              = "last_10m"
      }
      grafana = {
        expr           = "sum by (instance) (increase(redis_rejected_connections_total$${bsel}[10m]))"
        pending_period = "0s"
        subject        = "Redis {{ $labels.instance }}"
        summary        = "Redis {{ $labels.instance }} rejected {{ humanize $values.A.Value }} connections in the last 10 minutes (maxclients reached)."
      }
      group     = "backing-services"
      operator  = "gt"
      requires  = "redis"
      severity  = "warning"
      threshold = 0
      title     = "Redis rejecting connections"
    }
  }
}
