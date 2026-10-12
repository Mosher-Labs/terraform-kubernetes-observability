# Postmortem: [short incident title]

<!--
How to use
- Based on the Google SRE Book example postmortem (Appendix D) and the
  SRE Workbook postmortem chapter.
- Blameless: describe what the system and process allowed, not what a person
  did wrong. Write "the deploy tool allowed X", not "[name] ran X by mistake".
- Write it within [3 working days] of resolution. Review it with the team.
  An unreviewed postmortem might as well not exist.
- Every action item has one owner, one tracking link and a priority.
- Prefer fixes in tooling and process over "be more careful" or "train people".
- Delete this comment block when you copy the file.
-->

| Field | Value |
| --- | --- |
| Date of incident | [YYYY-MM-DD] |
| Authors | [names or roles] |
| Status | [draft / in review / complete] |
| Severity | [level] |
| Incident document | [link] |
| Reviewed on | [YYYY-MM-DD] |

## Summary

[One or two sentences: what broke, for how long, and the main cause.]

## Impact

- Duration: [start] to [end] ([N] minutes)
- Users or systems affected: [who, how many, which regions or environments]
- Failed requests, lost data or lost revenue: [numbers, or "none"]
- Error budget consumed: [percent of period budget, if an SLO exists]

## Timeline

All times in [UTC]. Include detection, key decisions, and each mitigation step.

| Time | Event |
| --- | --- |
| [HH:MM] | [Trigger happened] |
| [HH:MM] | [Alert fired, or someone noticed] |
| [HH:MM] | [Incident declared; roles assigned] |
| [HH:MM] | [Mitigation applied] |
| [HH:MM] | [Service restored] |

## Root causes

[The conditions that allowed the failure, found with the five whys. Ask why
the failure happened, then ask why about each answer, until you reach
something an action item can fix. That can take fewer than five. Keep each
answer about the system or the process, not a person. Start another chain for
each cause when there is more than one.]

Cause 1:

1. Why [did the failure happen]? Because [answer 1].
2. Why [answer 1]? Because [answer 2].
3. Why [answer 2]? Because [answer 3].
4. Why [answer 3]? Because [answer 4].
5. Why [answer 4]? Because [answer 5].

Root cause: [the last answer, the one the action items fix]

## Trigger

[The event that set it off: a deploy, a config change, a traffic spike, an
expired certificate.]

## Resolution

[What stopped the impact. Name the mitigation and the permanent fix if they
differ.]

## Detection

[How we found out: alert name, customer report, or luck.] Time from trigger to
detection: [N] minutes. [Did the right alert page the right person? Why wasn't
it caught earlier?]

## Action items

| Action | Type | Priority | Owner | Tracking | Due |
| --- | --- | --- | --- | --- | --- |
| [Specific, measurable change] | [prevent / detect / mitigate / process] | [P0-P2] | [one name] | [link] | [date] |

Types: prevent stops the cause, detect finds it sooner, mitigate limits the
impact, process fixes how we respond.

## Lessons learned

### What went well

- [for example, "The alert fired within two minutes."]

### What went badly

- [for example, "The runbook was out of date."]

### Where we got lucky

- [Things that limited impact by chance and could not be counted on again.]

## Supporting information

- Dashboards and graphs: [links, screenshots]
- Logs and queries: [links]
- Chat or call record: [link]
- Related incidents: [links]
