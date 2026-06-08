#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

usage() {
    cat <<'EOF'
usage: docker_resource_report

Report Docker Swarm service reservations, limits, node placement capacity, and live local container usage.
Run on a Swarm manager for the node and service allocation sections.
EOF
}

bytes_to_mib() {
    awk -v bytes="${1:-0}" 'BEGIN { printf "%.0f", bytes / 1048576 }'
}

nano_to_cpu() {
    awk -v nano="${1:-0}" 'BEGIN { printf "%.3f", nano / 1000000000 }'
}

percent() {
    awk -v used="${1:-0}" -v total="${2:-0}" 'BEGIN { if (total > 0) printf "%.1f%%", used * 100 / total; else printf "n/a" }'
}

parse_bytes_expression() {
    local amount
    local unit
    local value="${1:-0B}"

    if [[ "$value" =~ ^([0-9.]+)([A-Za-z]+)$ ]]; then
        amount="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
    else
        printf '0'
        return 0
    fi

    awk -v amount="$amount" -v unit="$unit" '
        function to_bytes(amount, unit, normalized) {
            normalized = tolower(unit)
            if (normalized == "b" || normalized == "") return amount
            if (normalized == "kb") return amount * 1000
            if (normalized == "kib") return amount * 1024
            if (normalized == "mb") return amount * 1000 * 1000
            if (normalized == "mib") return amount * 1024 * 1024
            if (normalized == "gb") return amount * 1000 * 1000 * 1000
            if (normalized == "gib") return amount * 1024 * 1024 * 1024
            if (normalized == "tb") return amount * 1000 * 1000 * 1000 * 1000
            if (normalized == "tib") return amount * 1024 * 1024 * 1024 * 1024
            return amount
        }
        BEGIN {
            printf "%.0f", to_bytes(amount, unit)
        }'
}

print_swarm_node_allocations() {
    local nodes_file="$1"
    local tasks_file="$2"

    printf 'Swarm node allocation by reservations\n'
    if [ ! -s "$nodes_file" ]; then
        printf '  no Swarm nodes visible; run this command on a manager\n\n'
        return 0
    fi

    awk -F '\t' '
        FNR == NR {
            task_count[$1] += 1
            reserve_cpu[$1] += $3
            reserve_mem[$1] += $4
            limit_cpu[$1] += $5
            limit_mem[$1] += $6
            next
        }
        function cpu(nano) { return sprintf("%.3f", nano / 1000000000) }
        function mib(bytes) { return sprintf("%.0f", bytes / 1048576) }
        function pct(used, total) { return total > 0 ? sprintf("%.1f%%", used * 100 / total) : "n/a" }
        BEGIN {
            printf "%-28s %-10s %-8s %9s %12s %11s %9s %10s %12s %11s %9s %12s %9s %6s\n",
                "NODE", "AVAIL", "STATE", "CPU", "CPU_RES", "CPU_FREE", "CPU_%", "MEM_MIB", "MEM_RES_MIB", "MEM_FREE", "MEM_%", "CPU_LIMIT", "MEM_LIM", "TASKS"
        }
        {
            node = $1
            total_cpu = $2
            total_mem = $3
            cpu_free = total_cpu - reserve_cpu[node]
            mem_free = total_mem - reserve_mem[node]
            if (cpu_free < 0) cpu_free = 0
            if (mem_free < 0) mem_free = 0
            printf "%-28s %-10s %-8s %9s %12s %11s %9s %10s %12s %11s %9s %12s %9s %6d\n",
                node, $4, $5, cpu(total_cpu), cpu(reserve_cpu[node]), cpu(cpu_free), pct(reserve_cpu[node], total_cpu),
                mib(total_mem), mib(reserve_mem[node]), mib(mem_free), pct(reserve_mem[node], total_mem),
                cpu(limit_cpu[node]), mib(limit_mem[node]), task_count[node]
        }
    ' "$tasks_file" "$nodes_file"
    printf '\n'
}

print_swarm_service_allocations() {
    local services_file="$1"
    local tasks_file="$2"

    printf 'Swarm service reservations and limits\n'
    if [ ! -s "$services_file" ]; then
        printf '  no Swarm services visible\n\n'
        return 0
    fi

    awk -F '\t' '
        FNR == NR {
            assigned[$2] += 1
            next
        }
        function cpu(nano) { return sprintf("%.3f", nano / 1000000000) }
        function mib(bytes) { return sprintf("%.0f", bytes / 1048576) }
        BEGIN {
            printf "%-40s %8s %12s %11s %12s %11s %13s %12s\n",
                "SERVICE", "TASKS", "CPU_RES_EA", "MEM_RES_EA", "CPU_LIM_EA", "MEM_LIM_EA", "CPU_RES_SUM", "MEM_RES_SUM"
        }
        {
            service = $2
            tasks = assigned[service]
            printf "%-40s %8d %12s %11s %12s %11s %13s %12s\n",
                service, tasks, cpu($3), mib($4), cpu($5), mib($6), cpu($3 * tasks), mib($4 * tasks)
        }
    ' "$tasks_file" "$services_file"
    printf '\n'
}

print_local_live_usage() {
    local stats_file="$1"
    local cpu_percent_total=0
    local mem_bytes_total=0
    local mem_total_mib
    local mem_used_mib

    printf 'Local host live usage\n'
    if command -v free >/dev/null 2>&1; then
        mem_total_mib=$(free -m | awk '/^Mem:/ { print $2 }')
        mem_used_mib=$(free -m | awk '/^Mem:/ { print $3 }')
        printf '  host memory used: %s MiB / %s MiB (%s)\n' "$mem_used_mib" "$mem_total_mib" "$(percent "$mem_used_mib" "$mem_total_mib")"
    fi

    if [ ! -s "$stats_file" ]; then
        printf '  no local running containers reported by docker stats\n\n'
        return 0
    fi

    while IFS=$'\t' read -r cpu_percent mem_usage; do
        cpu_percent=${cpu_percent%%%}
        cpu_percent_total=$(awk -v total="$cpu_percent_total" -v cpu="$cpu_percent" 'BEGIN { printf "%.2f", total + cpu }')
        mem_bytes_total=$(awk -v total="$mem_bytes_total" -v bytes="$(parse_bytes_expression "${mem_usage%% / *}")" 'BEGIN { printf "%.0f", total + bytes }')
    done <"$stats_file"

    printf '  docker stats CPU sum: %s%%\n' "$cpu_percent_total"
    printf '  docker stats memory sum: %s MiB\n\n' "$(bytes_to_mib "$mem_bytes_total")"
}

main() {
    local arg
    local nodes_file
    local services_file
    local stats_file
    local tasks_file

    for arg in "$@"; do
        case "$arg" in
        -h | --help)
            usage
            return 0
            ;;
        *)
            _usage_error "docker_resource_report: unknown argument: $arg"
            ;;
        esac
    done

    _require_command docker

    nodes_file=$(mktemp)
    services_file=$(mktemp)
    tasks_file=$(mktemp)
    stats_file=$(mktemp)
    trap 'rm -f "$nodes_file" "$services_file" "$tasks_file" "$stats_file"' EXIT

    if docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null | grep -q '^true$'; then
        while IFS= read -r node_id; do
            docker node inspect --format '{{.Description.Hostname}}	{{.Description.Resources.NanoCPUs}}	{{.Description.Resources.MemoryBytes}}	{{.Spec.Availability}}	{{.Status.State}}' "$node_id"
        done < <(docker node ls -q) >"$nodes_file"

        while IFS= read -r service_id; do
            docker service inspect --format '{{.ID}}	{{.Spec.Name}}	{{with .Spec.TaskTemplate.Resources}}{{with .Reservations}}{{.NanoCPUs}}{{else}}0{{end}}{{else}}0{{end}}	{{with .Spec.TaskTemplate.Resources}}{{with .Reservations}}{{.MemoryBytes}}{{else}}0{{end}}{{else}}0{{end}}	{{with .Spec.TaskTemplate.Resources}}{{with .Limits}}{{.NanoCPUs}}{{else}}0{{end}}{{else}}0{{end}}	{{with .Spec.TaskTemplate.Resources}}{{with .Limits}}{{.MemoryBytes}}{{else}}0{{end}}{{else}}0{{end}}' "$service_id"
        done < <(docker service ls -q) >"$services_file"

        while IFS=$'\t' read -r service_id service_name reserve_cpu reserve_mem limit_cpu limit_mem; do
            docker service ps --no-trunc --filter desired-state=running --format '{{.Node}}	{{.CurrentState}}' "$service_id" |
                awk -F '\t' -v service="$service_name" -v reserve_cpu="$reserve_cpu" -v reserve_mem="$reserve_mem" -v limit_cpu="$limit_cpu" -v limit_mem="$limit_mem" '
                    $1 != "" && $2 !~ /^Rejected/ {
                        print $1 "\t" service "\t" reserve_cpu "\t" reserve_mem "\t" limit_cpu "\t" limit_mem
                    }
                '
        done <"$services_file" >"$tasks_file"
    else
        _warn "docker_resource_report: this node is not a Swarm manager; skipping Swarm allocation sections"
    fi

    docker stats --no-stream --format '{{.CPUPerc}}	{{.MemUsage}}' >"$stats_file" 2>/dev/null || true

    print_swarm_node_allocations "$nodes_file" "$tasks_file"
    print_swarm_service_allocations "$services_file" "$tasks_file"
    print_local_live_usage "$stats_file"
    printf 'Scheduler note: Swarm placement uses reservations, not live docker stats usage. During start-first updates, a node may need enough free reservation headroom for an extra replacement task.\n'
}

main "$@"
