#!/usr/bin/env bash
# اضافه کردن هدر master به همه ایجنت‌ها
# فقط یک‌بار اجرا شود

set -e

MASTER_HEADER='<!-- Horizon Angel | Owner: Mahdi Amoli Moghaddam -->
<!-- این ایجنت تحت فرمان _master.md عمل می‌کند -->
<!-- زبان پیش‌فرض: فارسی -->
<!-- قالب پاسخ: استاندارد Horizon Angel -->

'

DIRS=(academic design engineering finance game-development gis healthcare
      marketing paid-media product project-management sales security
      spatial-computing specialized support testing)

COUNT=0
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || continue
  for f in "$d"/*.md; do
    [ -f "$f" ] || continue
    # اگر قبلاً هدر گرفته، رد کن
    if head -1 "$f" | grep -q "Horizon Angel | Owner"; then
      continue
    fi
    # هدر را اضافه کن
    tmp=$(mktemp)
    printf '%s' "$MASTER_HEADER" > "$tmp"
    cat "$f" >> "$tmp"
    mv "$tmp" "$f"
    COUNT=$((COUNT+1))
  done
done

echo "✅ $COUNT ایجنت هدر گرفتند"
