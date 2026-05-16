variable "environment" {
  description = "Ambiente provisionado no Grafana Cloud."
  type        = string
  default     = "prod"
}

variable "grafana_url" {
  description = "URL do stack Grafana, por exemplo https://mcad.grafana.net."
  type        = string
}

variable "grafana_auth" {
  description = "Service account token do Grafana usado pelo Terraform."
  type        = string
  sensitive   = true
}

variable "prometheus_datasource_uid" {
  description = "UID do datasource Prometheus/Mimir no Grafana Cloud."
  type        = string
  default     = "grafanacloud-prom"
}

variable "alert_email_addresses" {
  description = "Lista de e-mails para alertas. Se vazia, o contact point de e-mail nao e criado."
  type        = list(string)
  default     = []
}

variable "alert_webhook_url" {
  description = "Webhook Prometheus Alertmanager-compatible para alertas. Se vazio, nao e criado."
  type        = string
  default     = ""
  sensitive   = true
}
