# Networking & Private Access

## 1. Disable public network access on PaaS resources by default

Storage accounts, Key Vault, SQL/Cosmos DB, and similar managed services should have public
network access disabled and reached via Private Link/private endpoints, unless there's a
specific, stated reason a resource needs to be publicly reachable (e.g., a genuinely public
static website).

```hcl
# Bad - default public access left open
resource "azurerm_storage_account" "data" {
  # ... no network restriction at all
}

# Good
resource "azurerm_storage_account" "data" {
  # ...
  public_network_access_enabled = false
}

resource "azurerm_private_endpoint" "data_blob" {
  name                = "pe-st-data-blob"
  location            = azurerm_storage_account.data.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "st-data-blob"
    private_connection_resource_id = azurerm_storage_account.data.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}
```

**Flag:** `public_network_access_enabled` left at its default (`true`) or explicitly `true`
on a resource holding non-public data, with no private endpoint and no documented reason.

## 2. No `0.0.0.0/0` (or equivalent "any") rules in NSGs or firewall rules

Network Security Group rules and resource-level firewall/network rules should specify actual
source ranges (specific CIDR blocks, an Azure service tag, or a specific subnet/VNet) rather
than allowing all sources.

```hcl
# Bad
resource "azurerm_network_security_rule" "allow_all" {
  source_address_prefix      = "*"
  destination_port_range     = "*"
  access                      = "Allow"
  direction                   = "Inbound"
  # ...
}

# Good
resource "azurerm_network_security_rule" "allow_https_from_gateway" {
  source_address_prefix      = azurerm_subnet.app_gateway.address_prefixes[0]
  destination_port_range     = "443"
  access                      = "Allow"
  direction                   = "Inbound"
  # ...
}
```

**Flag:** `source_address_prefix = "*"` or `"0.0.0.0/0"` combined with `access = "Allow"` on
an inbound rule, especially for management ports (22, 3389, 5985/5986) or database ports.

## 3. Management ports are never open to the internet

RDP (3389), SSH (22), and direct database ports should not be reachable from `Internet`/`*` in
any NSG rule. Use Azure Bastion, a jump box on a private network, VPN/ExpressRoute, or
just-in-time (JIT) VM access instead of opening these ports broadly.

**Flag:** an NSG rule allowing inbound traffic on 22/3389 (or a database's default port) from
any source broader than a specific known management network/Bastion subnet.

## 4. Segment networks by function/trust boundary

Use separate subnets (and, where appropriate, separate VNets with peering) for different
tiers/trust levels - e.g., a subnet for private endpoints, a subnet for application
compute, a subnet for data services - rather than placing everything in one flat address
space with no NSGs between tiers.

**Flag:** all resources placed in a single subnet with no NSG associated, especially when the
resources span clearly different trust levels (public-facing compute vs. data stores).

## 5. TLS/HTTPS enforced, minimum TLS version pinned

Resources exposing an endpoint (App Service, Storage, API Management, etc.) should require
HTTPS/TLS and pin a minimum TLS version (1.2 or higher) rather than accepting the platform
default, which may be older for backward compatibility.

```hcl
resource "azurerm_storage_account" "data" {
  # ...
  min_tls_version           = "TLS1_2"
  enable_https_traffic_only = true
}
```

**Flag:** `min_tls_version` omitted or set below `TLS1_2`; `enable_https_traffic_only`
(or the resource's equivalent HTTPS-only setting) explicitly disabled.

## 6. Diagnostic/flow logging enabled on network boundaries

NSGs and any resource acting as a network boundary should have flow logs / diagnostic
settings enabled and routed to a Log Analytics workspace, so network traffic is auditable
(see [09-logging-and-monitoring.md](./09-logging-and-monitoring.md)).

**Flag:** an NSG or VNet with no associated flow log / diagnostic setting resource anywhere in
the codebase.
