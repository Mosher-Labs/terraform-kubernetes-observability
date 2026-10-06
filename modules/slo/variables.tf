variable "slos" {
  default     = {}
  description = <<-EOT
    Your SLOs, keyed by an ID that becomes part of each rule ID. For each one:

    - `title`: what the SLO covers, in a few words, such as "Pi-hole DNS replies".
    - `target`: the objective as a fraction, such as 0.999 for 99.9%.
    - `error_ratio`: a PromQL expression for the fraction of events that were bad over `$${window}`, a value from 0 to 1. Write `$${window}` where the range goes; it is filled in for each alert window.
    - `window_days`: the SLO window. Default 30.
    - `tiers`: which burn-rate alerts to create, out of `fast` (14.4x over 1h and 5m, critical), `medium` (6x over 6h and 30m, critical) and `slow` (1x over 3d and 6h, warning). Default is all three. Use `["slow"]` for a service too quiet to page on.
    - `group`: the rule group. Default `slo`.

    The burn-rate thresholds come from the share of the error budget each tier may spend, so they stay correct if you change `window_days`.
  EOT
  type = map(object({
    error_ratio = string
    group       = optional(string, "slo")
    target      = number
    tiers       = optional(list(string), ["fast", "medium", "slow"])
    title       = string
    window_days = optional(number, 30)
  }))

  validation {
    condition     = alltrue([for s in values(var.slos) : s.target > 0 && s.target < 1])
    error_message = "Each SLO target is a fraction between 0 and 1, such as 0.999."
  }

  validation {
    condition     = alltrue([for s in values(var.slos) : length(s.tiers) > 0 && alltrue([for t in s.tiers : contains(["fast", "medium", "slow"], t)])])
    error_message = "Each SLO needs at least one tier, and tiers are fast, medium or slow."
  }

  validation {
    condition     = alltrue([for s in values(var.slos) : s.window_days > 0])
    error_message = "window_days must be greater than 0."
  }

  validation {
    condition     = alltrue([for s in values(var.slos) : strcontains(s.error_ratio, "$${window}")])
    error_message = "Each error_ratio must contain $${window}, where the alert window goes."
  }
}
