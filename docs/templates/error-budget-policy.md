# Error budget policy: [service name]

<!--
How to use
- Based on the SRE Workbook example error budget policy (Appendix B).
- It states what the team does when the error budget is spent. Agree on it
  before it is needed, and get sign-off from product, development and on-call.
- The policy is not a punishment. It gives the team permission to put
  reliability first when the data says to.
- Fill in or delete every [placeholder]. Keep the numbers realistic for your team.
-->

| Field | Value |
| --- | --- |
| Service | [name] |
| SLO document | [link] |
| Authors | [names or roles] |
| Approvers | [product owner, dev lead, on-call lead, escalation owner] |
| Approved on | [YYYY-MM-DD] |
| Revisit on | [YYYY-MM-DD] |

## Goals

- Protect users from repeated SLO misses.
- Give the team a clear way to balance feature work and reliability work.

## Non-goals

- Blaming a team or person for an outage.
- Setting SLOs so tight that no change can ship.

## Scope

This policy covers [backend releases, client releases, config changes, data
changes].

## When the budget is not spent

Releases proceed as normal.

## When the budget is spent

Evaluated over [28 days]. Until the service is back within its SLO:

1. Stop feature releases and non-urgent changes. Allow [P0 fixes and security fixes].
2. The team works on reliability items first. The list is in [tracker link].
3. [Owner] reports status at [the weekly production meeting].

## Exceptions

The team may keep shipping features when the budget was spent mainly by:

- [An outage of shared infrastructure that the team does not own]
- [A dependency owned by another team, with a postmortem filed to that team]
- [Out-of-scope traffic: load tests, scanners]
- [Measurement errors with no user impact]

The team must stop features when the cause was:

- [Our own code or process]
- [A known dependency risk that postmortem action items did not address]

## Postmortem thresholds

- One incident that uses more than [20%] of the budget needs a postmortem with
  at least one P0 action item.
- One outage category that uses more than [20%] of the budget over a quarter
  puts a P0 item on next quarter's plan.

## Disagreements

If the parties disagree about the budget calculation or what the policy
requires, escalate to [role]. That person decides.

## Review

Review this policy [quarterly]. Record changes below.

| Date | Change | Who agreed |
| --- | --- | --- |
| [YYYY-MM-DD] | Initial version | [names] |
