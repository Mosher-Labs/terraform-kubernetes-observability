terraform {
  required_version = ">= 1.15.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
}
