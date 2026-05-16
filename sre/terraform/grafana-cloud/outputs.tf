output "folder_uids" {
  description = "UIDs dos folders criados no Grafana."
  value       = { for key, folder in grafana_folder.folders : key => folder.uid }
}

output "notifications_enabled" {
  description = "Indica se uma notification policy raiz foi criada."
  value       = nonsensitive(local.notifications_enabled)
}
