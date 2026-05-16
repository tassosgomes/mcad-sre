resource "grafana_dashboard" "service_overview" {
  folder    = grafana_folder.folders["overview"].uid
  overwrite = true

  config_json = templatefile("${path.module}/dashboards/service-overview.json.tftpl", {
    prometheus_datasource_uid = var.prometheus_datasource_uid
    environment               = var.environment
  })
}

resource "grafana_dashboard" "authz" {
  folder    = grafana_folder.folders["authz"].uid
  overwrite = true

  config_json = templatefile("${path.module}/dashboards/authz.json.tftpl", {
    prometheus_datasource_uid = var.prometheus_datasource_uid
    environment               = var.environment
    service_name              = "ecad-authz"
  })
}

resource "grafana_dashboard" "logs_overview" {
  folder    = grafana_folder.folders["overview"].uid
  overwrite = true

  config_json = templatefile("${path.module}/dashboards/logs-overview.json.tftpl", {
    loki_datasource_uid = var.loki_datasource_uid
    environment         = var.environment
  })
}
