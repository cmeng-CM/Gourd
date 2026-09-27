#!/bin/bash
# 校验 upstreams.tsv 中的仓库是否都已拉取、许可文件是否存在、当前 commit 是多少，
# 并校验 dependency 行与 Package.resolved 里 pin 的 revision 是否一致
# 用法: bash tools/verify-upstreams.sh
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$(dirname "$HERE")"
MANIFEST="$HERE/upstreams.tsv"
RESOLVED="$HERE/DynamicIsland.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

missing=0; warn=0; unpinned=0; drift=0
printf "%-22s %-8s %-10s %-24s %s\n" "目录" "状态" "commit" "许可" "用途"
printf -- "--------------------------------------------------------------------------------------------\n"

# dependency 行（mode 或 usage 任一为 dependency）由 SPM 引入，不 clone 到同级目录：
# 不要求本地存在目录（不计入 missing），目录存在时才顺带校验许可与 commit。
while IFS=$'\t' read -r dir repo mode license usage purpose commit key; do
  target="$DEST/$dir"
  isdep=0
  [[ "$mode" == "dependency" || "$usage" == "dependency" ]] && isdep=1
  if [[ ! -d "$target/.git" ]]; then
    if [[ "$isdep" -eq 1 ]]; then
      printf "%-22s %-8s %-10s %-24s %s\n" "$dir" "依赖" "-" "$license" "$purpose"
      continue
    fi
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
# dependency 行与 Package.resolved 的 pin 一致性：
# 登记的 clone_commit（首个空格前那段，如 `e2d30af`）必须是 Package.resolved 对应 pin revision 的前缀。
# 未登记进 upstreams.tsv 的 pin（如传递依赖 lottie-spm）不参与比对。
if [[ ! -f "$RESOLVED" ]]; then
  echo "警告: 找不到 $RESOLVED，跳过依赖 pin 一致性检查"
  warn=$((warn+1))
else
  pins=$(python3 - "$RESOLVED" <<'PY'
import json, re, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
for pin in data.get("pins", []):
    loc = pin.get("location", "")
    slug = re.sub(r"\.git$", "", re.sub(r"^[a-z]+://[^/]+/", "", loc)).lower()
    state = pin.get("state", {})
    print("\t".join([pin.get("identity", ""), slug, state.get("revision", ""),
                     "branch" if "branch" in state else "pin"]))
PY
)
  echo "依赖 pin 一致性（Package.resolved ↔ upstreams.tsv 的 dependency 行）："
  while IFS=$'\t' read -r dir repo mode license usage purpose commit key; do
    [[ "$mode" == "dependency" || "$usage" == "dependency" ]] || continue
    want_slug=$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')
    want_id=$(printf '%s' "$dir" | tr '[:upper:]' '[:lower:]')
    rec="${commit%% *}"
    hit=""
    while IFS=$'\t' read -r pident pslug prev pkind; do
      [[ "$pslug" == "$want_slug" || "$pident" == "$want_id" ]] && { hit="$pident|$prev|$pkind"; break; }
    done < <(printf '%s\n' "$pins")
    if [[ -z "$hit" ]]; then
      printf "  %-22s 未 pin（Package.resolved 无对应条目：备选/未引入）\n" "$dir"
      unpinned=$((unpinned+1))
      continue
    fi
    pident="${hit%%|*}"; rest="${hit#*|}"; prev="${rest%%|*}"; pkind="${rest##*|}"
    if [[ "$pkind" == "branch" ]]; then
      printf "  %-22s 不一致：%s 在 Package.resolved 里是 branch 形态（%s），不是 revision pin\n" "$dir" "$pident" "$prev"
      drift=$((drift+1))
    elif [[ "$prev" == "$rec"* || "$rec" == "$prev"* ]]; then
      printf "  %-22s OK   清单 %s = pin %s\n" "$dir" "$rec" "$prev"
    else
      printf "  %-22s 不一致：清单登记 %s，Package.resolved pin %s\n" "$dir" "$rec" "$prev"
      drift=$((drift+1))
    fi
  done < <(tail -n +2 "$MANIFEST")
fi

echo
echo "共 $(($(wc -l < "$MANIFEST") - 1)) 个上游：缺失 ${missing} 个，许可待人工确认 ${warn} 个，依赖未 pin ${unpinned} 个，依赖 pin 不一致 ${drift} 个"
[[ "$missing" -eq 0 && "$drift" -eq 0 ]] || exit 1
