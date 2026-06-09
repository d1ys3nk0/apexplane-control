#!/usr/bin/env bash

# shellcheck shell=bash
# System Report Tool: boxed snapshots for system, Docker, and fixed-name stack containers.
# sysrep system ends with a long “extended” block (journal, dmesg, ss, FDs, systemd, exporters).

set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

HR_DOCKER_TIMEOUT="${HR_DOCKER_TIMEOUT:-10}"
HR_DOCKER_QUICK="${HR_DOCKER_QUICK:-3}"

usage() {
    printf 'Usage: %s <report>\n' "$(basename "$0")" >&2
    printf '  Reports: system docker postgres redis elasticsearch rabbitmq haproxy promtail monitoring\n' >&2
    printf '  system  — load, memory, disk, PSI, ss, journal, dmesg, systemd, FDs, zombies, exporters\n' >&2
}

# ── shared theme / frame ────────────────────────────────────────────────────

hr_theme_init() {
    hr_R="" hr_B="" hr_red="" hr_yel="" hr_grn="" hr_blu=""
    if [[ -t 1 ]]; then
        hr_R=$'\033[0m'
        hr_B=$'\033[1m'
        hr_red=$'\033[1;31m'
        hr_yel=$'\033[1;33m'
        hr_grn=$'\033[1;32m'
        hr_blu=$'\033[1;34m'
    fi
}

hr_rule_eq() {
    printf '%s\n' "${hr_blu}+==============================================================================+${hr_R}"
}

hr_rule_dash() {
    printf '%s\n' "${hr_blu}+------------------------------------------------------------------------------+${hr_R}"
}

# Inner width between "|" and "|" is 78 chars; "|   " leaves 75 for title text.
hr_title_row() {
    local title=$1
    printf '%s\n' "${hr_blu}|   $(printf '%-75s' "$title")|${hr_R}"
}

hr_meta_host_time() {
    local host now
    host=$(hostname -s 2>/dev/null || hostname)
    now=$(date '+%Y-%m-%d %H:%M:%S %Z')
    printf '%s\n' "| Host       : ${hr_B}${host}${hr_R}"
    printf '%s\n' "| Time       : ${now}"
}

hr_report_header() {
    hr_rule_eq
    hr_title_row "$1"
    hr_rule_eq
    hr_meta_host_time
}

hr_report_footer() {
    hr_rule_eq
}

hr_indent_stream() {
    while IFS= read -r line || [[ -n $line ]]; do
        printf '%s\n' "|   $line"
    done
}

hr_section() {
    hr_rule_dash
    printf '%s\n' "| $1"
    hr_rule_dash
}

# ── docker invocation (sudo, optional timeout) ──────────────────────────────

hr__docker_run() {
    local to=$1
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$to" sudo docker "$@"
    else
        sudo docker "$@"
    fi
}

hr_docker() {
    hr__docker_run "$HR_DOCKER_TIMEOUT" "$@"
}

hr_docker_quick() {
    hr__docker_run "$HR_DOCKER_QUICK" "$@"
}

hr_docker_has() {
    hr_docker_quick inspect --format '{{.State.Status}}' "$1" &>/dev/null
}

hr_docker_client_label() {
    printf '%s' "sudo docker"
}

hr_need_docker_or_exit() {
    if ! command -v docker >/dev/null 2>&1; then
        hr_rule_eq
        hr_title_row "Docker (no client)"
        hr_rule_eq
        hr_meta_host_time
        printf '%s\n' "| Status     : no docker client in PATH (try: sysrep system)"
        hr_rule_eq
        exit 0
    fi
}

hr_service_skip() {
    local name=$1
    hr_section "Skipping"
    printf '%s\n' "|   No container named '${name}' (nothing to show)."
}

hr_run() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        "$@"
    fi
}

hr_run_timeout() {
    local to=$1
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "$to" "$@"
    else
        "$@"
    fi
}

# Extended host diagnostics (journal, dmesg, ss, FDs, …) — keep report_system() summary readable.
hr_system_extended() {
    local jn=150

    hr_section "TCP: socket summary (ss -s)"
    if command -v ss >/dev/null 2>&1; then
        ss -s 2>&1 | hr_indent_stream
    else
        printf '%s\n' "ss not installed" | hr_indent_stream
    fi

    hr_section "TCP: counts by state (ss -ant)"
    if command -v ss >/dev/null 2>&1; then
        ss -ant 2>/dev/null | awk 'NR > 1 { print $1 }' | sort | uniq -c | sort -rn | hr_indent_stream
    else
        printf '%s\n' "ss not installed" | hr_indent_stream
    fi

    hr_section "TCP: top processes by attached sockets (heuristic)"
    if command -v ss >/dev/null 2>&1; then
        ss -antp 2>/dev/null | awk '{print $NF}' | sed -E 's/users:\(\("([^"]+)".*/\1/; t; d' | sort | uniq -c | sort -nr | head -20 | hr_indent_stream
    else
        printf '%s\n' "ss not installed" | hr_indent_stream
    fi

    hr_section "TCP: listening sockets (ss -lntp, first 40 lines)"
    if command -v ss >/dev/null 2>&1; then
        ss -lntp 2>&1 | head -40 | hr_indent_stream
    else
        printf '%s\n' "ss not installed" | hr_indent_stream
    fi

    hr_section "Swap devices (swapon --show)"
    if command -v swapon >/dev/null 2>&1; then
        swapon --show --bytes 2>&1 | hr_indent_stream
    else
        printf '%s\n' "swapon not available" | hr_indent_stream
    fi

    hr_section "vmstat (instant snapshot)"
    if command -v vmstat >/dev/null 2>&1; then
        vmstat 2>&1 | hr_indent_stream
    else
        printf '%s\n' "vmstat not installed" | hr_indent_stream
    fi

    hr_section "Disk usage (df -h, real filesystems)"
    df -P -x tmpfs -x devtmpfs -h 2>/dev/null | head -40 | hr_indent_stream

    hr_section "Failed systemd units (systemctl --failed)"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --failed --no-pager 2>&1 | hr_indent_stream
    else
        printf '%s\n' "systemctl not available" | hr_indent_stream
    fi

    hr_section "Systemd default resource limits"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl show --property DefaultLimitNOFILE --property DefaultLimitNPROC --property DefaultTasksMax --no-pager 2>&1 | hr_indent_stream
    else
        printf '%s\n' "systemctl not available" | hr_indent_stream
    fi

    hr_section "sshd unit limits (ssh & sshd)"
    if command -v systemctl >/dev/null 2>&1; then
        hr_run systemctl show ssh sshd -p LimitNOFILE -p LimitNPROC -p TasksMax -p FragmentPath -p DropInPaths --no-pager 2>/dev/null | hr_indent_stream || printf '%s\n' "(not available)" | hr_indent_stream
    fi

    hr_section "Docker unit limits (docker / docker.socket)"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl show docker docker.socket -p LimitNOFILE -p LimitNPROC -p TasksMax -p FragmentPath -p DropInPaths --no-pager 2>/dev/null | hr_indent_stream || printf '%s\n' "(no docker unit or not applicable)" | hr_indent_stream
    fi

    hr_section "PostgreSQL units on host (systemd limits, if any)"
    (
        any=0
        while read -r u; do
            [[ -z $u ]] && continue
            any=1
            printf '%s\n' "### $u"
            hr_run systemctl show "$u" -p LimitNOFILE -p LimitNPROC -p TasksMax -p FragmentPath -p DropInPaths --no-pager 2>/dev/null || true
            printf '\n'
        done < <(systemctl list-units --type=service --all --no-pager 2>/dev/null | awk '{ print $1 }' | grep -E '^postgresql' || true)
        [[ $any -eq 0 ]] && printf '%s\n' "(no postgresql*.service units)"
    ) | hr_indent_stream

    hr_section "Global file descriptors (/proc/sys/fs/file-nr, sysctl)"
    {
        awk '{printf "allocated / unused / max: %s / %s / %s\n", $1, $2, $3}' /proc/sys/fs/file-nr 2>/dev/null || printf '%s\n' "(cannot read file-nr)"
        if command -v sysctl >/dev/null 2>&1; then
            sysctl fs.file-max fs.nr_open 2>/dev/null || true
        fi
    } | hr_indent_stream

    hr_section "Top processes by open FD count (may take a few seconds)"
    if [[ ! -d /proc ]]; then
        printf '%s\n' "/proc not available" | hr_indent_stream
    else
        {
            for p in /proc/[0-9]*; do
                pid=${p#/proc/}
                comm=$(tr -d '\0' <"$p/comm" 2>/dev/null || echo "?")
                user=$(stat -c '%U' "$p" 2>/dev/null || echo "?")
                cnt=$(find "$p/fd" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
                printf '%s\n' "$cnt $pid $user $comm"
            done | sort -nr | head -20
        } 2>/dev/null | hr_indent_stream
    fi

    hr_section "Zombie processes (header + up to 40 lines)"
    ps -eo pid,ppid,stat,comm 2>/dev/null | awk 'NR == 1 || $3 ~ /Z/' | head -40 | hr_indent_stream

    hr_section "Uninterruptible D-state (header + up to 40 lines)"
    ps -eo pid,ppid,stat,wchan:32,comm 2>/dev/null | awk 'NR == 1 || $3 ~ /D/' | head -40 | hr_indent_stream

    hr_section "Process counts by user (top 15)"
    ps -eo user= 2>/dev/null | sort | uniq -c | sort -nr | head -15 | hr_indent_stream

    hr_section "Sample /proc/PID/limits (newest sshd, dockerd)"
    {
        for name in sshd dockerd; do
            pid=$(pgrep -n "$name" 2>/dev/null || true)
            if [[ -n $pid && -r /proc/$pid/limits ]]; then
                printf '%s\n' "--- $name pid=$pid ---"
                cat "/proc/$pid/limits"
            fi
        done
    } | hr_indent_stream

    hr_section "dmesg: OOM / kill lines (last 30 matches)"
    { hr_run dmesg -T 2>/dev/null | grep -iE 'oom|out of memory|killed process' || true; } | tail -30 | hr_indent_stream

    hr_section "dmesg: errors / panic / hung_task (last 30 matches)"
    { hr_run dmesg -T 2>/dev/null | grep -iE 'error|fail|bug|panic|hung_task|blocked for more than' || true; } | tail -30 | hr_indent_stream

    hr_section "dmesg: FD exhaustion signals (recent, filtered)"
    { hr_run dmesg -T 2>/dev/null | tail -120 | grep -Ei 'file-max|file table|ENFILE|EMFILE|too many open' || true; } | tail -20 | hr_indent_stream

    hr_section "Journal: kernel errors this boot (tail 40)"
    hr_run journalctl -k -b 0 --no-pager -p err 2>/dev/null | tail -40 | hr_indent_stream || printf '%s\n' "(journal not available)" | hr_indent_stream

    hr_section "Journal: err priority this boot (tail 50, short-iso)"
    hr_run journalctl -b 0 --no-pager -p err --no-hostname -o short-iso 2>/dev/null | tail -50 | hr_indent_stream || true

    hr_section "Journal: docker unit this boot (tail 40)"
    hr_run journalctl -u docker -b 0 --no-pager -n 120 2>/dev/null | tail -40 | hr_indent_stream || true

    hr_section "Journal: previous boot — kernel / ssh / postgresql snippets"
    {
        printf '%s\n' "--- kernel (boot -1), stress/OOM filter ---"
        hr_run journalctl -k -b -1 --no-pager 2>/dev/null | grep -iE 'oom|out of memory|killed process|file.table|file-max|ENFILE|EMFILE|too many open files|panic|bug|hung_task' | tail -40 || true
        printf '%s\n' "--- ssh (boot -1, last $jn lines) ---"
        hr_run journalctl -u ssh -u sshd -b -1 --no-pager -n "$jn" 2>/dev/null || true
        printf '%s\n' "--- postgresql* (boot -1, last $jn lines) ---"
        hr_run journalctl -u 'postgresql*' -b -1 --no-pager -n "$jn" 2>/dev/null || true
    } | hr_indent_stream

    hr_section "systemd timers (first 22 lines)"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl list-timers --all --no-pager 2>/dev/null | head -22 | hr_indent_stream || true
    else
        printf '%s\n' "systemctl not available" | hr_indent_stream
    fi

    hr_section "node_exporter smoke (127.0.0.1:49100/metrics, first lines)"
    if command -v curl >/dev/null 2>&1; then
        curl -sS --max-time 3 http://127.0.0.1:49100/metrics 2>&1 | head -8 | hr_indent_stream || printf '%s\n' "(unreachable or error)" | hr_indent_stream
    else
        printf '%s\n' "curl not installed" | hr_indent_stream
    fi

    hr_section "cAdvisor healthz (127.0.0.1:48080)"
    if command -v curl >/dev/null 2>&1; then
        curl -sS --max-time 3 http://127.0.0.1:48080/healthz 2>&1 | hr_indent_stream || printf '%s\n' "(unreachable or error)" | hr_indent_stream
    else
        printf '%s\n' "curl not installed" | hr_indent_stream
    fi
}

# ── reports ─────────────────────────────────────────────────────────────────

report_docker() {
    hr_theme_init
    local host now d_run d_all ver df_line docker_lbl df_summary

    hr_need_docker_or_exit

    host=$(hostname -s 2>/dev/null || hostname)
    now=$(date '+%Y-%m-%d %H:%M:%S %Z')
    d_run="n/a"
    d_all="n/a"
    ver="n/a"
    df_line=""
    docker_lbl=$(hr_docker_client_label)

    d_run=$(hr_docker_quick ps -q 2>/dev/null | awk 'END { print NR + 0 }')
    d_all=$(hr_docker_quick ps -a -q 2>/dev/null | awk 'END { print NR + 0 }')
    ver=$(hr_docker_quick version --format '{{.Server.Version}}' 2>/dev/null || echo "n/a")
    df_line=$(hr_docker_quick system df 2>/dev/null | head -1)
    if [[ -z $df_line ]]; then
        df_summary="(docker system df unavailable)"
    else
        df_summary=$df_line
    fi

    hr_rule_eq
    hr_title_row "Docker report"
    hr_rule_eq
    printf '%s\n' "| Host       : ${hr_B}${host}${hr_R}"
    printf '%s\n' "| Time       : ${now}"
    printf '%s\n' "| Client     : ${docker_lbl}"
    printf '%s\n' "| Server     : version ${ver}"
    printf '%s\n' "| Containers : ${d_run} running, ${d_all} total (ps -a count)"
    printf '%s\n' "| docker df  : ${df_summary}"
    hr_rule_eq

    hr_section "docker system df"
    hr_docker_quick system df 2>/dev/null | hr_indent_stream || printf '%s\n' "(docker system df failed)" | hr_indent_stream

    hr_section "docker info (compact)"
    hr_docker_quick info --format 'Server Version: {{.ServerVersion}}
Containers running: {{.ContainersRunning}}
Containers stopped: {{.ContainersStopped}}
Images: {{.Images}}
Storage Driver: {{.Driver}}
Total Memory: {{.MemTotal}}' 2>/dev/null | hr_indent_stream || printf '%s\n' "(docker info failed)" | hr_indent_stream

    hr_section "Per-container state / health / restarts / started"
    (
        while read -r c; do
            [[ -z $c ]] && continue
            restart=$(hr_docker_quick inspect --format '{{.RestartCount}}' "$c" 2>/dev/null || echo "?")
            health=$(hr_docker_quick inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$c" 2>/dev/null || echo "?")
            state=$(hr_docker_quick inspect --format '{{.State.Status}}' "$c" 2>/dev/null || echo "?")
            started=$(hr_docker_quick inspect --format '{{.State.StartedAt}}' "$c" 2>/dev/null || echo "?")
            printf '%s  state=%s  health=%s  restarts=%s  started=%s\n' "$c" "$state" "$health" "$restart" "$started"
        done < <(hr_docker_quick ps -a --format '{{.Names}}' 2>/dev/null)
    ) | hr_indent_stream

    hr_section "Containers restarting or exited — logs (tail 80 each)"
    (
        # shellcheck disable=SC2046
        for c in $(hr_docker_quick ps -a --filter 'status=restarting' --filter 'status=exited' --format '{{.Names}}' 2>/dev/null); do
            printf '%s\n' "===== $c ====="
            hr_docker_quick logs --tail 80 --timestamps "$c" 2>&1 | tail -80
            printf '\n'
        done
    ) | hr_indent_stream

    hr_rule_eq
}

report_system() {
    hr_theme_init
    local host now uptime_text
    local load1 load5 load15 run_queue total_tasks last_pid
    local cpu_count load_per_cpu
    local -a cpu_a cpu_b
    local busy_delta idle_delta iowait_delta total_delta
    local cpu_busy_pct cpu_iowait_pct
    local mem_total_kb mem_available_kb swap_total_kb swap_free_kb
    local mem_used_pct swap_used_pct
    local disk_pct disk_mount inode_pct inode_mount
    local psi_cpu psi_io psi_mem
    local dstate_count zombie_count failed_units proc_count
    local suspects suspect_list top_cpu top_mem disk_io blocked
    local health_label health_color
    local line
    local os_pretty kernel tcp_est tcp_tw

    host=$(hostname -s 2>/dev/null || hostname)
    now=$(date '+%Y-%m-%d %H:%M:%S %Z')
    uptime_text=$(uptime -p 2>/dev/null | sed 's/^up //')
    [[ -n $uptime_text ]] || uptime_text=$(awk '{ printf "%.0f minutes", $1 / 60 }' /proc/uptime 2>/dev/null)

    read -r load1 load5 load15 run_queue last_pid </proc/loadavg
    total_tasks=${run_queue#*/}
    run_queue=${run_queue%/*}
    cpu_count=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
    [[ $cpu_count =~ ^[0-9]+$ ]] || cpu_count=1
    load_per_cpu=$(awk -v loadavg="$load1" -v cpus="$cpu_count" 'BEGIN {
        if (cpus < 1) {
            cpus = 1
        }
        printf "%.2f", loadavg / cpus
    }')

    read -r -a cpu_a </proc/stat
    sleep 1
    read -r -a cpu_b </proc/stat
    busy_delta=$(((cpu_b[1] - cpu_a[1]) + (cpu_b[2] - cpu_a[2]) + (cpu_b[3] - cpu_a[3]) + (cpu_b[6] - cpu_a[6]) + (cpu_b[7] - cpu_a[7]) + (cpu_b[8] - cpu_a[8])))
    idle_delta=$((cpu_b[4] - cpu_a[4]))
    iowait_delta=$((cpu_b[5] - cpu_a[5]))
    total_delta=$((busy_delta + idle_delta + iowait_delta))
    cpu_busy_pct=$(awk -v busy="$busy_delta" -v total="$total_delta" 'BEGIN {
        if (total <= 0) {
            print "0.0"
            exit
        }
        printf "%.1f", (busy / total) * 100
    }')
    cpu_iowait_pct=$(awk -v wait="$iowait_delta" -v total="$total_delta" 'BEGIN {
        if (total <= 0) {
            print "0.0"
            exit
        }
        printf "%.1f", (wait / total) * 100
    }')

    mem_total_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
    mem_available_kb=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
    swap_total_kb=$(awk '/^SwapTotal:/ { print $2 }' /proc/meminfo)
    swap_free_kb=$(awk '/^SwapFree:/ { print $2 }' /proc/meminfo)
    mem_used_pct=$(awk -v total="$mem_total_kb" -v avail="$mem_available_kb" 'BEGIN {
        if (total <= 0) {
            print "0.0"
            exit
        }
        printf "%.1f", ((total - avail) / total) * 100
    }')
    swap_used_pct=$(awk -v total="$swap_total_kb" -v free="$swap_free_kb" 'BEGIN {
        if (total <= 0) {
            print "0.0"
            exit
        }
        printf "%.1f", ((total - free) / total) * 100
    }')

    read -r disk_pct disk_mount < <(
        df -P -x tmpfs -x devtmpfs 2>/dev/null | awk '
            NR > 1 {
                gsub("%", "", $5)
                if ($5 > max) {
                    max = $5
                    mount = $6
                }
            }
            END {
                if (mount == "") {
                    print "n/a n/a"
                } else {
                    print max, mount
                }
            }
        '
    )
    read -r inode_pct inode_mount < <(
        df -Pi -x tmpfs -x devtmpfs 2>/dev/null | awk '
            NR > 1 {
                gsub("%", "", $5)
                if ($5 > max) {
                    max = $5
                    mount = $6
                }
            }
            END {
                if (mount == "") {
                    print "n/a n/a"
                } else {
                    print max, mount
                }
            }
        '
    )

    psi_cpu=$(awk '/^some / { for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) { split($i, a, "="); print a[2] } }' /proc/pressure/cpu 2>/dev/null)
    psi_io=$(awk '/^some / { for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) { split($i, a, "="); print a[2] } }' /proc/pressure/io 2>/dev/null)
    psi_mem=$(awk '/^some / { for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) { split($i, a, "="); print a[2] } }' /proc/pressure/memory 2>/dev/null)
    [[ -n $psi_cpu ]] || psi_cpu="n/a"
    [[ -n $psi_io ]] || psi_io="n/a"
    [[ -n $psi_mem ]] || psi_mem="n/a"

    dstate_count=$(ps -eo state= 2>/dev/null | awk '$1 ~ /^D/ { c++ } END { print c + 0 }')
    zombie_count=$(ps -eo state= 2>/dev/null | awk '$1 ~ /^Z/ { c++ } END { print c + 0 }')
    proc_count=$(ps -e --no-headers 2>/dev/null | awk 'END { print NR + 0 }')
    if command -v systemctl >/dev/null 2>&1; then
        failed_units=$(systemctl --failed --plain --no-legend 2>/dev/null | awk 'END { print NR + 0 }')
    else
        failed_units=0
    fi

    if [[ -r /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        os_pretty="${PRETTY_NAME:-$NAME}"
    else
        os_pretty="n/a"
    fi
    kernel=$(uname -r 2>/dev/null || echo "n/a")
    if command -v ss >/dev/null 2>&1; then
        tcp_est=$(ss -ant state established 2>/dev/null | awk 'NR > 1 { c++ } END { print c + 0 }')
        tcp_tw=$(ss -ant state time-wait 2>/dev/null | awk 'NR > 1 { c++ } END { print c + 0 }')
    else
        tcp_est="n/a"
        tcp_tw="n/a"
    fi

    suspects=""
    if awk -v loadavg="$load_per_cpu" -v busy="$cpu_busy_pct" 'BEGIN { exit !(loadavg >= 1.00 || busy >= 85.0) }'; then
        suspects="CPU saturation"
    fi
    if awk -v dstate="$dstate_count" -v iowait="$cpu_iowait_pct" -v psi="$psi_io" 'BEGIN { exit !(dstate > 0 || iowait >= 10.0 || (psi != "n/a" && psi + 0 >= 1.00)) }'; then
        [[ -n $suspects ]] && suspects+=", "
        suspects+="I/O wait or blocked tasks"
    fi
    if awk -v mem="$mem_used_pct" -v swap_total="$swap_total_kb" -v swap_used="$swap_used_pct" -v psi="$psi_mem" 'BEGIN { exit !(mem >= 90.0 || (swap_total > 0 && swap_used >= 25.0) || (psi != "n/a" && psi + 0 >= 1.00)) }'; then
        [[ -n $suspects ]] && suspects+=", "
        suspects+="memory pressure"
    fi
    if awk -v disk="$disk_pct" -v inode="$inode_pct" 'BEGIN { exit !((disk != "n/a" && disk + 0 >= 90) || (inode != "n/a" && inode + 0 >= 90)) }'; then
        [[ -n $suspects ]] && suspects+=", "
        suspects+="filesystem pressure"
    fi
    if ((zombie_count > 0)); then
        [[ -n $suspects ]] && suspects+=", "
        suspects+="zombies present"
    fi
    if ((failed_units > 0)); then
        [[ -n $suspects ]] && suspects+=", "
        suspects+="failed systemd units"
    fi

    if [[ $suspects == *"CPU saturation"* ]] || [[ $suspects == *"I/O wait or blocked tasks"* ]] || [[ $suspects == *"memory pressure"* ]]; then
        health_label="HOT"
        health_color="$hr_red"
    elif [[ $suspects == *"filesystem pressure"* ]] || ((zombie_count > 0 || failed_units > 0)); then
        health_label="WARN"
        health_color="$hr_yel"
    else
        health_label="OK"
        health_color="$hr_grn"
    fi

    if [[ -z $suspects ]]; then
        suspect_list="no obvious bottleneck detected"
    else
        suspect_list="$suspects"
    fi

    top_cpu=$(
        ps -eo pid=PID,stat=STAT,pcpu=%CPU,pmem=%MEM,comm=COMMAND --sort=-pcpu --no-headers 2>/dev/null |
            awk '
                BEGIN {
                    printf "%-7s %-5s %-6s %-6s %s\n", "PID", "STAT", "%CPU", "%MEM", "COMMAND"
                }
                NR <= 10 {
                    printf "%-7s %-5s %-6s %-6s %s\n", $1, $2, $3, $4, $5
                }
            '
    )
    top_mem=$(
        ps -eo pid=PID,stat=STAT,pmem=%MEM,rss=RSS_KB,comm=COMMAND --sort=-pmem --no-headers 2>/dev/null |
            awk '
                BEGIN {
                    printf "%-7s %-5s %-6s %-10s %s\n", "PID", "STAT", "%MEM", "RSS_KB", "COMMAND"
                }
                NR <= 10 {
                    printf "%-7s %-5s %-6s %-10s %s\n", $1, $2, $3, $4, $5
                }
            '
    )
    if command -v iostat >/dev/null 2>&1; then
        disk_io=$(
            iostat -dx 1 2 2>/dev/null |
                awk '
                    /^Device/ {
                        in_block = 1
                        current_header = $0
                        count = 0
                        delete current_line
                        delete current_util
                        next
                    }
                    in_block && NF == 0 {
                        if (count > 0) {
                            header = current_header
                            saved_count = count
                            delete saved_line
                            delete saved_util
                            for (i = 1; i <= count; i++) {
                                saved_line[i] = current_line[i]
                                saved_util[i] = current_util[i]
                            }
                        }
                        in_block = 0
                        next
                    }
                    in_block && $1 !~ /^(loop|ram|fd|sr|md)/ {
                        current_line[++count] = $0
                        current_util[count] = $NF + 0
                    }
                    END {
                        if (header == "") {
                            print "iostat returned no device data"
                            exit
                        }
                        print header
                        limit = saved_count < 10 ? saved_count : 10
                        for (n = 1; n <= limit; n++) {
                            best = 0
                            for (i = 1; i <= saved_count; i++) {
                                if (!(i in used) && (best == 0 || saved_util[i] > saved_util[best])) {
                                    best = i
                                }
                            }
                            if (best == 0) {
                                break
                            }
                            print saved_line[best]
                            used[best] = 1
                        }
                    }
                '
        )
    else
        disk_io="iostat not installed"
    fi
    blocked=$(
        ps -eo pid=PID,stat=STAT,wchan:24=WCHAN,comm=COMMAND --no-headers 2>/dev/null |
            awk '
                BEGIN {
                    printf "%-7s %-5s %-24s %s\n", "PID", "STAT", "WCHAN", "COMMAND"
                }
                $2 ~ /^D/ {
                    printf "%-7s %-5s %-24s %s\n", $1, $2, $3, $4
                    count++
                    if (count == 5) {
                        exit
                    }
                }
                END {
                    if (count == 0) {
                        print "none"
                    }
                }
            '
    )

    hr_rule_eq
    printf '%s\n' "${hr_blu}|   _                    _   ____                       _                      |${hr_R}"
    printf '%s\n' "${hr_blu}|  | |    ___   __ _  __| | |  _ \\ ___ _ __   ___  _ __| |_                    |${hr_R}"
    printf '%s\n' "${hr_blu}|  | |   / _ \\ / _\` |/ _\` | | |_) / _ \\ '_ \\ / _ \\| '__| __|                   |${hr_R}"
    printf '%s\n' "${hr_blu}|  | |__| (_) | (_| | (_| | |  _ <  __/ |_) | (_) | |  | |_                    |${hr_R}"
    printf '%s\n' "${hr_blu}|  |_____\\___/ \\__,_|\\__,_| |_| \\_\\___| .__/ \\___/|_|   \\__|                   |${hr_R}"
    printf '%s\n' "${hr_blu}|                                     |_|                                      |${hr_R}"
    hr_rule_eq
    printf '%s\n' "| Host       : ${hr_B}${host}${hr_R}"
    printf '%s\n' "| Time       : ${now}"
    printf '%s\n' "| Uptime     : ${uptime_text}"
    printf '%s\n' "| Health     : ${health_color}${health_label}${hr_R}"
    printf '%s\n' "| Suspects   : ${suspect_list}"
    hr_rule_dash
    printf '%s\n' "| OS         : ${os_pretty}"
    printf '%s\n' "| Kernel     : ${kernel}"
    printf '%s\n' "| Load       : ${load1} ${load5} ${load15} on ${cpu_count} CPU(s) (${load_per_cpu} per CPU)"
    printf '%s\n' "| Run queue  : ${run_queue} running, ${total_tasks} total tasks, last pid ${last_pid}"
    printf '%s\n' "| CPU        : busy ${cpu_busy_pct}%%, iowait ${cpu_iowait_pct}%%, PSI cpu10 ${psi_cpu}, io10 ${psi_io}"
    printf '%s\n' "| Memory     : used ${mem_used_pct}%%, swap ${swap_used_pct}%%, PSI mem10 ${psi_mem}"
    printf '%s\n' "| Pressure   : D-state ${dstate_count}, zombies ${zombie_count}, failed units ${failed_units}, procs ${proc_count}"
    printf '%s\n' "| Network    : TCP established ${tcp_est}, TIME-WAIT ${tcp_tw} (ss)"
    printf '%s\n' "| Filesystem : disk ${disk_pct}%% on ${disk_mount}, inodes ${inode_pct}%% on ${inode_mount}"
    hr_rule_dash
    printf '%s\n' "| Hot CPU processes"
    while IFS= read -r line; do
        printf '%s\n' "|   ${line}"
    done <<<"$top_cpu"
    hr_rule_dash
    printf '%s\n' "| Hot memory processes"
    while IFS= read -r line; do
        printf '%s\n' "|   ${line}"
    done <<<"$top_mem"
    hr_rule_dash
    printf '%s\n' "| Disk activity (iostat)"
    while IFS= read -r line; do
        printf '%s\n' "|   ${line}"
    done <<<"$disk_io"
    hr_rule_dash
    printf '%s\n' "| Blocked D-state processes (sample up to 5; see extended report for full list)"
    while IFS= read -r line; do
        printf '%s\n' "|   ${line}"
    done <<<"$blocked"

    hr_system_extended

    hr_rule_eq
}

report_postgres() {
    hr_theme_init
    hr_need_docker_or_exit
    hr_report_header "PostgreSQL report"
    if ! hr_docker_has postgres; then
        hr_service_skip postgres
        hr_report_footer
        return 0
    fi

    hr_section "Container"
    hr_docker inspect postgres --format "Name={{.Name}} Image={{.Config.Image}} State={{.State.Status}} Restarts={{.RestartCount}} StartedAt={{.State.StartedAt}}" | hr_indent_stream

    hr_section "Host: postgres-related processes (pgrep -a)"
    pgrep -a postgres 2>/dev/null | hr_indent_stream || printf '%s\n' "(no matching host processes)" | hr_indent_stream

    hr_section "Host: TCP flows mentioning :5432 (ss -tan, first 25)"
    if command -v ss >/dev/null 2>&1; then
        {
            printf '%s\n' "matching line count: $(ss -tan 2>/dev/null | grep -c ':5432' || true)"
            ss -tan 2>/dev/null | grep ':5432' | head -25 || true
        } | hr_indent_stream
    else
        printf '%s\n' "ss not installed" | hr_indent_stream
    fi

    hr_section "Host: open FD count per postgres PID (if any on host)"
    (
        any=0
        while read -r pid; do
            [[ -z $pid ]] && continue
            any=1
            cnt=$(find "/proc/$pid/fd" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
            printf '%s\n' "$pid $cnt"
        done < <(pgrep postgres 2>/dev/null || true)
        [[ $any -eq 0 ]] && printf '%s\n' "(no host postgres PIDs)"
    ) | hr_indent_stream

    hr_section "psql snapshot"
    local psql_snap
    read -r -d '' psql_snap <<'HREP_PGSQL' || true
SELECT '--- server ---';
SELECT now();
SELECT version();

SELECT '--- key settings ---';
SELECT name||'='||setting FROM pg_settings
WHERE name IN (
  'max_connections','superuser_reserved_connections',
  'shared_buffers','work_mem','maintenance_work_mem',
  'effective_cache_size','max_wal_size',
  'max_files_per_process',
  'idle_in_transaction_session_timeout','statement_timeout',
  'deadlock_timeout','lock_timeout',
  'logging_collector','log_destination',
  'listen_addresses','port'
)
ORDER BY 1;

SELECT '--- connections by state ---';
SELECT state, count(*) FROM pg_stat_activity GROUP BY 1 ORDER BY 2 DESC;

SELECT '--- connections by user ---';
SELECT usename, count(*) FROM pg_stat_activity GROUP BY 1 ORDER BY 2 DESC;

SELECT '--- connections by client ---';
SELECT client_addr::text, count(*) FROM pg_stat_activity GROUP BY 1 ORDER BY 2 DESC;

SELECT '--- connections by app ---';
SELECT application_name, count(*) FROM pg_stat_activity GROUP BY 1 ORDER BY 2 DESC;

SELECT '--- active queries ---';
SELECT pid, usename, client_addr, application_name, state,
       now()-backend_start   AS backend_age,
       now()-xact_start      AS xact_age,
       now()-query_start     AS query_age,
       wait_event_type, wait_event,
       left(regexp_replace(query, E'[\n\r\t]+',' ','g'), 200) AS query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start NULLS LAST
LIMIT 40;

SELECT '--- long-running transactions (>30s) ---';
SELECT pid, usename, state, now()-xact_start AS xact_age,
       left(regexp_replace(query, E'[\n\r\t]+',' ','g'), 160) AS query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND now()-xact_start > interval '30 seconds'
ORDER BY xact_start;

SELECT '--- lock waits ---';
SELECT blocked.pid AS blocked_pid,
       blocked.usename AS blocked_user,
       blocking.pid AS blocking_pid,
       blocking.usename AS blocking_user,
       left(blocked.query, 120) AS blocked_query
FROM pg_stat_activity AS blocked
JOIN pg_locks AS bl ON bl.pid = blocked.pid AND NOT bl.granted
JOIN pg_locks AS kl ON kl.locktype = bl.locktype
  AND kl.database IS NOT DISTINCT FROM bl.database
  AND kl.relation IS NOT DISTINCT FROM bl.relation
  AND kl.page IS NOT DISTINCT FROM bl.page
  AND kl.tuple IS NOT DISTINCT FROM bl.tuple
  AND kl.pid != bl.pid AND kl.granted
JOIN pg_stat_activity AS blocking ON blocking.pid = kl.pid
LIMIT 20;

SELECT '--- locks by mode ---';
SELECT mode, count(*) FROM pg_locks GROUP BY 1 ORDER BY 2 DESC;

SELECT '--- replication status ---';
SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;

SELECT '--- database sizes ---';
SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database WHERE NOT datistemplate ORDER BY pg_database_size(datname) DESC;
HREP_PGSQL
    hr_docker exec -i postgres psql -U admin -Atc "$psql_snap" 2>&1 | hr_indent_stream

    hr_section "Logs (tail 60)"
    hr_docker logs --tail 60 --timestamps postgres 2>&1 | hr_indent_stream

    hr_report_footer
}

report_redis() {
    hr_theme_init
    hr_need_docker_or_exit
    hr_report_header "Redis report"
    if ! hr_docker_has redis; then
        hr_service_skip redis
        hr_report_footer
        return 0
    fi

    hr_section "Container"
    hr_docker inspect redis --format "State={{.State.Status}} Restarts={{.RestartCount}} StartedAt={{.State.StartedAt}}" | hr_indent_stream

    hr_section "redis-cli info (server / memory / clients / stats, dbsize)"
    hr_run_timeout "$HR_DOCKER_TIMEOUT" bash -o pipefail -c '
sudo docker exec -i redis redis-cli info server 2>&1 | head -20
sudo docker exec -i redis redis-cli info memory 2>&1 | head -15
sudo docker exec -i redis redis-cli info clients 2>&1 | head -15
sudo docker exec -i redis redis-cli info stats 2>&1 | grep -E "connected_clients|blocked_clients|rejected_connections|evicted_keys|keyspace_" || true
sudo docker exec -i redis redis-cli dbsize 2>&1
' | hr_indent_stream

    hr_section "slowlog (last 10)"
    hr_run_timeout "$HR_DOCKER_TIMEOUT" bash -o pipefail -c "sudo docker exec -i redis redis-cli slowlog get 10 2>&1" | hr_indent_stream

    hr_report_footer
}

report_elasticsearch() {
    hr_theme_init
    hr_need_docker_or_exit
    hr_report_header "Elasticsearch report"
    if ! hr_docker_has elasticsearch; then
        hr_service_skip elasticsearch
        hr_report_footer
        return 0
    fi

    hr_section "Container"
    hr_docker inspect elasticsearch --format "State={{.State.Status}} Restarts={{.RestartCount}} StartedAt={{.State.StartedAt}}" | hr_indent_stream

    hr_section "Cluster health"
    hr_run_timeout "$HR_DOCKER_TIMEOUT" bash -o pipefail -c "sudo docker exec -i elasticsearch curl -sS localhost:9200/_cluster/health?pretty 2>&1" | hr_indent_stream

    hr_section "Node stats (fs, jvm, truncated)"
    hr_run_timeout "$HR_DOCKER_TIMEOUT" bash -o pipefail -c "sudo docker exec -i elasticsearch curl -sS 'localhost:9200/_nodes/stats/fs,jvm?pretty' 2>&1 | head -80" | hr_indent_stream

    hr_section "Logs (tail 40)"
    hr_docker logs --tail 40 --timestamps elasticsearch 2>&1 | hr_indent_stream

    hr_report_footer
}

report_rabbitmq() {
    hr_theme_init
    hr_need_docker_or_exit
    hr_report_header "RabbitMQ report"
    if ! hr_docker_has rabbitmq; then
        hr_service_skip rabbitmq
        hr_report_footer
        return 0
    fi

    hr_section "Container"
    hr_docker inspect rabbitmq --format "State={{.State.Status}} Restarts={{.RestartCount}} StartedAt={{.State.StartedAt}}" | hr_indent_stream

    hr_section "rabbitmqctl status"
    hr_run_timeout "$HR_DOCKER_TIMEOUT" bash -o pipefail -c "sudo docker exec -i rabbitmq rabbitmqctl status 2>&1 | head -60" | hr_indent_stream

    hr_section "Queues"
    hr_run_timeout "$HR_DOCKER_TIMEOUT" bash -o pipefail -c "sudo docker exec -i rabbitmq rabbitmqctl list_queues name messages consumers 2>&1 | head -40" | hr_indent_stream

    hr_section "Logs (tail 40)"
    hr_docker logs --tail 40 --timestamps rabbitmq 2>&1 | hr_indent_stream

    hr_report_footer
}

report_haproxy() {
    hr_theme_init
    hr_need_docker_or_exit
    hr_report_header "HAProxy report"
    if ! hr_docker_has haproxy; then
        hr_service_skip haproxy
        hr_report_footer
        return 0
    fi

    hr_section "Container"
    hr_docker inspect haproxy --format "State={{.State.Status}} Restarts={{.RestartCount}} StartedAt={{.State.StartedAt}}" | hr_indent_stream

    hr_section "Logs (tail 40)"
    hr_docker logs --tail 40 --timestamps haproxy 2>&1 | hr_indent_stream

    hr_report_footer
}

report_promtail() {
    hr_theme_init
    hr_need_docker_or_exit
    hr_report_header "Promtail report"
    if ! hr_docker_has promtail; then
        hr_service_skip promtail
        hr_report_footer
        return 0
    fi

    hr_section "Container"
    hr_docker inspect promtail --format "State={{.State.Status}} Restarts={{.RestartCount}} StartedAt={{.State.StartedAt}}" | hr_indent_stream

    hr_section "Logs (tail 40)"
    hr_docker logs --tail 40 --timestamps promtail 2>&1 | hr_indent_stream

    hr_report_footer
}

report_monitoring() {
    hr_theme_init
    hr_need_docker_or_exit
    hr_report_header "Monitoring stack report (prometheus, grafana, loki, alertmanager)"

    local svc any=0
    for svc in prometheus grafana loki alertmanager; do
        if hr_docker_has "$svc"; then
            any=1
            hr_section "Service: ${svc}"
            hr_docker inspect "$svc" --format "State={{.State.Status}} Restarts={{.RestartCount}} StartedAt={{.State.StartedAt}}" | hr_indent_stream
            hr_section "Logs: ${svc} (tail 40)"
            hr_docker logs --tail 40 --timestamps "$svc" 2>&1 | hr_indent_stream
        fi
    done

    if ((any == 0)); then
        hr_section "Skipping"
        printf '%s\n' "|   No prometheus/grafana/loki/alertmanager containers found."
    fi

    hr_section "node_exporter smoke (127.0.0.1:49100/metrics, first lines)"
    if command -v curl >/dev/null 2>&1; then
        curl -sS --max-time 3 http://127.0.0.1:49100/metrics 2>&1 | head -8 | hr_indent_stream || printf '%s\n' "(unreachable or error)" | hr_indent_stream
    else
        printf '%s\n' "|   curl not installed" | hr_indent_stream
    fi

    hr_section "cAdvisor healthz (127.0.0.1:48080)"
    if command -v curl >/dev/null 2>&1; then
        curl -sS --max-time 3 http://127.0.0.1:48080/healthz 2>&1 | hr_indent_stream || printf '%s\n' "(unreachable or error)" | hr_indent_stream
    else
        printf '%s\n' "|   curl not installed" | hr_indent_stream
    fi

    hr_report_footer
}

main() {
    case "${1-}" in
    system) report_system ;;
    docker) report_docker ;;
    postgres | pg) report_postgres ;;
    redis) report_redis ;;
    elasticsearch | es) report_elasticsearch ;;
    rabbitmq | rabbit) report_rabbitmq ;;
    haproxy) report_haproxy ;;
    promtail) report_promtail ;;
    monitoring | mon) report_monitoring ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        usage
        exit 1
        ;;
    esac
}

main "$@"
