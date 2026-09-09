#!/bin/zsh
set -euo pipefail

# 生成可重复的本地性能夹具。脚本只允许删除自己管理的 fixture_root 子目录。
tab=$'\t'

fixture_root="${GITIGNORE_FIXTURE_ROOT:-${TMPDIR:-/tmp}/GitIgnore-Performance-Fixtures}"
scenario="all"
workspace_count="100"
diff_megabytes="10"
keep_existing=0
manifest_path=""

fail() {
  print -u2 -- "performance-fixtures: $*"
  exit 2
}

usage() {
  print -- '用法：performance-fixtures.sh [all|workspace [数量]|history|diff [MB]] [选项]'
  print -- ''
  print -- '选项：'
  print -- '  --keep                 保留已存在的同名夹具，不覆盖重建'
  print -- '  --root <目录>           指定夹具根目录（默认位于 TMPDIR）'
  print -- '  --manifest <文件>       输出夹具清单 TSV（--report 为别名）'
  print -- '  --help                  显示帮助'
}

while (($#)); do
  case "$1" in
    all|workspace|history|diff)
      scenario="$1"
      shift
      if [[ "$scenario" == workspace && $# -gt 0 && "$1" != --* ]]; then
        workspace_count="$1"
        shift
      elif [[ "$scenario" == diff && $# -gt 0 && "$1" != --* ]]; then
        diff_megabytes="$1"
        shift
      fi
      ;;
    --keep)
      keep_existing=1
      shift
      ;;
    --root)
      (($# >= 2)) || fail "--root 需要目录参数"
      fixture_root="$2"
      shift 2
      ;;
    --manifest|--report)
      (($# >= 2)) || fail "$1 需要文件参数"
      manifest_path="$2"
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

[[ "$workspace_count" == <-> && "$workspace_count" -gt 0 ]] || fail 'workspace 数量必须是正整数'
[[ "$diff_megabytes" == <-> && "$diff_megabytes" -gt 0 ]] || fail 'diff 大小必须是正整数 MB'

mkdir -p "$fixture_root"
fixture_root="$(cd "$fixture_root" && pwd -P)"
if [[ -z "$manifest_path" ]]; then
  manifest_path="$fixture_root/fixture-manifest.tsv"
else
  mkdir -p "${manifest_path:h}"
  manifest_path="$(cd "${manifest_path:h}" && pwd -P)/${manifest_path:t}"
fi

safe_remove_target() {
  local target="$1"
  [[ "$target" != "$fixture_root" ]] || fail "拒绝删除夹具根目录"
  case "$target" in
    "$fixture_root"/*) rm -rf -- "$target" ;;
    *) fail "拒绝删除夹具目录之外的路径：$target" ;;
  esac
}

prepare_target() {
  local target="$1"
  if [[ -e "$target" ]]; then
    if (( keep_existing )); then
      print -- "保留已有夹具：$target"
      return 1
    fi
    safe_remove_target "$target"
  fi
  mkdir -p "$target"
  return 0
}

init_repository() {
  local target="$1"
  git -C "$target" init -q
  git -C "$target" config user.name "GitIgnore Fixture"
  git -C "$target" config user.email "fixture@gitignore.local"
  git -C "$target" config commit.gpgsign false
}

write_repeated_file() {
  local output_file="$1"
  local bytes="$2"
  local line="$3"
  perl -e '
    my ($path, $bytes, $line) = @ARGV;
    open my $fh, ">", $path or die "$path: $!";
    my $chunk = $line x 1024;
    while ($bytes > 0) {
      my $part = $bytes < length($chunk) ? substr($chunk, 0, $bytes) : $chunk;
      print {$fh} $part or die "$path: $!";
      $bytes -= length($part);
    }
    close $fh or die "$path: $!";
  ' "$output_file" "$bytes" "$line"
}

create_workspace_fixture() {
  local count="$1"
  local target="$fixture_root/workspace-$count"
  if ! prepare_target "$target"; then
    print -r -- "workspace-$count${tab}workspace${tab}$count${tab}$target" >> "$manifest_path"
    return 0
  fi
  init_repository "$target"
  print -r -- "baseline" > "$target/README.md"
  git -C "$target" add README.md
  git -C "$target" commit -qm "baseline"
  local index
  for index in {1..$count}; do
    print -r -- "changed $index" > "$target/file-$index.txt"
  done
  print -r -- "workspace-$count${tab}workspace${tab}$count${tab}$target" >> "$manifest_path"
}

create_history_fixture() {
  local target="$fixture_root/history-10000"
  if ! prepare_target "$target"; then
    print -r -- "history-10000${tab}history${tab}10000${tab}$target" >> "$manifest_path"
    return 0
  fi
  init_repository "$target"
  # fast-import 将 10,000 次 commit 从分钟级降为秒级，同时保持真实 Git 历史拓扑。
  local index message
  {
    for index in {1..10000}; do
      message="fixture commit $index"
      print -r -- "commit refs/heads/main"
      print -r -- "mark :$index"
      print -r -- "author GitIgnore Fixture <fixture@gitignore.local> 1700000000 +0000"
      print -r -- "committer GitIgnore Fixture <fixture@gitignore.local> 1700000000 +0000"
      print -r -- "data ${#message}"
      print -r -- "$message"
      if (( index > 1 )); then print -r -- "from :$((index - 1))"; fi
      print -r -- "M 100644 inline history.txt"
      print -r -- "data ${#index}"
      print -r -- "$index"
      print -r -- ""
    done
  } | git -C "$target" fast-import --quiet
  git -C "$target" update-ref HEAD refs/heads/main
  print -r -- "history-10000${tab}history${tab}10000${tab}$target" >> "$manifest_path"
}

create_diff_fixture() {
  local megabytes="$1"
  local target="$fixture_root/diff-${megabytes}mb"
  if ! prepare_target "$target"; then
    print -r -- "diff-${megabytes}mb${tab}diff${tab}${megabytes}MB${tab}$target" >> "$manifest_path"
    return 0
  fi
  init_repository "$target"
  local bytes=$((megabytes * 1024 * 1024))
  write_repeated_file "$target/large.txt" "$bytes" $'baseline 0123456789 abcdefghijklmnopqrstuvwxyz\n'
  git -C "$target" add large.txt
  git -C "$target" commit -qm "baseline"
  write_repeated_file "$target/large.txt" "$bytes" $'changed 9876543210 zyxwvutsrqponmlkjihgfedcba\n'
  print -r -- "diff-${megabytes}mb${tab}diff${tab}${megabytes}MB${tab}$target" >> "$manifest_path"
}

print -r -- "fixture${tab}scenario${tab}size${tab}path" > "$manifest_path"
case "$scenario" in
  workspace) create_workspace_fixture "$workspace_count" ;;
  history) create_history_fixture ;;
  diff) create_diff_fixture "$diff_megabytes" ;;
  all)
    create_workspace_fixture 10
    create_workspace_fixture 100
    create_workspace_fixture 1000
    create_history_fixture
    create_diff_fixture 1
    create_diff_fixture 10
    create_diff_fixture 100
    ;;
esac

print -- "夹具清单：$manifest_path"
print -- "夹具目录：$fixture_root"
