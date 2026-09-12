#!/usr/bin/env bash
# Checks changed C# files against the mechanically-verifiable rules in
# csharp/REVIEW-CHECKLIST.md.
#
# Usage: review-csharp.sh <findings-tsv> [changed-file...]
# Appends findings as: file <TAB> line <TAB> severity <TAB> rule <TAB> message
# Severity is BLOCK (a real defect) or WARN (worth a look, may be intentional).

set -uo pipefail

FINDINGS="${1:?usage: review-csharp.sh <findings-tsv> [changed-file...]}"
shift
touch "$FINDINGS"

cs_files=()
csproj_files=()
config_files=()
for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        *.cs) cs_files+=("$f") ;;
        *.csproj) csproj_files+=("$f") ;;
        *appsettings*.json) config_files+=("$f") ;;
    esac
done

emit() {
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$FINDINGS"
}

# check <regex> <severity> <rule> <message> -- <file...>
check() {
    local regex="$1" severity="$2" rule="$3" message="$4"
    shift 5 # drop the four args plus the "--" separator
    [ "$#" -eq 0 ] && return 0
    grep -HnE "$regex" "$@" 2>/dev/null | while IFS=: read -r file line _rest; do
        emit "$file" "$line" "$severity" "$rule" "$message"
    done
}

if [ "${#cs_files[@]}" -gt 0 ]; then
    # 04-async-and-concurrency.md
    check '\.(Result)\s*[;,)]|\.Wait\(\)|\.GetAwaiter\(\)\.GetResult\(\)' \
        BLOCK 'async/no-sync-over-async' \
        'Blocking on async code (.Result/.Wait()/.GetAwaiter().GetResult()) risks deadlock and thread-pool starvation. Await it instead.' \
        -- "${cs_files[@]}"

    check 'async\s+void\s+' \
        BLOCK 'async/no-async-void' \
        'async void cannot be awaited and its exceptions cannot be caught by the caller. Use async Task (event handlers are the only exception).' \
        -- "${cs_files[@]}"

    # 05-error-handling.md
    check 'throw\s+(ex|e|exception|error)\s*;' \
        BLOCK 'errors/rethrow-resets-stack' \
        'throw ex; resets the stack trace. Use a bare throw; to rethrow, or wrap the original as an InnerException.' \
        -- "${cs_files[@]}"

    check 'catch\s*(\([^)]*\))?\s*\{\s*\}' \
        BLOCK 'errors/empty-catch' \
        'Empty catch block swallows the error silently. Handle it, add context and rethrow, or let it propagate.' \
        -- "${cs_files[@]}"

    check 'throw\s+new\s+Exception\s*\(' \
        WARN 'errors/specific-exception-type' \
        'Throw a specific exception type (or a meaningful domain exception) rather than bare Exception.' \
        -- "${cs_files[@]}"

    # 06-logging-and-observability.md
    check 'Console\.(WriteLine|Write)\s*\(' \
        WARN 'logging/no-console-writeline' \
        'Use an injected ILogger<T> rather than Console.WriteLine for application logging.' \
        -- "${cs_files[@]}"

    check 'Log(Information|Warning|Error|Debug|Trace|Critical)\s*\(\s*\$"' \
        BLOCK 'logging/structured-templates' \
        'String interpolation in a log call destroys structured logging. Use a message template with named placeholders: logger.LogInformation("... {OrderId}", id).' \
        -- "${cs_files[@]}"

    # 10-performance.md
    check 'new\s+HttpClient\s*\(' \
        BLOCK 'performance/httpclient-factory' \
        'new HttpClient() per call can exhaust sockets under load. Use IHttpClientFactory or a registered typed client.' \
        -- "${cs_files[@]}"

    # 02-dependency-injection.md / 08-data-access-ef-core.md
    check 'AddSingleton<[^>]*DbContext' \
        BLOCK 'di/dbcontext-not-singleton' \
        'DbContext is not thread-safe and must be Scoped, never Singleton.' \
        -- "${cs_files[@]}"

    # 09-security.md
    check 'FromSqlRaw\s*\(\s*\$?"[^"]*\{' \
        BLOCK 'security/sql-injection' \
        'Interpolated/concatenated SQL is an injection risk. Use FromSqlInterpolated or explicit parameters.' \
        -- "${cs_files[@]}"

    check '(Password|password|pwd)\s*=\s*"[^";{]{6,}"' \
        BLOCK 'security/hardcoded-secret' \
        'Looks like a hardcoded credential. Move it to configuration bound via IOptions<T>, sourced from a secret store.' \
        -- "${cs_files[@]}"

    # 03-configuration-and-options.md: IConfiguration outside the composition root.
    app_files=()
    for f in "${cs_files[@]}"; do
        case "$(basename "$f")" in
            Program.cs|Startup.cs|*Extensions.cs|*ServiceCollection*.cs) ;;
            *) app_files+=("$f") ;;
        esac
    done
    if [ "${#app_files[@]}" -gt 0 ]; then
        check 'IConfiguration\s+[a-z_][A-Za-z0-9_]*\s*[,)]' \
            BLOCK 'config/no-iconfiguration-injection' \
            'IConfiguration injected outside the composition root. Bind a strongly-typed options class and inject IOptions<T> instead.' \
            -- "${app_files[@]}"

        check '_config(uration)?\s*\[\s*"' \
            BLOCK 'config/no-magic-string-lookup' \
            'String-keyed configuration lookup in application code. Use a bound options class instead of magic-string keys.' \
            -- "${app_files[@]}"
    fi
fi

# 12-nullable-reference-types.md: project-level enforcement settings.
for proj in "${csproj_files[@]:-}"; do
    [ -f "$proj" ] || continue
    if ! grep -qE '<Nullable>\s*enable\s*</Nullable>' "$proj"; then
        emit "$proj" 1 BLOCK 'nullable/enable' \
            'Project is missing <Nullable>enable</Nullable>, so nullable reference type analysis is off entirely.'
    fi
    if ! grep -qE '<TreatWarningsAsErrors>\s*true\s*</TreatWarningsAsErrors>' "$proj"; then
        emit "$proj" 1 WARN 'nullable/warnings-as-errors' \
            'Project is missing <TreatWarningsAsErrors>true</TreatWarningsAsErrors>. Without it a possible null is only a warning and the build still succeeds.'
    fi
done

# 03-configuration-and-options.md: secrets committed in appsettings.
if [ "${#config_files[@]}" -gt 0 ]; then
    check '"[^"]*(Password|Pwd|AccountKey|SharedAccessKey)[^"]*"\s*:\s*"[^"{]{6,}"' \
        BLOCK 'config/secret-in-appsettings' \
        'Looks like a real credential committed in appsettings. Use user-secrets locally and a secret store (Key Vault, env vars) in deployed environments.' \
        -- "${config_files[@]}"

    check '"(ConnectionString|DefaultConnection)"\s*:\s*"[^"]*(Password|Pwd)=' \
        BLOCK 'config/secret-in-appsettings' \
        'Connection string with an embedded password committed to source control.' \
        -- "${config_files[@]}"
fi

exit 0
