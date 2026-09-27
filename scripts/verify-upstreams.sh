#!/bin/bash
# 校验 upstreams.tsv 中的仓库是否都已拉取、许可文件是否存在、当前 commit 是多少
# 用法: bash scripts/verify-upstreams.sh
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$(dirname "$HERE")"
MANIFEST="$HERE/upstreams.tsv"

missing=0; warn=0
printf "%-22s %-8s %-10s %-24s %s\n" "目录" "状态" "commit" "许可" "用途"
printf -- "--------------------------------------------------------------------------------------------\n"

while IFS=$'\t' read -r dir repo mode license usage purpose commit key; do
  target="$DEST/$dir"
  if [[ ! -d "$target/.git" ]]; then
    printf "%-22s %-8s %-10s %-24s %s\n" "$dir" "缺失" "-" "$license" "$purpose"
    missing=$((missing+1))
    continue
  fi
  cur=$(git -C "$target" rev-parse --short HEAD 2>/dev/null)
  licfile=""
  for f in LICENSE LICENSE.md LICENSE.txt LICENCE LICENCE.md License.txt COPYING; do
    [[ -f "$target/$f" ]] && { licfile="$f"; break; }
  done
  if [[ -n "$licfile" ]]; then
    actual=$(head -c 300 "$target/$licfile" | grep -o -i -E "GNU GENERAL PUBLIC LICENSE|Apache License|MIT License|Mozilla Public License" | head -1)
    status="OK"
  else
    actual="未见许可文件"
    status="警告"
    warn=$((warn+1))
  fi
  printf "%-22s %-8s %-10s %-24s %s\n" "$dir" "$status" "$cur" "${actual:-未识别}" "$purpose"
done < <(tail -n +2 "$MANIFEST")

echo
echo "共 $(($(wc -l < "$MANIFEST") - 1)) 个上游：缺失 ${missing} 个，许可待人工确认 ${warn} 个"
[[ "$missing" -eq 0 ]] || exit 1
