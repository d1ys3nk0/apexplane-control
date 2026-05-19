#!/usr/bin/env bash

RULES_FILE="/opt/iptables/rules"

start() {
    iptables -N LOG_N_DROP
    iptables -A LOG_N_DROP -j LOG --log-prefix "DROP: " --log-level 4
    iptables -A LOG_N_DROP -j DROP

    tac "$RULES_FILE" | grep -v '^\s*#' | grep -v '^\s*$' | while read -r rule; do
        cmd="iptables -I $rule"
        echo "$cmd"
        $cmd
    done
}

stop() {
    cat "$RULES_FILE" | grep -v '^\s*#' | grep -v '^\s*$' | while read -r rule; do
        cmd="iptables -D $rule"
        echo "$cmd"
        $cmd
    done

    iptables -F LOG_N_DROP
    iptables -X LOG_N_DROP
}

restart() {
    stop
    start
}

status() {
    iptables -L -n -v
}

case "$1" in
start)
    start
    ;;
stop)
    stop
    ;;
restart)
    restart
    ;;
status)
    status
    ;;
*)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac

exit 0
