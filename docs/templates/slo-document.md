# SLO document: [service name]

<!--
How to use
- Based on the SRE Workbook example SLO document (Appendix A).
- Write one per service (or per user journey). Keep it to a page or two.
- Agree on it with the product owner, the developers and the on-call team
  before it takes effect. Record who agreed and when.
- Start loose and tighten later. Do not copy today's performance as the target
  without asking whether users would be happy with it.
- Revisit on the date below. Monthly while the SLO is new, quarterly later.
-->

| Field | Value |
| --- | --- |
| Service | [name] |
| Status | [draft / published / retired] |
| Authors | [names or roles] |
| Reviewers | [names or roles] |
| Approvers | [product owner, dev lead, on-call lead] |
| Approved on | [YYYY-MM-DD] |
| Revisit on | [YYYY-MM-DD] |
| Error budget policy | [link to the policy] |

## Service overview

[What the service does, who uses it, and the main components. Two to five
sentences. Add a diagram link if one helps.]

## Measurement window

[for example, rolling 28 days]

## SLIs and SLOs

| Category | SLI (what we measure) | How it is calculated | Data source | SLO |
| --- | --- | --- | --- | --- |
| Availability | [proportion of valid requests that succeed] | [good events / valid events] | [load balancer metric] | [99.9%] |
| Latency (fast) | <proportion of requests faster than [N] ms> | [fast requests / valid requests] | [request histogram] | [90%] |
| Latency (acceptable) | <proportion faster than [N] ms> | [...] | [...] | [99%] |
| [Freshness / correctness / durability] | [...] | [...] | [...] | [...] |

Define "valid request" and "good request" here: [which status codes count as
errors, which endpoints and callers are excluded (health checks, load tests)].

## Rationale

[Why these numbers. State whether they come from measured history, user
research or an estimate. Say what has not been verified, for example "not yet
checked against user complaints".]

## Error budget

Error budget = 100% minus the SLO. For [99.9%] over [28 days] and
[N] requests, the budget is [N x 0.001] failed requests.

What happens when the budget is spent: see the error budget policy.

## Alerting

| Alert | Burn rate | Long window | Short window | Action |
| --- | --- | --- | --- | --- |
| Fast burn | 14.4 | 1h | 5m | Page |
| Medium burn | 6 | 6h | 30m | Page |
| Slow burn | 1 | 3d | 6h | Ticket |

Runbook: [link]

## Dependencies and caveats

- [Dependencies whose failures count or do not count against this SLO]
- [Known measurement gaps]
- [Low-traffic periods and how they are treated]

## Review log

| Date | Change | Who agreed |
| --- | --- | --- |
| [YYYY-MM-DD] | Initial version | [names] |
