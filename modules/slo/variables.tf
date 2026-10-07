variable "slos" {
  default     = {}
  description = <<-EOT
    Your SLOs, keyed by an ID that becomes part of each rule ID. For each one:

    - `title`: what the SLO covers, in a few words, such as "Pi-hole DNS replies".
    - `target`: the objective as a fraction, such as 0.999 for 99.9%.
    - `window_days`: the SLO window: 7, 30 or 90 (Datadog's choices). Default 30.
    - `tiers`: which burn-rate alerts to create, out of `fast` (14.4x over 1h and 5m, critical), `medium` (6x over 6h and 30m, critical) and `slow` (3x over 1d and 2h, warning). Default is all three. Use `["slow"]` for a service too quiet to page on.
    - `group`: the rule group. Default `slo`.
    - `grafana`: for the Grafana backend, `error_ratio`, a PromQL expression for the fraction of events that were bad over `$${window}`, a value from 0 to 1. Write `$${window}` where the range goes; it is filled in for each alert window. It must return a single series, so aggregate it with `sum()` or similar.
    - `datadog`: for the Datadog backend, `good` and `total`, the metric queries that count good events and all valid events (`sum:my.metric{...}.as_count()`).

    Each SLO needs at least one backend block. The burn-rate thresholds come from the share of the error budget each tier may spend, so they stay correct for every window.
  EOT
  type = map(object({
    datadog = optional(object({
      good  = string
      total = string
    }))
    grafana = optional(object({
      error_ratio = string
    }))
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
    condition     = alltrue([for s in values(var.slos) : contains([7, 30, 90], s.window_days)])
    error_message = "window_days must be 7, 30 or 90."
  }

  validation {
    condition     = alltrue([for s in values(var.slos) : s.grafana != null || s.datadog != null])
    error_message = "Each SLO needs a grafana block, a datadog block, or both."
  }

  validation {
    condition     = alltrue([for s in values(var.slos) : s.grafana == null ? true : strcontains(s.grafana.error_ratio, "$${window}")])
    error_message = "Each grafana.error_ratio must contain $${window}, where the alert window goes."
  }
}
