# alerts

Creates a Grafana folder and alert rule groups from the catalog in `catalog.tf`. See the root README for the rule list.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.5.0 |
| grafana | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| grafana | >= 4.0.0, < 5.0.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [grafana_folder.this](https://registry.terraform.io/providers/grafana/grafana/latest/docs/resources/folder) | resource |
| [grafana_rule_group.this](https://registry.terraform.io/providers/grafana/grafana/latest/docs/resources/rule_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster\_name | Name of the cluster. Added to every alert as the `cluster` label and to each rule title, so alerts from several clusters stay distinguishable in one Grafana. | `string` | n/a | yes |
| prometheus\_datasource\_uid | UID of the Prometheus-compatible Grafana datasource the rules query. | `string` | n/a | yes |
| cluster\_type | Kind of cluster: eks, aks, gke, openshift, k3s or generic. Managed control planes (eks, aks, gke) don't expose API server or etcd metrics, so those rules are left out for them. | `string` | `"generic"` | no |
| control\_plane | Override which control-plane metrics exist. Null keeps the cluster\_type default. For example, k3s only has etcd metrics when it runs embedded etcd instead of the default SQLite. | ```object({ apiserver = optional(bool) etcd = optional(bool) })``` | `{}` | no |
| disabled\_rules | IDs of catalog rules to leave out, such as `node_network_errors`. | `set(string)` | `[]` | no |
| evaluation\_interval\_seconds | How often Grafana evaluates each rule group. | `number` | `60` | no |
| folder\_title | Title of the Grafana folder that holds the alert rules. Defaults to "Kubernetes alerts (<cluster\_name>)". | `string` | `null` | no |
| labels | Extra labels added to every alert, for routing or ownership. | `map(string)` | `{}` | no |
| overrides | Per-rule changes, keyed by rule ID: threshold, pending period (`for`), severity, or a paused flag. | ```map(object({ threshold = optional(number) for = optional(string) severity = optional(string) paused = optional(bool) }))``` | `{}` | no |
| workload\_selector | PromQL label matchers added to every workload rule, to scope them. For example `namespace!="kube-system"`. Empty means all namespaces. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| folder\_uid | UID of the Grafana folder that holds the rules. |
| rule\_ids | IDs of the rules that were created, after cluster type, disabled\_rules and control\_plane are applied. |
| rules | The rules as created: group, title, query, threshold, pending period and severity, keyed by rule ID. |
<!-- END_TF_DOCS -->
