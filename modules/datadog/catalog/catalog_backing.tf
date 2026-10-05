# Backing-service rules from the Datadog Agent's integrations, one opt-in
# section per technology in var.backing_services, with the same rule IDs and
# thresholds as modules/alerts' catalog_backing.tf. `__SCOPE__` gets the
# cluster tag and var.backing_services.scope. The `*_down` rules are service
# checks on each integration's can_connect check, like Datadog's
# recommended monitors.
#
# RabbitMQ metrics are from the integration's OpenMetrics mode (the
# rabbitmq_prometheus plugin, RabbitMQ 3.8+).
locals {
  backing_catalog_raw = {
    mongodb = {
      mongodb_connections_high = {
        operator  = "gt"
        query     = "min(__WINDOW__):100 * max:mongodb.connections.current{__SCOPE__} by {host} / (max:mongodb.connections.current{__SCOPE__} by {host} + max:mongodb.connections.available{__SCOPE__} by {host})"
        severity  = "warning"
        summary   = "MongoDB on {{host.name}} is using {{value}}% of its connections."
        threshold = var.backing_services.mongodb.connections_percent
        title     = "MongoDB connections high"
        window    = "last_10m"
      }
      mongodb_down = {
        query     = "\"mongodb.can_connect\".over(__TAGS__).by(\"host\").last(__LAST__).count_by_status()"
        severity  = "critical"
        summary   = "The Agent on {{host.name}} can't reach MongoDB."
        threshold = 8
        title     = "MongoDB down"
        type      = "service check"
      }
      mongodb_replication_lag = {
        operator  = "gt"
        query     = "min(__WINDOW__):max:mongodb.replset.replicationlag{__SCOPE__} by {replset_name,host}"
        severity  = "warning"
        summary   = "A secondary in replica set {{replset_name.name}} on {{host.name}} is {{value}}s behind the primary."
        threshold = var.backing_services.mongodb.replication_lag_seconds
        title     = "MongoDB replication lag"
        window    = "last_5m"
      }
    }
    mysql = {
      mysql_connections_high = {
        operator  = "gt"
        query     = "min(__WINDOW__):100 * max:mysql.performance.threads_connected{__SCOPE__} by {host} / max:mysql.net.max_connections_available{__SCOPE__} by {host}"
        severity  = "warning"
        summary   = "MySQL on {{host.name}} is using {{value}}% of max_connections."
        threshold = var.backing_services.mysql.connections_percent
        title     = "MySQL connections high"
        window    = "last_10m"
      }
      mysql_down = {
        query     = "\"mysql.can_connect\".over(__TAGS__).by(\"host\").last(__LAST__).count_by_status()"
        severity  = "critical"
        summary   = "The Agent on {{host.name}} can't reach MySQL."
        threshold = 8
        title     = "MySQL down"
        type      = "service check"
      }
      mysql_replication_lag = {
        operator  = "gt"
        query     = "min(__WINDOW__):max:mysql.replication.seconds_behind_master{__SCOPE__} by {host}"
        severity  = "warning"
        summary   = "MySQL replica {{host.name}} is {{value}}s behind its source."
        threshold = var.backing_services.mysql.replication_lag_seconds
        title     = "MySQL replication lag"
        window    = "last_5m"
      }
    }
    postgres = {
      postgres_connections_high = {
        operator  = "gt"
        query     = "min(__WINDOW__):100 * max:postgresql.percent_usage_connections{__SCOPE__} by {host}"
        severity  = "warning"
        summary   = "Postgres on {{host.name}} is using {{value}}% of max_connections."
        threshold = var.backing_services.postgres.connections_percent
        title     = "Postgres connections high"
        window    = "last_10m"
      }
      postgres_deadlocks = {
        operator            = "gt"
        query               = "sum(__WINDOW__):default_zero(sum:postgresql.deadlocks{__SCOPE__} by {host,db}.as_count())"
        require_full_window = false
        severity            = "warning"
        summary             = "{{value}} deadlocks in database {{db.name}} on {{host.name}} in the last 10 minutes."
        threshold           = 0
        title               = "Postgres deadlocks"
        window              = "last_10m"
      }
      postgres_down = {
        query     = "\"postgres.can_connect\".over(__TAGS__).by(\"host\").last(__LAST__).count_by_status()"
        severity  = "critical"
        summary   = "The Agent on {{host.name}} can't reach Postgres."
        threshold = 8
        title     = "Postgres down"
        type      = "service check"
      }
      postgres_replication_lag = {
        operator  = "gt"
        query     = "min(__WINDOW__):max:postgresql.replication_delay{__SCOPE__} by {host}"
        severity  = "warning"
        summary   = "Postgres replica {{host.name}} is {{value}}s behind its primary."
        threshold = var.backing_services.postgres.replication_lag_seconds
        title     = "Postgres replication lag"
        window    = "last_5m"
      }
    }
    rabbitmq = {
      # default_zero() on each alarm, because one missing series would empty
      # the sum.
      rabbitmq_alarm = {
        operator  = "gt"
        query     = "min(__WINDOW__):default_zero(max:rabbitmq.alarms.memory_used_watermark{__SCOPE__} by {host}) + default_zero(max:rabbitmq.alarms.free_disk_space_watermark{__SCOPE__} by {host}) + default_zero(max:rabbitmq.alarms.file_descriptor_limit{__SCOPE__} by {host})"
        severity  = "critical"
        summary   = "RabbitMQ on {{host.name}} has a resource alarm (memory, disk or file descriptors), so publishers are blocked."
        threshold = 0
        title     = "RabbitMQ resource alarm"
        window    = "last_1m"
      }
      rabbitmq_queue_backlog = {
        operator  = "gt"
        query     = "min(__WINDOW__):sum:rabbitmq.queue.messages.ready{__SCOPE__} by {host}"
        severity  = "warning"
        summary   = "{{value}} messages are waiting for consumers on RabbitMQ {{host.name}}."
        threshold = var.backing_services.rabbitmq.queue_depth
        title     = "RabbitMQ queue backlog"
        window    = "last_15m"
      }
      rabbitmq_unacked_high = {
        operator  = "gt"
        query     = "min(__WINDOW__):sum:rabbitmq.queue.messages.unacked{__SCOPE__} by {host}"
        severity  = "warning"
        summary   = "{{value}} messages are delivered but not acknowledged on RabbitMQ {{host.name}}. Consumers may be stuck."
        threshold = var.backing_services.rabbitmq.unacked_messages
        title     = "RabbitMQ unacknowledged messages high"
        window    = "last_15m"
      }
    }
    redis = {
      redis_down = {
        query     = "\"redis.can_connect\".over(__TAGS__).by(\"host\").last(__LAST__).count_by_status()"
        severity  = "critical"
        summary   = "The Agent on {{host.name}} can't reach Redis."
        threshold = 8
        title     = "Redis down"
        type      = "service check"
      }
      # maxmemory 0 (no limit) divides by zero and has no data.
      redis_memory_high = {
        operator  = "gt"
        query     = "min(__WINDOW__):100 * max:redis.mem.used{__SCOPE__} by {host} / max:redis.mem.maxmemory{__SCOPE__} by {host}"
        severity  = "warning"
        summary   = "Redis on {{host.name}} is using {{value}}% of maxmemory, so it will start evicting or refusing writes."
        threshold = var.backing_services.redis.memory_percent
        title     = "Redis memory high"
        window    = "last_10m"
      }
      redis_rejected_connections = {
        operator            = "gt"
        query               = "sum(__WINDOW__):default_zero(diff(max:redis.net.rejected{__SCOPE__} by {host}))"
        require_full_window = false
        severity            = "warning"
        summary             = "Redis on {{host.name}} rejected {{value}} connections in the last 10 minutes (maxclients reached)."
        threshold           = 0
        title               = "Redis rejecting connections"
        window              = "last_10m"
      }
    }
  }

  # Every backing-service rule, with its group set and gated on its section.
  backing_catalog = merge([
    for tech, rules in local.backing_catalog_raw : {
      for id, r in rules : id => merge(r, { backing = true, group = "backing-services", requires = tech })
    }
  ]...)
}
