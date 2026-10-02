output "folder_uid" {
  description = "UID of the Grafana folder that holds the rules."
  value       = grafana_folder.this.uid
}

output "rule_ids" {
  description = "IDs of the rules that were created, after cluster type, disabled_rules and control_plane are applied."
  value       = sort(keys(local.rules))
}

output "rules" {
  description = "The rules as created: group, title, subject, query, threshold, pending period and severity, keyed by rule ID."
  value = {
    for id, r in local.rules : id => {
      expr           = r.expr
      group          = r.group
      pending_period = r.pending_period
      severity       = r.severity
      subject        = r.subject
      threshold      = r.threshold
      title          = r.title
    }
  }
}
