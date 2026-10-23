#!/bin/bash
# Q4：合并日志，按级别提取，保存首尾片段并统计错误行数。
# 完整接口与验收规格见 Problem.pdf。只修改本文件，不修改测试或工具。
set -eu
input=${1:?需要输入目录}
output=${2:?需要输出目录}

mkdir -p "$output"
cat "$input/boot.log" "$input/run.log" > "$output/all.log"
# No matching log entries is a valid input, not a command failure.
if grep '^ERROR ' "$output/all.log" > "$output/errors.log"; then
    :
else
    status=$?
    [ "$status" -eq 1 ] || exit "$status"
fi
if grep -E '^(WARN|ERROR) ' "$output/all.log" > "$output/attention.log"; then
    :
else
    status=$?
    [ "$status" -eq 1 ] || exit "$status"
fi
tail -n 5 "$output/all.log" > "$output/recent.log"
head -n 3 "$output/errors.log" > "$output/first-errors.log"
count=$(wc -l < "$output/errors.log")
printf '%d\n' "$count" > "$output/error-count.txt"
