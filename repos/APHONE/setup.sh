#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# APHONE v2.0 AUTO-INSTALLER — Bulletproof Edition
# Repo: https://github.com/muxd22-alt/APHONE
# Runs fully native in Termux NDK — no proot, no docker
# ============================================================

set -euo pipefail
trap 'echo -e "\n${RED}[✗] Setup failed at line $LINENO${NC}"; exit 1' ERR

REPO="https://github.com/muxd22-alt/APHONE"
MODEL_DIR="$HOME/models"
AGENT_DIR="$HOME/aphone"
MODEL_URL="https://huggingface.co/unsloth/gemma-3-270m-it-GGUF/resolve/main/gemma-3-270m-it-Q4_K_M.gguf"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

banner() {
  echo -e "${CYAN}"
  echo "  ╔══════════════════════════════════════╗"
  echo "  ║   APHONE Research Agent v2.0         ║"
  echo "  ║   Bulletproof Edition · Termux NDK   ║"
  echo "  ╚══════════════════════════════════════╝"
  echo -e "${NC}"
}

step()  { echo -e "\n${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()  { echo -e "${CYAN}[→]${NC} $1"; }

banner

# ── Collect secrets interactively ────────────────────────────
echo -e "${MAGENTA}━━━ Configuration ━━━${NC}\n"

BOT_TOKEN="${APHONE_TOKEN:-}"
if [ -z "$BOT_TOKEN" ]; then
  echo -e "${YELLOW}► Enter your Telegram Bot Token:${NC}"
  read -r -p "> " BOT_TOKEN </dev/tty
  echo ""
fi
[ -z "$BOT_TOKEN" ] && fail "Bot token is required."

SERPER_KEY="${SERPER_API_KEY:-}"
if [ -z "$SERPER_KEY" ]; then
  echo -e "${YELLOW}► Enter your Serper API Key (get one at https://serper.dev/api-keys):${NC}"
  read -r -p "> " SERPER_KEY </dev/tty
  echo ""
fi
[ -z "$SERPER_KEY" ] && fail "Serper API key is required for web search."

GH_TOKEN="${GH_TOKEN:-}"
if [ -z "$GH_TOKEN" ]; then
  echo -e "${YELLOW}► Enter GitHub PAT (or press Enter to skip):${NC}"
  read -r -p "> " GH_TOKEN </dev/tty
  echo ""
fi

# ── 1. Termux mirror ────────────────────────────────────────
step "Fixing Termux mirror…"
termux-change-repo 2>/dev/null || true

# ── 2. Core packages ────────────────────────────────────────
step "Installing system packages…"
pkg update -y -o Dpkg::Options::="--force-confdef" 2>/dev/null || true

pkg install -y git python python-pip gh ffmpeg llama-cpp 2>/dev/null \
  || fail "Package install failed — check your internet"

# ── 3. Python dependencies ───────────────────────────────────
step "Installing Python dependencies…"
pip install --quiet --upgrade \
  python-telegram-bot \
  httpx \
  requests \
  yt-dlp \
  feedparser \
  aiofiles \
  youtube-transcript-api 2>/dev/null \
  || warn "Some Python packages may have failed — checking…"

# Verify critical imports
python -c "import httpx; import telegram; print('Core deps OK')" \
  || fail "Critical Python dependencies missing"

info "Optional: youtube-transcript-api"
python -c "from youtube_transcript_api import YouTubeTranscriptApi; print('  ✓ transcript-api OK')" 2>/dev/null \
  || warn "youtube-transcript-api unavailable — will use yt-dlp subtitle fallback"

# ── 4. Wakelock ──────────────────────────────────────────────
step "Acquiring Termux wakelock…"
termux-wake-lock 2>/dev/null || warn "Wakelock unavailable — set battery to Unrestricted"

# ── 5. Project dir ───────────────────────────────────────────
step "Setting up project directory…"
mkdir -p "$MODEL_DIR" "$AGENT_DIR/docs" "$AGENT_DIR/db"

cat > "$AGENT_DIR/.env" << ENVEOF
APHONE_TOKEN="${BOT_TOKEN}"
SERPER_API_KEY="${SERPER_KEY}"
GH_TOKEN="${GH_TOKEN}"
ENVEOF
chmod 600 "$AGENT_DIR/.env"

# ── 6. Copy agent code ──────────────────────────────────────
step "Installing nano_agent.py…"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/nano_agent.py" ]; then
  cp "$SCRIPT_DIR/nano_agent.py" "$AGENT_DIR/nano_agent.py"
else
  # Download from repo if running via curl
  curl -fsSL "https://raw.githubusercontent.com/muxd22-alt/APHONE/main/nano_agent.py" \
    -o "$AGENT_DIR/nano_agent.py" \
    || fail "Could not download nano_agent.py"
fi
chmod +x "$AGENT_DIR/nano_agent.py"

# ── 7. Download LLM model ────────────────────────────────────
step "Downloading LLM model…"
if [ ! -f "$MODEL_DIR/model_a.gguf" ]; then
  info "Downloading Gemma 3 270M (~241MB)…"
  curl -L --progress-bar -o "$MODEL_DIR/model_a.gguf" "$MODEL_URL" || {
    warn "Model download failed — retry later with: curl -L -o ~/models/model_a.gguf $MODEL_URL"
    rm -f "$MODEL_DIR/model_a.gguf"
  }
  if [ -f "$MODEL_DIR/model_a.gguf" ]; then
    head -c 4 "$MODEL_DIR/model_a.gguf" | grep -q "GGUF" \
      || { warn "Model file corrupt — deleting"; rm -f "$MODEL_DIR/model_a.gguf"; }
  fi
else
  info "Model already exists, skipping"
fi

# ── 8. GitHub repo setup ────────────────────────────────────
step "Setting up Git repository…"
cd "$AGENT_DIR"

if [ ! -d ".git" ]; then
  git init -q
  git remote add origin "$REPO" 2>/dev/null || git remote set-url origin "$REPO"
fi

# Initialize report
if [ ! -f "RESEARCH_LOG.md" ]; then
cat > RESEARCH_LOG.md << 'MDEOF'
# APHONE Research Log

> Auto-generated research reports by [APHONE v2.0](https://github.com/muxd22-alt/APHONE)
> Powered by Serper Search + YouTube Transcripts + arXiv + Extractive AI

---
MDEOF
fi

# Write docs/style.css
cat > docs/style.css << 'CSSEOF'
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');

*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --bg-primary: #0a0a0f;
  --bg-card: #12121a;
  --bg-card-hover: #1a1a28;
  --bg-input: #16161f;
  --border: rgba(255,255,255,0.06);
  --border-active: rgba(139,92,246,0.4);
  --text-primary: #e8e8ed;
  --text-secondary: #8b8b9e;
  --text-muted: #55556a;
  --accent: #8b5cf6;
  --accent-glow: rgba(139,92,246,0.15);
  --green: #34d399;
  --green-dim: rgba(52,211,153,0.12);
  --blue: #60a5fa;
  --blue-dim: rgba(96,165,250,0.12);
  --orange: #fb923c;
  --orange-dim: rgba(251,146,60,0.12);
  --pink: #f472b6;
  --radius: 12px;
  --radius-sm: 8px;
}

body {
  font-family: 'Inter', -apple-system, sans-serif;
  background: var(--bg-primary);
  color: var(--text-primary);
  min-height: 100vh;
  line-height: 1.6;
}

.root {
  max-width: 720px;
  margin: 0 auto;
  padding: 24px 16px;
}

/* Cards */
.card {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 20px;
  margin-bottom: 14px;
  transition: border-color 0.2s, box-shadow 0.2s;
}
.card:hover {
  border-color: var(--border-active);
  box-shadow: 0 0 20px var(--accent-glow);
}

/* Header */
.hero { text-align: center; padding: 32px 20px; }
.hero h1 {
  font-size: 22px; font-weight: 700; letter-spacing: -0.02em;
  background: linear-gradient(135deg, var(--accent), var(--pink));
  -webkit-background-clip: text; -webkit-text-fill-color: transparent;
}
.hero .tagline {
  font-size: 13px; color: var(--text-secondary); margin-top: 6px;
}

/* Badges */
.badge {
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 11px; padding: 3px 10px; border-radius: 99px; font-weight: 500;
}
.badge-green { background: var(--green-dim); color: var(--green); }
.badge-blue { background: var(--blue-dim); color: var(--blue); }
.badge-orange { background: var(--orange-dim); color: var(--orange); }
.badge-purple { background: var(--accent-glow); color: var(--accent); }

/* Flow */
.flow {
  display: flex; align-items: center; gap: 6px;
  flex-wrap: wrap; justify-content: center; margin: 16px 0;
}
.flow-box {
  background: var(--bg-input); border: 1px solid var(--border);
  border-radius: var(--radius-sm); padding: 6px 12px;
  font-size: 12px; font-weight: 500;
}
.flow-arrow { color: var(--accent); font-size: 14px; }

/* Tabs */
.tab-row { display: flex; gap: 4px; margin-bottom: 14px; overflow-x: auto; }
.tab {
  padding: 7px 14px; font-size: 12px; font-weight: 500;
  border: 1px solid var(--border); border-radius: var(--radius-sm);
  cursor: pointer; color: var(--text-secondary); background: transparent;
  white-space: nowrap; transition: all 0.15s;
}
.tab:hover { border-color: var(--border-active); color: var(--text-primary); }
.tab.active {
  background: var(--accent-glow); color: var(--accent);
  border-color: var(--border-active);
}

/* Steps */
.step { display: flex; gap: 12px; align-items: flex-start; margin-bottom: 12px; }
.step-num {
  width: 24px; height: 24px; min-width: 24px; border-radius: 50%;
  background: var(--accent-glow); color: var(--accent);
  font-size: 11px; font-weight: 600;
  display: flex; align-items: center; justify-content: center;
}
.step-txt { font-size: 13px; font-weight: 500; }
.step-sub { font-size: 12px; color: var(--text-secondary); margin-top: 2px; }

/* Code */
.code-block {
  background: var(--bg-input); border: 1px solid var(--border);
  border-radius: var(--radius-sm); padding: 12px 14px;
  font-family: 'JetBrains Mono', 'Fira Code', monospace;
  font-size: 12px; position: relative; margin: 8px 0;
  line-height: 1.7; word-break: break-all;
}
.copy-btn {
  position: absolute; right: 8px; top: 8px;
  background: var(--bg-card); border: 1px solid var(--border);
  border-radius: 6px; padding: 3px 10px; font-size: 10px;
  cursor: pointer; color: var(--text-secondary); transition: all 0.15s;
}
.copy-btn:hover { border-color: var(--accent); color: var(--accent); }

/* History */
.history-item {
  padding: 12px; border-bottom: 1px solid var(--border);
  margin-bottom: 8px; transition: background 0.15s;
}
.history-item:hover { background: var(--bg-card-hover); }
.timestamp { font-size: 10px; color: var(--text-muted); }
.category { font-size: 13px; font-weight: 500; margin-top: 2px; }
.hist-title { font-size: 13px; font-weight: 500; margin-top: 4px; }
.hist-preview { font-size: 12px; color: var(--text-secondary); margin-top: 4px; line-height: 1.5; }
.hist-stats { font-size: 11px; color: var(--text-secondary); margin-top: 6px; }
.hist-links { font-size: 12px; margin-top: 6px; font-weight: 500; }

/* Date filter */
.date-filter { display: flex; gap: 6px; margin-bottom: 12px; flex-wrap: wrap; }
.date-pill {
  padding: 5px 14px; font-size: 11px; font-weight: 500;
  border: 1px solid var(--border); border-radius: 99px;
  cursor: pointer; color: var(--text-secondary); background: transparent;
  transition: all 0.15s;
}
.date-pill:hover { border-color: var(--border-active); color: var(--text-primary); }
.date-pill.active {
  background: var(--accent-glow); color: var(--accent);
  border-color: var(--border-active);
}
.history-count { font-size: 11px; color: var(--text-muted); margin-bottom: 10px; }

/* Links */
a { color: var(--blue); text-decoration: none; transition: color 0.15s; }
a:hover { color: var(--accent); }

.section-label {
  font-size: 11px; font-weight: 600; color: var(--text-muted);
  text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 10px;
}

.divider { border: none; border-top: 1px solid var(--border); margin: 14px 0; }
.muted { font-size: 12px; color: var(--text-secondary); }

.pill-row { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 8px; }

/* Animations */
@keyframes fadeIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: none; } }
.card { animation: fadeIn 0.4s ease-out both; }
.card:nth-child(2) { animation-delay: 0.1s; }
.card:nth-child(3) { animation-delay: 0.2s; }
CSSEOF

# Write docs/index.html
cat > docs/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>APHONE · Research Agent v2.0</title>
<meta name="description" content="AI-powered research agent running natively on Android. Summarizes videos, texts, papers. Finds insights.">
<link rel="stylesheet" href="style.css">
</head>
<body>
<div class="root">

  <div class="card hero">
    <h1>APHONE Research Agent</h1>
    <p class="tagline">Summarize • Discover • Analyze — from your phone</p>
    <div style="margin-top:12px;">
      <span class="badge badge-purple">v2.0</span>
      <span class="badge badge-green">Bulletproof</span>
      <span class="badge badge-blue">Termux NDK</span>
    </div>
    <div class="flow">
      <div class="flow-box">📱 Telegram</div>
      <div class="flow-arrow">→</div>
      <div class="flow-box">📹 Transcript</div>
      <div class="flow-arrow">→</div>
      <div class="flow-box">🔎 Serper</div>
      <div class="flow-arrow">→</div>
      <div class="flow-box">📚 arXiv</div>
      <div class="flow-arrow">→</div>
      <div class="flow-box">✍️ Summarize</div>
      <div class="flow-arrow">→</div>
      <div class="flow-box">📄 Report</div>
    </div>
  </div>

  <div class="card">
    <div class="section-label">One-command install</div>
    <div class="code-block" id="install-cmd">
      curl -fsSL https://raw.githubusercontent.com/muxd22-alt/APHONE/main/setup.sh | bash
      <button class="copy-btn" onclick="copyText('curl -fsSL https://raw.githubusercontent.com/muxd22-alt/APHONE/main/setup.sh | bash')">copy</button>
    </div>
  </div>

  <div class="card">
    <div class="tab-row">
      <button class="tab active" onclick="showTab('features')">✨ Features</button>
      <button class="tab" onclick="showTab('setup')">Setup</button>
      <button class="tab" onclick="showTab('run')">How to run</button>
      <button class="tab" onclick="showTab('commands')">Commands</button>
      <button class="tab" onclick="showTab('history')">📜 History</button>
    </div>

    <div id="tab-features">
      <div class="step"><div class="step-num">📹</div><div><div class="step-txt">YouTube Summarizer</div><div class="step-sub">Extracts transcripts via youtube-transcript-api + yt-dlp fallback</div></div></div>
      <div class="step"><div class="step-num">🔎</div><div><div class="step-txt">Serper Web Search</div><div class="step-sub">Google-powered context enrichment via Serper.dev API</div></div></div>
      <div class="step"><div class="step-num">📚</div><div><div class="step-txt">arXiv Paper Discovery</div><div class="step-sub">Async academic paper search across all disciplines</div></div></div>
      <div class="step"><div class="step-num">✍️</div><div><div class="step-txt">Smart Summarization</div><div class="step-sub">Extractive pre-processing + LLM-powered synthesis on every request</div></div></div>
      <div class="step"><div class="step-num">📌</div><div><div class="step-txt">Key Insights</div><div class="step-sub">Auto-extracted bullet points and topic detection</div></div></div>
      <div class="step"><div class="step-num">🛡️</div><div><div class="step-txt">Bulletproof</div><div class="step-sub">Graceful degradation — every component has fallbacks</div></div></div>
    </div>

    <div id="tab-setup" style="display:none">
      <div class="step"><div class="step-num">1</div><div><div class="step-txt">Install system packages</div><div class="step-sub">python · git · gh · ffmpeg · llama-cpp</div></div></div>
      <div class="step"><div class="step-num">2</div><div><div class="step-txt">Install Python libs</div><div class="step-sub">telegram-bot · httpx · yt-dlp · youtube-transcript-api · feedparser</div></div></div>
      <div class="step"><div class="step-num">3</div><div><div class="step-txt">Configure API keys</div><div class="step-sub">Telegram token + Serper key → stored in local .env (never committed)</div></div></div>
      <div class="step"><div class="step-num">4</div><div><div class="step-txt">Download LLM</div><div class="step-sub">Gemma 3 270M — powers the analysis and summarization engine</div></div></div>
      <div class="step"><div class="step-num">5</div><div><div class="step-txt">Git push → GitHub Pages</div><div class="step-sub">Auto-publishes your research dashboard</div></div></div>
    </div>

    <div id="tab-run" style="display:none">
      <div class="section-label">Quick Launch</div>
      <div class="code-block">
        bash ~/start_aphone.sh
        <button class="copy-btn" onclick="copyText('bash ~/start_aphone.sh')">copy</button>
      </div>
      <hr class="divider">
      <div class="section-label">Manual (no LLM)</div>
      <div class="code-block">
        cd ~/aphone && python nano_agent.py
        <button class="copy-btn" onclick="copyText('cd ~/aphone && python nano_agent.py')">copy</button>
      </div>
    </div>

    <div id="tab-commands" style="display:none">
      <div class="step"><div class="step-num">/s</div><div><div class="step-txt">/start — Welcome + capabilities</div></div></div>
      <div class="step"><div class="step-num">/st</div><div><div class="step-txt">/status — Health check (LLM, Serper, transcripts)</div></div></div>
      <div class="step"><div class="step-num">/c</div><div><div class="step-txt">/categories — List research categories</div></div></div>
      <div class="step"><div class="step-num">/q</div><div><div class="step-txt">/search &lt;query> — Quick web search</div></div></div>
      <div class="step"><div class="step-num">↗</div><div><div class="step-txt">Send any URL, text, or link to analyze</div></div></div>
    </div>

    <div id="tab-history" style="display:none">
      <div class="section-label">Research Database</div>
      <div class="date-filter">
        <button class="date-pill active" onclick="filterDate('all')">All</button>
        <button class="date-pill" onclick="filterDate('today')">Today</button>
        <button class="date-pill" onclick="filterDate('yesterday')">Yesterday</button>
        <button class="date-pill" onclick="filterDate('7')">7 Days</button>
        <button class="date-pill" onclick="filterDate('30')">30 Days</button>
      </div>
      <div class="history-count" id="history-count"></div>
      <div id="history-list">
        <div class="muted">No research history yet. Send a link to start!</div>
      </div>
    </div>
  </div>

</div>

<script>
  const tabs = ['features','setup','run','commands','history'];
  function showTab(name) {
    tabs.forEach(t => {
      document.getElementById('tab-'+t).style.display = t===name ? 'block' : 'none';
    });
    document.querySelectorAll('.tab').forEach((b,i) => {
      b.classList.toggle('active', tabs[i]===name);
    });
    if (name === 'history') updateHistoryCount('all');
  }
  function copyText(text) {
    navigator.clipboard.writeText(text).catch(() => {});
  }
  function filterDate(range) {
    const items = document.querySelectorAll('.history-item');
    const now = new Date();
    const todayStr = now.toISOString().slice(0,10);
    const yesterday = new Date(now); yesterday.setDate(now.getDate()-1);
    const yesterdayStr = yesterday.toISOString().slice(0,10);
    let shown = 0;
    items.forEach(item => {
      const d = item.getAttribute('data-date');
      let show = false;
      if (range === 'all') show = true;
      else if (range === 'today') show = (d === todayStr);
      else if (range === 'yesterday') show = (d === yesterdayStr);
      else { const days = parseInt(range); const cutoff = new Date(now); cutoff.setDate(now.getDate()-days); show = new Date(d) >= cutoff; }
      item.style.display = show ? 'block' : 'none';
      if (show) shown++;
    });
    document.querySelectorAll('.date-pill').forEach(b => b.classList.remove('active'));
    event.target.classList.add('active');
    updateHistoryCount(range, shown, items.length);
  }
  function updateHistoryCount(range, shown, total) {
    const el = document.getElementById('history-count');
    const items = document.querySelectorAll('.history-item');
    if (!total) total = items.length;
    if (shown === undefined) shown = total;
    if (total === 0) { el.textContent = ''; return; }
    el.textContent = range === 'all' ? total+' report'+(total!==1?'s':'') : shown+' of '+total+' reports';
  }
</script>
</body>
</html>
HTMLEOF

# .gitignore
cat > .gitignore << 'GIEOF'
*.pyc
__pycache__/
*.gguf
*.log
.env
GIEOF

git add -A
git commit -m "APHONE v2.0: bulletproof rewrite" 2>/dev/null || true

# ── 9. GitHub auth + push ───────────────────────────────────
step "GitHub authentication…"
if [ -n "$GH_TOKEN" ]; then
  REMOTE="https://${GH_TOKEN}@github.com/muxd22-alt/APHONE.git"
  git push -u -f "$REMOTE" main 2>/dev/null || warn "Push failed — check token"
else
  echo -e "${YELLOW}  Authenticate with GitHub:${NC}"
  gh auth login --hostname github.com --git-protocol https --web 2>/dev/null \
    || gh auth login --hostname github.com --git-protocol https 2>/dev/null \
    || warn "GitHub auth skipped"
  git push -u -f origin main 2>/dev/null || {
    warn "Push failed — creating repo…"
    gh repo create muxd22-alt/APHONE --private --source=. --remote=origin --push 2>/dev/null \
      || warn "Repo create failed — do it manually"
  }
fi

gh api -X PUT "repos/muxd22-alt/APHONE/pages" \
  -f source[branch]=main -f source[path]=/docs 2>/dev/null \
  || warn "GitHub Pages API failed — enable in Settings → Pages"

# ── 10. Startup script ──────────────────────────────────────
step "Writing start script…"
cat > "$HOME/start_aphone.sh" << 'STARTEOF'
#!/data/data/com.termux/files/usr/bin/bash
# APHONE v2.0 startup

AGENT_DIR="$HOME/aphone"
MODEL="$HOME/models/model_a.gguf"

# Load env
if [ -f "$AGENT_DIR/.env" ]; then
  set -a; source "$AGENT_DIR/.env"; set +a
fi

echo "[APHONE] Acquiring wakelock…"
termux-wake-lock 2>/dev/null

# Start LLM if available (optional)
LLM_PID=""
if command -v llama-server >/dev/null 2>&1 && [ -f "$MODEL" ]; then
  echo "[APHONE] Starting LLM on :8080 (optional enhancer)…"
  llama-server -m "$MODEL" --port 8080 --ctx-size 4096 -t 4 --no-mmap &
  LLM_PID=$!
  echo "[APHONE] LLM PID: $LLM_PID — waiting for load…"
  for i in $(seq 1 20); do
    sleep 2
    curl -s http://localhost:8080/health | grep -q "ok" && break
    echo "  …loading ($i/20)"
  done
else
  echo "[APHONE] No LLM — running in extractive mode (still powerful!)"
fi

echo "[APHONE] Starting Telegram agent…"
cd "$AGENT_DIR"
python nano_agent.py

# Cleanup
[ -n "$LLM_PID" ] && kill $LLM_PID 2>/dev/null
STARTEOF
chmod +x "$HOME/start_aphone.sh"

# ── Done ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   APHONE v2.0 Setup Complete! 🚀        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Launch:${NC}     bash ~/start_aphone.sh"
echo -e "  ${CYAN}Or manual:${NC}  cd ~/aphone && python nano_agent.py"
echo -e "  ${CYAN}Dashboard:${NC}  https://muxd22-alt.github.io/APHONE/"
echo -e "  ${CYAN}Bot:${NC}        t.me/sdsdwadyasserbot"
echo ""
  echo -e "  ${MAGENTA}What's new in v2.0:${NC}"
  echo -e "    • 🔎 Serper web search (Google-powered)"
  echo -e "    • 📹 YouTube transcript extraction"
  echo -e "    • ✍️ Extractive pre-processing + LLM-powered synthesis"
  echo -e "    • 📌 Auto key-point extraction"
  echo -e "    • 🛡️ Bulletproof error recovery"
echo ""
echo -e "  ${YELLOW}Tip: Set Termux battery to 'Unrestricted'!${NC}"
echo ""
