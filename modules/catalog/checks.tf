# Shows the same gaps in a plain plan, where an output precondition only fires
# when something reads the output.
check "every_rule_covers_every_backend" {
  assert {
    condition     = length(local.uncovered_ids) == 0
    error_message = "Every rule needs its shared fields and, for each backend, a block or a skip reason. Gaps: ${join(", ", local.uncovered_ids)}."
  }
}
