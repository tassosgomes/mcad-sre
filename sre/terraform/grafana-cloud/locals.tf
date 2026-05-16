locals {
  folders = {
    overview   = "MCAD / Overview"
    services   = "MCAD / Services"
    infra      = "MCAD / Infra"
    authz      = "ECAD AuthZ"
    auditoria  = "ECAD Auditoria"
    slos       = "SLOs"
    synthetics = "Synthetic Monitoring"
  }

  notifications_enabled = var.alert_webhook_url != "" || length(var.alert_email_addresses) > 0
  root_contact_point = var.alert_webhook_url != "" ? try(grafana_contact_point.sre_webhook[0].name, null) : try(
    grafana_contact_point.sre_email[0].name,
    null,
  )
}
