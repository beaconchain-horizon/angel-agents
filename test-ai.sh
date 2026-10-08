#!/usr/bin/env bash
# تست سریع اتصال به Liara AI
# استفاده: ./test-ai.sh "پیام تو"

set -e

if [ ! -f .env.local ]; then
  echo "❌ .env.local پیدا نشد"
  exit 1
fi

set -a; source .env.local; set +a

MSG="${1:-فقط بگو: تست موفق}"

cat > /tmp/horizon-test.json << EOF
{
  "model": "$OPENAI_MODEL",
  "messages": [
    {"role": "user", "content": "$MSG"}
  ],
  "max_tokens": 500
}
EOF

curl -sS \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/horizon-test.json \
  "$OPENAI_BASE_URL/chat/completions" \
  | grep -oE '"content":"[^"]*"' | head -1

rm -f /tmp/horizon-test.json
