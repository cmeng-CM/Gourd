#!/bin/bash
# 按 upstreams.tsv 拉取缺失的上游仓库 / 刷新已有的参考仓库
# （mode=dependency 的行由 SPM 引入，不 clone 到同级目录）
# 用法: bash tools/sync-upstreams.sh [dir]   # 不带参数=全部；带 dir=只处理该目录
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$(dirname "$HERE")"          # ~/workspace/github
MANIFEST="$HERE/upstreams.tsv"
ONLY="${1:-}"

[[ -f "$MANIFEST" ]] || { echo "找不到 $MANIFEST"; exit 1; }

tail -n +2 "$MANIFEST" | while IFS=$'\t' read -r dir repo mode license usage purpose commit key; do
  [[ -n "$ONLY" && "$ONLY" != "$dir" ]] && continue
  target="$DEST/$dir"
  if [[ -d "$target/.git" ]]; then
    case "$mode" in
      full)
        # 基座：加 upstream remote 并抓取（不自动合并，合并需人工在分支上验证）
        git -C "$target" remote get-url upstream >/dev/null 2>&1 \
          || git -C "$target" remote add upstream "https://github.com/$repo.git"
        git -C "$target" fetch --tags upstream >/dev/null 2>&1 \
          && echo "FETCH  $dir  (upstream 已更新，合并请手工在分支上进行)" \
          || echo "WARN   $dir  fetch 失败（检查网络或仓库地址）"
        ;;
      shallow)
        if git -C "$target" fetch --depth 1 origin >/dev/null 2>&1; then
          git -C "$target" reset --hard FETCH_HEAD >/dev/null 2>&1
          echo "UPDATE $dir  -> $(git -C "$target" rev-parse --short HEAD)"
        else
          echo "WARN   $dir  刷新失败"
        fi
        ;;
      *)
        echo "SKIP   $dir  (mode=$mode)"
        ;;
    esac
  elif [[ "$mode" == "dependency" ]]; then
    echo "SKIP   $dir  (mode=dependency：SPM 依赖，按 upstreams.tsv 登记的 revision 由 Package.resolved 锁定)"
  else
    if [[ "$mode" == "full" ]]; then
      git clone "https://github.com/$repo.git" "$target" >/dev/null 2>&1
    else
      git clone --depth 1 --single-branch "https://github.com/$repo.git" "$target" >/dev/null 2>&1
    fi
    [[ -d "$target/.git" ]] \
      && echo "CLONE  $dir  ($repo, $mode)" \
      || echo "FAIL   $dir  ($repo)"
  fi
done
echo "完成。基座合并前请先跑 tools/verify-upstreams.sh 并自测（多屏 / 合盖 / 展开动画 / 各模块）。"
