#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE
zmodload zsh/datetime

# 在本机重复执行 Git 关键路径，并输出 TSV + JSON。默认只报告，不因阈值超标退出；
# CI 或本地回归可加 --strict 让任一超标返回非零。
script_dir="${0:A:h}"
fixture_script="$script_dir/performance-fixtures.sh"
fixture_root="${GITIGNORE_FIXTURE_ROOT:-${TMPDIR:-/tmp}/GitIgnore-Performance-Fixtures}"
report_path=""
scenario="all"
keep_existing=0
strict=0
sample_interval="0.05"

fail() {
  print -u2 -- "performance-regression: $*"
  exit 2
}

usage() {
  print -- '用法：performance-regression.sh [选项]'
  print -- ''
  print -- '  --scenario <all|workspace|history|diff>  选择回归场景（默认 all）'
  print -- '  --root <目录>                            夹具根目录'
  print -- '  --report <文件>                          JSON 输出路径（同时生成 .tsv）'
  print -- '  --keep                                   保留已有夹具，避免覆盖用户夹具'
  print -- '  --strict                                 阈值超标时返回 1'
  print -- '  --sample-interval <秒>                   CPU 采样间隔（默认 0.05）'
}

while (($#)); do
  case "$1" in
    --scenario)
      (($# >= 2)) || fail '--scenario 需要参数'
      scenario="$2"
      shift 2
      ;;
    --root)
      (($# >= 2)) || fail '--root 需要参数'
      fixture_root="$2"
      shift 2
      ;;
    --report)
      (($# >= 2)) || fail '--report 需要参数'
      report_path="$2"
      shift 2
      ;;
    --keep)
      keep_existing=1
      shift
      ;;
    --strict)
      strict=1
      shift
      ;;
    --sample-interval)
      (($# >= 2)) || fail '--sample-interval 需要参数'
      sample_interval="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "无法识别参数：$1"
      ;;
  esac
done

[[ "$scenario" == all || "$scenario" == workspace || "$scenario" == history || "$scenario" == diff ]] || fail "未知场景：$scenario"
[[ "$sample_interval" == <->\.<-> || "$sample_interval" == <-> ]] || fail '采样间隔必须是数字'
command -v git >/dev/null || fail '找不到 git'
[[ -r "$fixture_script" ]] || fail "无法读取夹具脚本：$fixture_script"

mkdir -p "$fixture_root"
fixture_root="$(cd "$fixture_root" && pwd -P)"
if [[ -z "$report_path" ]]; then
  report_path="$fixture_root/performance-report-$(date +%Y%m%d-%H%M%S).json"
else
  mkdir -p "${report_path:h}"
  report_path="$(cd "${report_path:h}" && pwd -P)/${report_path:t}"
fi
tsv_path="${report_path:r}.tsv"

fixture_args=(--root "$fixture_root")
(( keep_existing )) && fixture_args+=(--keep)
case "$scenario" in
  all) zsh "$fixture_script" all "${fixture_args[@]}" >/dev/null ;;
  workspace)
    for count in 10 100 1000; do
      zsh "$fixture_script" workspace "$count" "${fixture_args[@]}" >/dev/null
    done
    ;;
  history) zsh "$fixture_script" history "${fixture_args[@]}" >/dev/null ;;
  diff)
    for megabytes in 1 10 100; do
      zsh "$fixture_script" diff "$megabytes" "${fixture_args[@]}" >/dev/null
    done
    ;;
esac

typeset -a json_rows
typeset -a tsv_rows
failed_count=0

record_result() {
  local name="$1" command_label="$2" duration_ms="$3" max_rss="$4" max_cpu="$5" threshold_ms="$6" result_status="$7"
  local status_code="$8"
  tsv_rows+=("$name${tab}$command_label${tab}$duration_ms${tab}$max_rss${tab}$max_cpu${tab}$threshold_ms${tab}$result_status${tab}$status_code")
  json_rows+=("{\"name\":\"$name\",\"command\":\"$command_label\",\"durationMs\":$duration_ms,\"peakRSSBytes\":$max_rss,\"maxCPUPercent\":$max_cpu,\"targetMs\":$threshold_ms,\"status\":\"$result_status\",\"exitStatus\":$status_code}")
  [[ "$result_status" == pass ]] || (( failed_count += 1 ))
}

run_timed() {
  local name="$1" command_label="$2" threshold_ms="$3" cwd="$4"
  shift 4
  local time_log="$fixture_root/.time-$RANDOM-$RANDOM.log"
  local status_code=0
  local start="$EPOCHREALTIME"
  (/usr/bin/time -p "$@" > /dev/null 2> "$time_log") &
  local pid=$!
  local max_cpu="0"
  local max_rss="0"
  local cpu="" rss="" rss_bytes=0
  while kill -0 "$pid" 2>/dev/null; do
    cpu="$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print $1}' | head -1 || true)"
    if [[ "$cpu" == <->*([.])<-> ]]; then
      max_cpu="$(awk -v a="$max_cpu" -v b="$cpu" 'BEGIN { print (b > a ? b : a) }')"
    fi
    rss="$(ps -p "$pid" -o rss= 2>/dev/null | awk '{print $1}' | head -1 || true)"
    if [[ "$rss" == <-> ]]; then
      rss_bytes=$((rss * 1024))
      (( rss_bytes > max_rss )) && max_rss="$rss_bytes"
    fi
    sleep "$sample_interval"
  done
  wait "$pid" || status_code=$?
  local duration_ms
  duration_ms="$(awk -v start="$start" -v end="$EPOCHREALTIME" 'BEGIN { printf "%.0f", (end - start) * 1000 }')"
  rm -f -- "$time_log"
  local result_status="pass"
  if (( status_code != 0 )); then
    result_status="error"
  elif (( duration_ms > threshold_ms )); then
    result_status="slow"
  fi
  record_result "$name" "$command_label" "$duration_ms" "$max_rss" "$max_cpu" "$threshold_ms" "$result_status" "$status_code"
  print -- "$(printf '%-24s %6sms  RSS %8s  CPU %5s%%  %s' "$name" "$duration_ms" "$max_rss" "$max_cpu" "$result_status")"
}

run_workspace() {
  local count="$1"
  local root="$fixture_root/workspace-$count"
  [[ -d "$root/.git" ]] || fail "缺少夹具：$root，请先运行 fixture 脚本"
  run_timed "workspace-$count/status" "git status --short" 1000 "$root" git -C "$root" status --short
  run_timed "workspace-$count/stage" "git add -A" 1500 "$root" git -C "$root" add -A
  run_timed "workspace-$count/unstage" "git reset" 1500 "$root" git -C "$root" reset -q HEAD -- .
  run_timed "workspace-$count/switch" "git switch" 500 "$root" git -C "$root" switch -q --detach HEAD
}

run_history() {
  local root="$fixture_root/history-10000"
  [[ -d "$root/.git" ]] || fail "缺少夹具：$root，请先运行 fixture 脚本"
  run_timed "history/first-page" "git log -n 60" 1000 "$root" git -C "$root" log --date-order --format='%H%x09%an%x09%ad%x09%s' -n 60
  run_timed "history/10000-scroll" "git log --skip 5000 -n 120" 1500 "$root" git -C "$root" log --date-order --format='%H%x09%s' --skip=5000 -n 120
  run_timed "history/10000-count" "git rev-list --count" 1500 "$root" git -C "$root" rev-list --count HEAD
}

run_diff() {
  local megabytes="$1"
  local root="$fixture_root/diff-${megabytes}mb"
  [[ -d "$root/.git" ]] || fail "缺少夹具：$root，请先运行 fixture 脚本"
  run_timed "diff-${megabytes}mb/read" "git diff" "$((megabytes <= 1 ? 500 : megabytes <= 10 ? 1500 : 5000))" "$root" git -C "$root" diff --no-ext-diff --unified=3 --no-color -- large.txt
  run_timed "diff-${megabytes}mb/stat" "git diff --stat" 1000 "$root" git -C "$root" diff --stat -- large.txt
}

tab=$'\t'
print -r -- "name${tab}command${tab}durationMs${tab}peakRSSBytes${tab}maxCPUPercent${tab}targetMs${tab}status${tab}exitStatus" > "$tsv_path"
if [[ "$scenario" == all || "$scenario" == workspace ]]; then
  run_workspace 10
  run_workspace 100
  run_workspace 1000
fi
if [[ "$scenario" == all || "$scenario" == history ]]; then run_history; fi
if [[ "$scenario" == all || "$scenario" == diff ]]; then
  run_diff 1
  run_diff 10
  run_diff 100
fi
printf '%s\n' "${tsv_rows[@]}" >> "$tsv_path"

{
  print -r -- '{'
  print -r -- '  "generatedAt": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",'
  print -r -- '  "fixtureRoot": "'"$fixture_root"'",'
  print -r -- '  "targets": {"idleCPUPercent": 1.0, "idleMemoryMinBytes": 157286400, "idleMemoryMaxBytes": 209715200},'
  print -r -- '  "results": ['
  local index=1
  for row in "${json_rows[@]}"; do
    if (( index < ${#json_rows[@]} )); then print -r -- "    $row,"; else print -r -- "    $row"; fi
    (( index += 1 ))
  done
  print -r -- '  ],'
  print -r -- '  "failedCount": '"$failed_count"
  print -r -- '}'
} > "$report_path"

print -- "TSV 报告：$tsv_path"
print -- "JSON 报告：$report_path"
if (( strict && failed_count > 0 )); then exit 1; fi
