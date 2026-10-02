# Setting up notification channels

The notifications module sends every alert to one Grafana contact point with
any combination of the channels below. Turn a channel on by setting its
variable; leave it null to keep it off. Every URL and token here is a secret:
keep it in a secret store and pass it in through a sensitive variable, never in
code.

Every channel gets the same title, for example
`🔴 FIRING: [homelab] Pod crash looping – api in prod`, then
`✅ RESOLVED: ...` when the alert clears. Resolves arrive as new messages, so
the title is what pairs them up.

## Sender avatar

Set `notifications.icon_url` to an image URL to use it as the sender's avatar
wherever the service allows it per message:

| Channel | Avatar |
| --- | --- |
| Slack | `icon_url` applies to every message. With a bot token, the app needs the `chat:write.customize` scope. |
| Webex, incoming webhook | Fixed by Webex: the webhook's initial. Use a bot for a custom avatar. |
| Webex, bot | The bot's avatar, set when you create the bot at <https://developer.webex.com/my-apps>. |
| Teams | The Workflows app's avatar. It can't be changed. |
| Email | None. |

```hcl
notifications = {
  icon_url = "https://example.com/logo.png"
}
```

## Slack

Two options.

**Incoming webhook.** Simplest. Posts as the Slack app that owns the webhook.

1. Go to <https://api.slack.com/apps>, create an app (or open an existing
   one), and turn on **Incoming Webhooks**.
2. Click **Add New Webhook to Workspace**, pick the channel, and copy the
   `https://hooks.slack.com/services/...` URL.

```hcl
slack = { url = var.slack_webhook_url }
```

**Bot token.** One token can post to any channel the bot is in.

1. In the app's **OAuth & Permissions**, add the `chat:write` bot scope, plus
   `chat:write.customize` to set the display name, and install the app.
2. Copy the **Bot User OAuth Token** (`xoxb-...`).
3. Invite the bot to the channel (`/invite @your-bot`), and copy the channel ID
   from the channel's details.

```hcl
slack = {
  recipient = "C0123456789"
  token     = var.slack_bot_token
  username  = "Alerts"  # Grafana posts as "Grafana" without this
}
```

## Microsoft Teams

Teams retired Office 365 connectors in favor of Workflows webhooks, which take
the Adaptive Card that Grafana sends.

1. In the Teams channel, open **⋯ → Workflows**.
2. Choose the template **Send webhook alerts to a channel** (also listed as
   "Post to a channel when a webhook request is received").
3. Name it, pick the team and channel, and click **Add workflow**.
4. Copy the URL it shows. It starts with
   `https://<region>.logic.azure.com/workflows/...` or, in newer tenants,
   `https://<tenant>.webhook.office.com/...`.

```hcl
teams = { url = var.teams_workflow_url }
```

Messages post as the account that created the workflow, through the Workflows
app. If that person leaves the organization, the workflow stops: create it with
a service account where possible.

## Webex

Two options.

**Incoming webhook.** No bot needed, so it works in organizations that block
Webex bot creation.

1. Open the **Incoming Webhooks** app in the Webex App Hub
   (<https://apphub.webex.com>, search "Incoming Webhooks") and click
   **Connect**.
2. Name the webhook, pick the space, and click **Add**.
3. Copy the `https://webexapis.com/v1/webhooks/incoming/...` URL.

```hcl
webex = { webhook_url = var.webex_webhook_url }
```

The module sends these through Grafana's generic webhook integration with a
Webex-shaped payload (`{"markdown": ...}`): the title in bold, then one line
per alert's summary. This needs Grafana 12 or later, for custom webhook
payloads.

**Bot.** Posts as a named bot, with the bot's own avatar, through Grafana's
built-in Webex integration. Messages look the same as the webhook mode's: the
title in bold, then one line per alert.

1. Create a bot at <https://developer.webex.com/my-apps> and copy its access
   token.
2. Add the bot to the space.
3. Find the space's room ID, for example with
   `curl -H "Authorization: Bearer $TOKEN" https://webexapis.com/v1/rooms`.

```hcl
webex = {
  room_id = "Y2lzY29zcGFyazovL..."
  token   = var.webex_bot_token
}
```

## Email

Grafana needs SMTP configured (`[smtp]` in `grafana.ini`, or the
`GF_SMTP_*` environment variables). With kube-prometheus-stack, set
`grafana."grafana.ini".smtp` in its values.

```hcl
notifications = {
  email = { addresses = ["oncall@example.com"] }
}
```

## Testing a channel

After applying, open **Alerting → Contact points** in Grafana, edit the
contact point, and click **Test** next to the channel. Grafana sends a sample
alert straight away, without waiting for a rule to fire.
