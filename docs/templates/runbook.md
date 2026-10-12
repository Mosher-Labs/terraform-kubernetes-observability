# Runbook: [alert title]

<!--
How to use
- One runbook per alert rule. Copy this file to docs/runbooks/[rule_id].md.
- Set the rule's runbook_url to this file's URL (or to the heading anchor).
- Write it for someone paged at 03:00 who has never seen this alert.
- Keep each section short. Link out for detail. Delete lines that don't apply.
- Review it whenever the alert fires and the runbook did not help. Update the
  "Last reviewed" line.
-->

| Field | Value |
| --- | --- |
| Rule ID | `[rule_id]` |
| Severity | [page / ticket / info] |
| Owner | [team or role] |
| Last reviewed | [YYYY-MM-DD] by [role] |

## What this alert means

[One or two sentences. State the condition in plain words, for example
"More than 5 container restarts in 15 minutes for one pod."]

Fires when: [query or condition, threshold, pending period]

## Impact

[Who or what is affected if this is real. Say whether users see it now,
will see it soon, or won't see it. If users are not affected, say so.]

## First checks (5 minutes)

1. [Check 1, with the command or dashboard link]
2. [Check 2]
3. [Check 3]

```text
[command or query to run]
```

Expected when healthy: [what you should see]

## Likely causes

| Cause | How to confirm | Go to |
| --- | --- | --- |
| [cause 1] | [check] | [mitigation heading] |
| [cause 2] | [check] | [mitigation heading] |
| A recent change | [deploy or config history link] | Roll back |

## Mitigations

### [Mitigation 1: for example, roll back the last deploy]

1. [Step]
2. [Step]

Verify: [how you know it worked, and how long to wait]

### [Mitigation 2]

1. [Step]

Do not: [known unsafe action]

## Escalation

Escalate if [condition: for example, not mitigated in 30 minutes, data loss
possible, more than one service affected].

| Who | How | When |
| --- | --- | --- |
| [primary on-call] | [pager or channel] | [condition] |
| [service owner] | [channel] | [condition] |

If this meets the incident criteria, declare an incident and open an
incident state document.

## Dashboards, queries and logs

- Dashboard: [link]
- Metrics query: `[query]`
- Logs: [link or saved search]
- Traces: [link]

## After the alert

- Is the alert noisy or not actionable? Note it for the next alert review.
- Did this runbook miss a step? Fix it now.
- Does this need a postmortem? Write one if the incident used a large share of the error budget
  or surprised the team. See postmortem.md.

## History

| Date | What happened | Link |
| --- | --- | --- |
| [YYYY-MM-DD] | [one line] | [incident or postmortem link] |
