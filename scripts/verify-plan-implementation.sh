#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法:
  bash scripts/verify-plan-implementation.sh --plan <计划文档> --report <完成报告文档>

说明:
  1) 计划文档中必须包含检查项: - [ ] P1: ...
  2) 完成报告中必须包含对应勾选项: - [x] P1: ...
  3) 完成报告必须包含: 结论: 通过
EOF
}

PLAN_PATH=""
REPORT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)
      PLAN_PATH="${2:-}"
      shift 2
      ;;
    --report)
      REPORT_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$PLAN_PATH" || -z "$REPORT_PATH" ]]; then
  echo "缺少必填参数 --plan 或 --report" >&2
  usage
  exit 2
fi

if [[ ! -f "$PLAN_PATH" ]]; then
  echo "计划文档不存在: $PLAN_PATH" >&2
  exit 2
fi

if [[ ! -f "$REPORT_PATH" ]]; then
  echo "完成报告不存在: $REPORT_PATH" >&2
  exit 2
fi

PLAN_IDS=()
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  PLAN_IDS+=("$id")
done < <(
  grep -E '^- \[[ xX]\] P[0-9]+:' "$PLAN_PATH" \
    | sed -E 's/^- \[[ xX]\] (P[0-9]+):.*/\1/' \
    | awk '!seen[$0]++'
)

if [[ ${#PLAN_IDS[@]} -eq 0 ]]; then
  echo "计划文档中未找到检查项（格式: - [ ] P1: ...）: $PLAN_PATH" >&2
  exit 2
fi

MISSING_IDS=()
UNCHECKED_IDS=()

for id in "${PLAN_IDS[@]}"; do
  if grep -Eq "^- \\[[xX]\\] ${id}:" "$REPORT_PATH"; then
    continue
  fi
  if grep -Eq "^- \\[[[:space:]]\\] ${id}:" "$REPORT_PATH"; then
    UNCHECKED_IDS+=("$id")
  else
    MISSING_IDS+=("$id")
  fi
done

if [[ ${#MISSING_IDS[@]} -gt 0 ]]; then
  echo "完成报告缺少以下检查项: ${MISSING_IDS[*]}" >&2
fi

if [[ ${#UNCHECKED_IDS[@]} -gt 0 ]]; then
  echo "完成报告中以下检查项尚未勾选: ${UNCHECKED_IDS[*]}" >&2
fi

if ! grep -Eq '^结论:[[:space:]]*通过' "$REPORT_PATH"; then
  echo "完成报告缺少“结论: 通过”" >&2
  exit 1
fi

if [[ ${#MISSING_IDS[@]} -gt 0 || ${#UNCHECKED_IDS[@]} -gt 0 ]]; then
  exit 1
fi

echo "计划实施校验通过:"
echo "  计划文档: $PLAN_PATH"
echo "  完成报告: $REPORT_PATH"
echo "  校验项: ${PLAN_IDS[*]}"
