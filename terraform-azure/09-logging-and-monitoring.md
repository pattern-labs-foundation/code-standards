# Logging & Monitoring

## 1. Diagnostic settings enabled on resources that support them

Resources should ship platform logs/metrics to a Log Analytics workspace (or Storage/Event
Hub, depending on the org's log-routing strategy) via an `azurerm_monitor_diagnostic_setting`
resource, rather than leaving diagnostics unconfigured and unobservable.

```hcl
resource "azurerm_monitor_diagnostic_setting" "kv_diagnostics" {
  name                       = "kv-diagnostics"
  target_resource_id         = azurerm_key_vault.kv.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "AuditEvent"
  }
  metric {
    category = "AllMetrics"
  }
}
```

**Flag:** a Key Vault, storage account, SQL server/database, App Service, or NSG with no
corresponding `azurerm_monitor_diagnostic_setting` anywhere in the codebase.

## 2. Audit-relevant resources specifically capture audit logs

Key Vault (`AuditEvent`), SQL (auditing/`extended_auditing_policy`), and storage (blob/queue
read-write-delete logging) should have their audit-specific log categories enabled - not just
generic metrics - since these are what let you answer "who accessed this secret/data and
when."

**Flag:** a diagnostic setting on an audit-relevant resource that only forwards `AllMetrics`
and omits the resource's audit/access log category.

## 3. Log retention is set deliberately, not left at a default that doesn't match policy

Log Analytics workspace retention (and any Storage-based log archival) should be set to match
the organization's actual compliance/retention requirements, rather than left at whatever the
provider's default happens to be.

```hcl
resource "azurerm_log_analytics_workspace" "this" {
  # ...
  retention_in_days = 90
}
```

**Flag:** `retention_in_days` omitted (relying on an unexamined default) on a workspace backing
production audit logs, when the organization has a stated retention requirement.

## 4. Alerting exists for security-relevant conditions, not just resource health

Beyond basic health/performance alerts, consider (and where the org has a defined policy,
require) alert rules for security-relevant signals available through Azure Monitor/Defender
for Cloud - e.g., a role assignment change at a sensitive scope, a Key Vault access policy
change, unusual sign-in activity - rather than only alerting on CPU/memory/availability.

**Flag:** an environment with `azurerm_monitor_metric_alert`/`azurerm_monitor_activity_log_alert`
resources covering only infrastructure health, with no alerting on access/permission changes
for resources holding secrets or sensitive data, where the org has stated this is required.

## 5. Diagnostic/log data itself is access-controlled

The Log Analytics workspace and any storage account used for log archival should follow the
same RBAC-over-keys and private-access principles as any other resource
(see [03-rbac-and-access-control.md](./03-rbac-and-access-control.md) and
[05-networking-and-private-access.md](./05-networking-and-private-access.md)) - logs often
contain sensitive operational detail and shouldn't be more loosely protected than the
resources they're logging.

**Flag:** a Log Analytics workspace or log-archival storage account with broader network/
access-key exposure than the resources whose logs it stores.
