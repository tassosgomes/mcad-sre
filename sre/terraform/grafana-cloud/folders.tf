resource "grafana_folder" "folders" {
  for_each = local.folders

  title = each.value
  uid   = "${replace(lower(each.key), "_", "-")}-${var.environment}"
}
