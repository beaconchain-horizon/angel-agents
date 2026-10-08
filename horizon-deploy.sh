#!/bin/bash
# ============================================================
# Horizon Ecosystem Deployer – v3.0.0 (با Horizon Angel)
# ============================================================
# Author: Mahdi Amolimoghaddam
# Description: استقرار کامل اکوسیستم Horizon شامل Core، Watcher،
#              Dashboard، Prefect و Horizon Angel
# Usage: ./horizon-deploy.sh {install|start|stop|restart|status|logs}
# ============================================================

set -euo pipefail

# ---------- Colors ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# ---------- Variables ----------
ROOT_DIR="$HOME/horizon-ecosystem"
ORG_URL="https://github.com/beaconchain-horizon"
BRANCH="main"  # یا "mine" اگر شاخه‌ی شما این است
LOG_DIR="$ROOT_DIR/logs"
PID_DIR="$ROOT_DIR/.pids"
ENV_FILE=".env"

# لیست کامل مخزن‌ها (به ترتیب وابستگی)
REPOS_CORE=("horizon-core-engine")
REPOS_UI=("beaconcha.in" "Beaconchain.us" "hub")
REPOS_AGENTS=("horizon-angel")
REPOS_EXTRA=("prefect")  # اگر وجود دارد

ALL_REPOS=("${REPOS_CORE[@]}" "${REPOS_UI[@]}" "${REPOS_AGENTS[@]}" "${REPOS_EXTRA[@]}")

# ---------- Functions ----------
log() { echo -e "${BLUE}[Horizon]${NC} $1"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️ $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; exit 1; }

check_prereqs() {
    log "بررسی پیش‌نیازها..."
    command -v git >/dev/null || error "Git نصب نیست."
    command -v go >/dev/null || error "Go (1.21+) نصب نیست."
    command -v docker >/dev/null || warn "Docker پیدا نشد. از SQLite استفاده می‌شود."
    command -v python3 >/dev/null || warn "Python3 پیدا نشد. برخی Agents ممکن است کار نکنند."
    command -v node >/dev/null || warn "Node.js پیدا نشد. برخی UIها ممکن است کار نکنند."
    success "پیش‌نیازها تأیید شد."
}

load_env() {
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE"
        set +a
        success "متغیرهای محیطی از $ENV_FILE بارگذاری شد."
    else
        warn "فایل .env پیدا نشد. از مقادیر پیش‌فرض استفاده می‌شود."
        export API_PORT=8080
        export UI_PORT=3000
        export DB_HOST=localhost
        export DB_PORT=5432
        export DB_USER=horizon
        export DB_PASS=horizon123
        export DB_NAME=horizon
        export ETH_NODE_URL="https://ethereum-node.example.com"
        export OPENAI_API_KEY="your-openai-key"  # برای Agents
    fi
}

clone_or_pull() {
    mkdir -p "$ROOT_DIR"
    cd "$ROOT_DIR"
    log "کلون/بروزرسانی مخزن‌ها از شاخه: $BRANCH"
    
    for repo in "${ALL_REPOS[@]}"; do
        if [ ! -d "$repo" ]; then
            git clone -b "$BRANCH" "$ORG_URL/$repo.git" "$repo" || warn "کلون $repo ناموفق بود"
            success "کلون $repo انجام شد"
        else
            cd "$repo" && git pull origin "$BRANCH" >/dev/null 2>&1 && cd ..
            success "بروزرسانی $repo انجام شد"
        fi
    done
}

build_core() {
    log "ساخت Core Engine (Merkle Tree + ECDSA)..."
    cd "$ROOT_DIR/horizon-core-engine"
    go mod download
    go test ./... -short || warn "بعضی تست‌ها ناموفق بود، اما ادامه می‌دهیم..."
    CGO_ENABLED=0 go build -o bin/horizon-api ./cmd/main.go
    CGO_ENABLED=0 go build -o bin/horizon-watcher ./cmd/watcher/main.go 2>/dev/null || warn "Watcher ساخته نشد (مسیر ممکن است متفاوت باشد)"
    chmod +x bin/*
    success "Core Engine ساخته شد."
}

build_ui() {
    log "ساخت رابط‌های کاربری..."
    for repo in "${REPOS_UI[@]}"; do
        if [ -f "$ROOT_DIR/$repo/package.json" ]; then
            cd "$ROOT_DIR/$repo"
            npm install --silent
            npm run build --silent || warn "ساخت $repo ناموفق بود"
            success "$repo ساخته شد"
        else
            warn "$repo فایل package.json ندارد (احتمالاً استاتیک است)."
        fi
    done
}

setup_agents() {
    log "راه‌اندازی Horizon Angel..."
    cd "$ROOT_DIR/horizon-angel"
    
    # اگر Agents با Python هستند
    if [ -f "requirements.txt" ]; then
        python3 -m venv venv
        source venv/bin/activate
        pip install -r requirements.txt --quiet
        deactivate
        success "وابستگی‌های Python Agents نصب شد."
    fi
    
    # اگر Agents با Node.js هستند
    if [ -f "package.json" ]; then
        npm install --silent
        success "وابستگی‌های Node.js Agents نصب شد."
    fi
    
    # ساخت فایل محیطی برای Agents (اتصال به Core API)
    cat > .env.agents <<EOF
CORE_API_URL=http://localhost:${API_PORT:-8080}
OPENAI_API_KEY=${OPENAI_API_KEY:-your-openai-key}
ETH_NODE_URL=${ETH_NODE_URL:-https://ethereum-node.example.com}
EOF
    success "Agents آماده‌ی اجرا شدند."
}

setup_database() {
    log "راه‌اندازی دیتابیس..."
    if command -v docker >/dev/null; then
        docker stop horizon-db 2>/dev/null || true
        docker rm horizon-db 2>/dev/null || true
        docker run -d --name horizon-db \
            -e POSTGRES_USER="$DB_USER" \
            -e POSTGRES_PASSWORD="$DB_PASS" \
            -e POSTGRES_DB="$DB_NAME" \
            -p "$DB_PORT":5432 \
            -v horizon-data:/var/lib/postgresql/data \
            postgres:16-alpine
        sleep 3
        success "PostgreSQL روی پورت $DB_PORT در حال اجراست."
        
        # اجرای مهاجرت (در صورت وجود)
        cd "$ROOT_DIR/horizon-core-engine"
        if [ -f "./bin/horizon-api" ]; then
            ./bin/horizon-api --migrate || warn "مهاجرت دیتابیس ناموفق بود."
        fi
    else
        warn "Docker در دسترس نیست. از SQLite استفاده می‌شود."
        mkdir -p "$ROOT_DIR/data"
        export HORIZON_DB_PATH="$ROOT_DIR/data/horizon.db"
    fi
}

start_services() {
    mkdir -p "$LOG_DIR" "$PID_DIR"
    log "شروع همه‌ی سرویس‌ها..."
    
    # 1. Core API
    cd "$ROOT_DIR/horizon-core-engine"
    nohup ./bin/horizon-api > "$LOG_DIR/api.log" 2>&1 &
    echo $! > "$PID_DIR/api.pid"
    success "Core API شروع شد (PID: $(cat $PID_DIR/api.pid)) روی http://localhost:${API_PORT:-8080}"
    
    # 2. Watcher (در صورت وجود)
    if [ -f "./bin/horizon-watcher" ]; then
        nohup ./bin/horizon-watcher > "$LOG_DIR/watcher.log" 2>&1 &
        echo $! > "$PID_DIR/watcher.pid"
        success "Blockchain Watcher شروع شد (PID: $(cat $PID_DIR/watcher.pid))"
    fi
    
    # 3. UI (beaconcha.in)
    if [ -d "$ROOT_DIR/beaconcha.in/dist" ]; then
        cd "$ROOT_DIR/beaconcha.in/dist"
        nohup python3 -m http.server ${UI_PORT:-3000} > "$LOG_DIR/ui.log" 2>&1 &
        echo $! > "$PID_DIR/ui.pid"
        success "Dashboard UI شروع شد روی http://localhost:${UI_PORT:-3000}"
    fi
    
    # 4. Horizon Angel (هر Agent به‌عنوان یک سرویس جداگانه)
    cd "$ROOT_DIR/horizon-angel"
    if [ -f "venv/bin/python" ]; then
        # اگر Agents پایتونی هستند
        for agent in $(ls -d */ 2>/dev/null | grep -v venv); do
            if [ -f "$agent/main.py" ]; then
                nohup venv/bin/python "$agent/main.py" > "$LOG_DIR/agent-${agent%/}.log" 2>&1 &
                echo $! > "$PID_DIR/agent-${agent%/}.pid"
                success "Agent '${agent%/}' شروع شد (PID: $(cat $PID_DIR/agent-${agent%/}.pid))"
            fi
        done
    elif [ -f "package.json" ]; then
        # اگر Agents Node.js هستند
        nohup npm start > "$LOG_DIR/agents.log" 2>&1 &
        echo $! > "$PID_DIR/agents.pid"
        success "Horizon Angel (Node.js) شروع شدند (PID: $(cat $PID_DIR/agents.pid))"
    else
        warn "هیچ Agent قابل اجرایی پیدا نشد."
    fi
    
    # 5. Prefect (در صورت وجود)
    if [ -d "$ROOT_DIR/prefect" ]; then
        cd "$ROOT_DIR/prefect"
        nohup prefect server start --host 0.0.0.0 > "$LOG_DIR/prefect.log" 2>&1 &
        echo $! > "$PID_DIR/prefect.pid"
        success "Prefect Orchestrator شروع شد روی http://localhost:4200"
    fi
    
    success "🎯 کل اکوسیستم Horizon با موفقیت راه‌اندازی شد!"
}

stop_services() {
    log "توقف همه‌ی سرویس‌ها..."
    for pid_file in "$PID_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            kill -9 $(cat "$pid_file") 2>/dev/null || true
            rm -f "$pid_file"
        fi
    done
    docker stop horizon-db 2>/dev/null || true
    success "همه‌ی سرویس‌ها متوقف شدند."
}

status_check() {
    log "بررسی وضعیت اکوسیستم..."
    
    # Core API
    if curl -s "http://localhost:${API_PORT:-8080}/health" >/dev/null; then
        success "Core API: RUNNING"
    else
        warn "Core API: DOWN"
    fi
    
    # Dashboard UI
    if curl -s "http://localhost:${UI_PORT:-3000}" >/dev/null; then
        success "Dashboard UI: RUNNING"
    else
        warn "Dashboard UI: DOWN"
    fi
    
    # Agents (بررسی نمونه)
    if pgrep -f "horizon-angel" >/dev/null; then
        success "Horizon Angel: RUNNING"
    else
        warn "Horizon Angel: DOWN"
    fi
    
    # Database
    if docker ps | grep horizon-db >/dev/null; then
        success "Database: RUNNING"
    else
        warn "Database: DOWN"
    fi
}

show_logs() {
    log "نمایش لاگ‌های لحظه‌ای (Ctrl+C برای خروج)..."
    tail -f "$LOG_DIR"/*.log 2>/dev/null || echo "هیچ لاگی موجود نیست."
}

# ---------- Main Menu ----------
mkdir -p "$ROOT_DIR" "$LOG_DIR" "$PID_DIR"

case "$1" in
    install)
        check_prereqs
        load_env
        clone_or_pull
        build_core
        setup_agents
        build_ui
        setup_database
        start_services
        status_check
        ;;
    start)
        load_env
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        stop_services
        sleep 2
        start_services
        ;;
    status)
        status_check
        ;;
    logs)
        show_logs
        ;;
    *)
        echo "Usage: $0 {install|start|stop|restart|status|logs}"
        echo "  install : استقرار کامل (کلون، بیلد، دیتابیس، Agents، اجرا)"
        echo "  start   : راه‌اندازی سرویس‌های قبلاً ساخته‌شده"
        echo "  stop    : توقف همه‌ی سرویس‌ها"
        echo "  restart : راه‌اندازی مجدد"
        echo "  status  : نمایش وضعیت همه‌ی مؤلفه‌ها"
        echo "  logs    : نمایش لاگ‌های لحظه‌ای"
        exit 1
        ;;
esac
