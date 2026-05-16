resource "grafana_dashboard" "service_overview" {
  folder    = grafana_folder.folders["overview"].uid
  overwrite = true

  config_json = templatefile("${path.module}/dashboards/service-overview.json.tftpl", {
    prometheus_datasource_uid = var.prometheus_datasource_uid
    environment               = var.environment
  })
}
