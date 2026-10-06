terraform {
  required_version = "1.16.5"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "4.24.0"
    }
  }
}
