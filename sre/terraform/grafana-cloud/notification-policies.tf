resource "grafana_notification_policy" "root" {
  count = local.notifications_enabled ? 1 : 0

  contact_point = local.root_contact_point
  group_by      = ["environment", "team", "service", "severity"]

  group_wait      = "30s"
  group_interval  = "5m"
  repeat_interval = "4h"
}
