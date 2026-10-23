#!/bin/bash
# Q8：repair 时识别并停止采集器、修复 HTTP 服务；cleanup 时停止修复后的服务。
# 完整接口与验收规格见 Problem.pdf。只修改本文件，不修改测试或工具。
set -eu
input=${1:?需要输入目录}
output=${2:?需要输出目录}

action=${3:-repair}
mkdir -p "$output"

# A terminated child may remain a zombie until its parent reaps it.
is_running() {
    local state
    state=$(ps -p "$1" -o stat= || true)
    case "$state" in
        ''|Z*) return 1 ;;
        *) return 0 ;;
    esac
}

# Stop only the supplied PID, allowing its normal shutdown handler to run.
stop_process() {
    local pid=$1 attempt
    if ! is_running "$pid"; then
        return 0
    fi
    kill -TERM "$pid"
    for ((attempt=0; attempt<60; attempt++)); do
        if ! is_running "$pid"; then
            return 0
        fi
        sleep 0.05
    done
    printf 'Process %s did not stop normally\n' "$pid" >&2
    return 1
}

case "$action" in
    repair)
        source "$input/process.env"
        read -r owner state < <(ps -p "$TARGET_PID" -o user:64=,stat=)
        command=$(ps -ww -p "$TARGET_PID" -o args=)
        printf 'pid=%s\nuser=%s\nstate=%s\ncommand=%s\n' \
            "$TARGET_PID" "$owner" "$state" "$command" > "$output/process.txt"
        grep -F "TICK $TARGET_TOKEN " "$WORKER_LOG" > "$output/collector-sample.log"
        stop_process "$TARGET_PID"
        stop_process "$SERVICE_PID"
        printf 'bind=127.0.0.1\nport=%s\nroute=/status\n' \
            "$TARGET_PORT" > "$output/server.conf"
        bash "$START_TOOL" "$output/server.conf" "$output/service"
        ready=0
        for ((attempt=0; attempt<30; attempt++)); do
            if status=$(curl --noproxy '*' --silent --show-error \
                --connect-timeout 0.2 --max-time 0.2 \
                --output "$output/http-body.txt" --write-out '%{http_code}' \
                "http://127.0.0.1:$TARGET_PORT/status"); then
                if [ "$status" = 200 ]; then
                    ready=1
                    break
                fi
            fi
            sleep 0.05
        done
        if [ "$ready" -ne 1 ]; then
            stop_process "$(cat "$output/service/pid")"
            printf '%s\n' 'HTTP service did not become ready' >&2
            exit 1
        fi
        printf '%s\n' "$status" > "$output/http-status.txt"
        ;;
    cleanup)
        if [ -f "$output/service/pid" ]; then
            stop_process "$(cat "$output/service/pid")"
        fi
        ;;
    *) printf 'Unknown action: %s\n' "$action" >&2; exit 1 ;;
esac
