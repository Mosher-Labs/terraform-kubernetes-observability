output "folder_uid" {
  description = "UID of the Grafana folder that holds the rules."
  value       = grafana_folder.this.uid
}

output "rule_ids" {
  description = "IDs of the rules that were created, after cluster type, disabled_rules and control_plane are applied."
  value       = sort(keys(local.rules))
}

output "rules" {
  description = "The rules as created: group, title, subject, query, threshold, pending period, severity and runbook URL, keyed by rule ID."
  value = {
    for id, r in local.rules : id => {
      expr           = r.expr
      group          = r.group
      pending_period = r.pending_period
      runbook_url    = lookup(local.runbook_urls, id, null)
      severity       = r.severity
      subject        = r.subject
      threshold      = r.threshold
      title          = r.title
    }
  }
}

output "rules_without_runbook" {
  description = "IDs of critical rules with no runbook link. Every rule that pages should have one."
  value       = local.rules_without_runbook
}
