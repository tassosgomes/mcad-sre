resource "grafana_contact_point" "sre_email" {
  count = length(var.alert_email_addresses) > 0 ? 1 : 0

  name = "mcad-sre-${var.environment}-email"

  email {
    addresses               = var.alert_email_addresses
    single_email            = true
    disable_resolve_message = false
    subject                 = "[{{ .Status | toUpper }}] {{ template \"default.title\" . }}"
    message                 = "{{ template \"default.message\" . }}"
  }
}

resource "grafana_contact_point" "sre_webhook" {
  count = var.alert_webhook_url != "" ? 1 : 0

  name = "mcad-sre-${var.environment}-webhook"

  webhook {
    url                     = var.alert_webhook_url
    disable_resolve_message = false
  }
}
