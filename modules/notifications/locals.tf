locals {
  any_enabled = local.email_enabled || local.slack_enabled || local.teams_enabled || local.webex_enabled

  email_enabled = var.email != null

  # The channel variables are sensitive, and Terraform refuses to expand a
  # dynamic block over a sensitive collection. Whether a channel is enabled
  # reveals nothing secret, so compute that much outside the mark.
  slack_enabled = nonsensitive(var.slack != null)
  teams_enabled = nonsensitive(var.teams != null)
  webex_enabled = nonsensitive(var.webex != null)
}
