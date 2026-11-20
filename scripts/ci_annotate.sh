#!/bin/bash
# コマンドを実行し、失敗したらコンパイルエラー・テスト失敗を GitHub の注釈（Annotations）として出す。
# 注釈はログ全体を開かなくても Actions の画面（と公開APIで）読める。
# 使い方: scripts/ci_annotate.sh <ログファイル名> <コマンド...>
log="$1"; shift
set -o pipefail
"$@" 2>&1 | tee "$log"
status=$?
if [ $status -ne 0 ]; then
  grep -E "^/.+\.swift:[0-9]+(:[0-9]+)?: (error|fatal error): " "$log" | sort -u | head -40 | while IFS= read -r line; do
    file=$(echo "$line" | sed -E 's#^(/[^:]+\.swift):.*#\1#' | sed -E "s#^$GITHUB_WORKSPACE/##")
    ln=$(echo "$line" | sed -E 's#^/[^:]+\.swift:([0-9]+).*#\1#')
    msg=$(echo "$line" | sed -E 's#^/[^:]+\.swift:[0-9]+(:[0-9]+)?: (fatal )?error: ##')
    echo "::error file=$file,line=$ln::$msg"
  done
  # Swift 以外の失敗（依存解決・設定など）は最後の行を出す
  if ! grep -qE "\.swift:[0-9]+.*error: " "$log"; then
    echo "::error::$(grep -iE "error|failed" "$log" | tail -5 | tr '\n' ' ' | cut -c1-900)"
  fi
fi
exit $status
