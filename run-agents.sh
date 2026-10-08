#!/usr/bin/env bash
set -e

if [ ! -f .env.local ]; then
  echo "❌ .env.local نیست"
  exit 1
fi
set -a; source .env.local; set +a

list_agents() {
  find . -maxdepth 2 -name "*.md" \
    -not -path "./.git/*" -not -path "./integrations/*" \
    -not -path "./scripts/*" -not -path "./examples/*" \
    -not -path "./strategy/*" -not -path "./.github/*" \
    -not -name "README.md" -not -name "CONTRIBUTING*.md" \
    -not -name "SECURITY.md" -not -name "LICENSE*" \
    -not -name "*.original-*" 2>/dev/null \
    | sed 's|^\./||' | sort
}

run_agent() {
  local agent_path="$1"
  local message="$2"

  [ ! -f "$agent_path" ] && { echo "❌ ایجنت نیست: $agent_path"; return 1; }

  local tmpfile
  tmpfile=$(mktemp)

  jq -n \
    --arg model "$OPENAI_MODEL" \
    --rawfile sys "$agent_path" \
    --arg user "$message" \
    '{
      model: $model,
      messages: [
        {role: "system", content: $sys},
        {role: "user", content: $user}
      ],
      max_tokens: 2000
    }' > "$tmpfile"

  curl -sS \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data-binary @"$tmpfile" \
    "$OPENAI_BASE_URL/chat/completions" \
    | jq -r '.choices[0].message.content // .choices[0].message.reasoning // "بدون پاسخ"' \
    > /tmp/agent-out.txt

  rm -f "$tmpfile"

  # نمایش با cat که UTF-8 را درست می‌خواند
  cat /tmp/agent-out.txt
}

case "${1:-}" in
  list)
    list_agents | nl
    echo ""
    echo "تعداد: $(list_agents | wc -l)"
    ;;
  run)
    [ -z "${2:-}" ] && { echo "استفاده: ./run-agents.sh run <agent> \"پیام\""; exit 1; }
    run_agent "$2" "$3"
    ;;
  all)
    [ -z "${2:-}" ] && { echo "استفاده: ./run-agents.sh all \"پیام\""; exit 1; }
    list_agents | while read -r agent; do
      echo ""
      echo "━━━ $agent ━━━"
      run_agent "$agent" "$2" 2>&1 | head -10
    done
    ;;
  *)
    echo "Usage: ./run-agents.sh {list|run <agent> \"پیام\"|all \"پیام\"}"
    ;;
esac
