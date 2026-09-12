#!/usr/bin/env bash
# Usage: review-terraform.sh <findings-tsv> [changed-file...]
# Appends: file <TAB> line <TAB> BLOCK|WARN <TAB> rule <TAB> message

set -uo pipefail

FINDINGS="${1:?usage: review-terraform.sh <findings-tsv> [changed-file...]}"
shift
touch "$FINDINGS"

tf_files=()
for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        *.tf|*.tfvars) tf_files+=("$f") ;;
    esac
done

[ "${#tf_files[@]}" -eq 0 ] && exit 0

emit() {
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$FINDINGS"
}

# check <regex> <severity> <rule> <message>
check() {
    grep -HnE "$1" "${tf_files[@]}" 2>/dev/null | while IFS=: read -r file line _rest; do
        emit "$file" "$line" "$2" "$3" "$4"
    done
}

# 03-rbac-and-access-control.md / 02-authentication-and-identity.md

check 'azurerm_storage_account_sas|\bsas_token\s*=' \
    BLOCK 'rbac/no-sas-token' \
    'SAS token used where an azurerm_role_assignment to a managed identity would work. A leaked SAS token works for anyone until it expires or the key is rotated.'

check 'primary_access_key|secondary_access_key|primary_connection_string|secondary_connection_string|list_keys' \
    BLOCK 'rbac/no-access-keys' \
    'Static access key/connection string used where Azure AD + RBAC is available. Grant access via azurerm_role_assignment to a managed identity instead.'

check 'client_secret\s*=' \
    BLOCK 'auth/no-client-secret' \
    'Service principal client secret in use. Prefer OIDC/workload identity federation for CI and managed identity for resource-to-resource auth.'

check 'role_definition_name\s*=\s*"(Owner|Contributor)"' \
    BLOCK 'rbac/least-privilege' \
    'Owner/Contributor grants broad write access. Use the least-privileged built-in role for the job (e.g. Storage Blob Data Reader, Key Vault Secrets User).'

check 'scope\s*=\s*(data\.)?azurerm_subscription|scope\s*=\s*"/subscriptions/[^/"]*"' \
    BLOCK 'rbac/scope-too-broad' \
    'Role assignment scoped to the whole subscription. Scope it to the specific resource or resource group that actually needs access.'

check 'shared_access_key_enabled\s*=\s*true' \
    BLOCK 'rbac/disable-shared-key' \
    'Shared key auth left enabled. Set shared_access_key_enabled = false once consumers use Azure AD auth.'

check 'enable_rbac_authorization\s*=\s*false' \
    WARN 'rbac/key-vault-rbac' \
    'Key Vault using the legacy access-policy model. Prefer enable_rbac_authorization = true with role assignments.'

# 01-state-management.md
check '^\s*access_key\s*=' \
    BLOCK 'state/backend-azuread-auth' \
    'Backend authenticating with a storage access key. Use use_azuread_auth = true and grant the pipeline identity an RBAC role instead.'

check '\-lock=false' \
    BLOCK 'state/no-lock-disable' \
    'State locking disabled. Never disable locking for routine plan/apply.'

# 04-secrets-and-key-vault.md
check '(password|secret|api_key|access_token)[a-z_]*\s*=\s*"[^"$]{8,}"' \
    BLOCK 'secrets/no-hardcoded-secret' \
    'Looks like a hardcoded credential. Source it from Key Vault at apply time and never commit it.'

check 'purge_protection_enabled\s*=\s*false' \
    BLOCK 'secrets/key-vault-purge-protection' \
    'Key Vault purge protection disabled, so a deleted vault can be permanently purged with no recovery window.'

# 05-networking-and-private-access.md
check 'public_network_access_enabled\s*=\s*true' \
    BLOCK 'network/no-public-access' \
    'Public network access enabled. Disable it and reach the resource over a private endpoint unless there is a stated reason it must be publicly reachable.'

check 'source_address_prefix\s*=\s*"(\*|0\.0\.0\.0/0|Internet)"' \
    BLOCK 'network/no-open-ingress' \
    'NSG rule open to any source. Specify actual CIDR ranges, a service tag, or a specific subnet.'

check 'min_tls_version\s*=\s*"TLS1_(0|1)"' \
    BLOCK 'network/min-tls-12' \
    'Minimum TLS version below 1.2.'

check 'default_action\s*=\s*"Allow"' \
    BLOCK 'network/deny-by-default' \
    'Network ACL defaults to Allow. Default to Deny and grant specific networks/identities explicitly.'

check 'enable_https_traffic_only\s*=\s*false|https_only\s*=\s*false' \
    BLOCK 'network/https-only' \
    'HTTPS-only disabled, allowing plaintext traffic.'

# 08-resource-protection-and-lifecycle.md
check 'ignore_changes\s*=\s*all' \
    BLOCK 'lifecycle/no-ignore-all' \
    'ignore_changes = all hides every drift, including security-relevant changes. List only the specific attributes genuinely managed elsewhere.'

check '\-auto-approve' \
    WARN 'lifecycle/no-auto-approve' \
    'terraform apply -auto-approve skips plan review. Gate shared/production applies behind a reviewed plan.'

# prevent_destroy and management lock, checked per file
DATA_RESOURCES='azurerm_mssql_database|azurerm_mssql_server|azurerm_cosmosdb_account|azurerm_storage_account|azurerm_key_vault|azurerm_postgresql_flexible_server|azurerm_mysql_flexible_server'

for f in "${tf_files[@]}"; do
    grep -HnE "^\s*resource\s+\"($DATA_RESOURCES)\"" "$f" 2>/dev/null | while IFS=: read -r file line _rest; do
        if ! grep -qE 'prevent_destroy\s*=\s*true' "$file"; then
            emit "$file" "$line" BLOCK 'lifecycle/prevent-destroy' \
                'Data-bearing resource with no lifecycle { prevent_destroy = true }, so a mistaken destroy or replace silently deletes the data.'
        fi
        if ! grep -qE 'azurerm_management_lock' "$file"; then
            emit "$file" "$line" WARN 'lifecycle/management-lock' \
                'Data-bearing resource with no azurerm_management_lock (CanNotDelete). prevent_destroy only stops Terraform; it does not stop deletion via the Portal, CLI, or API.'
        fi
    done
done

exit 0
