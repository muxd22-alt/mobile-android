# 🔬 APHONE · Research Agent v2.0
> *Bulletproof research intelligence from your phone.*

[![Termux Support](https://img.shields.io/badge/OS-Termux_NDK-green?style=for-the-badge&logo=android)](https://termux.dev/)
[![Serper](https://img.shields.io/badge/Search-Serper_API-blue?style=for-the-badge)](https://serper.dev/)
[![License](https://img.shields.io/badge/License-Private-red?style=for-the-badge)](LICENSE)

---

## 🚀 What's New in v2.0

APHONE v2.0 is a **complete rewrite** — no more relying on a tiny LLM for analysis. The agent now uses a powerful multi-source pipeline that works **with or without** a local LLM.

### ⚡ Key Capabilities
- **📹 YouTube Summarizer:** Extracts transcripts via `youtube-transcript-api` with `yt-dlp` subtitle fallback
- **🔎 Serper Web Search:** Google-powered context enrichment via [Serper.dev](https://serper.dev/) API
- **📚 arXiv Discovery:** Async academic paper search across all disciplines
- **✍️ Smart Summarization:** Extractive pre-processing + LLM-powered synthesis for every request
- **📌 Key Insights:** Auto-extracted bullet points and topic detection
- **🛡️ Bulletproof:** Every component has graceful fallbacks — nothing crashes the pipeline

---

## 🏗️ Architecture
```
Telegram Message
    │
    ├── YouTube URL → transcript-api → yt-dlp fallback
    ├── arXiv URL → API fetch → paper metadata
    ├── Any URL → HTTP fetch → HTML-to-text
    └── Plain text → direct analysis
          │
          ▼
    ┌─────────────────┐
    │  Topic Extraction│ (frequency-based keyword detection)
    └────────┬────────┘
             │
    ┌────────▼────────┐     ┌──────────────┐
    │  Serper Search   │────▶│ Web Context   │
    └────────┬────────┘     └──────────────┘
             │
    ┌────────▼────────┐     ┌──────────────┐
    │  arXiv Search    │────▶│ Academic Refs │
    └────────┬────────┘     └──────────────┘
             │
    ┌────────▼────────┐
    │  Extractive Sum. │ (TextRank — no LLM needed)
    └────────┬────────┘
             │
    ┌────────▼────────┐
    │  LLM Synthesis   │ (explains and connects all findings)
    └────────┬────────┘
             │
    ┌────────▼────────┐
    │  Markdown Report │ → db/ + RESEARCH_LOG.md → GitHub Pages
    └─────────────────┘
```

---

## 📦 Installation (Termux)

```bash
curl -fsSL https://raw.githubusercontent.com/muxd22-alt/APHONE/main/setup.sh | bash
```

### 🔐 Required Keys
| Key | Purpose | How to Get |
|:---|:---|:---|
| `APHONE_TOKEN` | Telegram Bot | [@BotFather](https://t.me/BotFather) |
| `SERPER_API_KEY` | Web Search | [serper.dev/api-keys](https://serper.dev/api-keys) |
| `GH_TOKEN` *(optional)* | GitHub push | [github.com/settings/tokens](https://github.com/settings/tokens) |

All secrets → `~/.aphone/.env` (never committed to git).

---

## 🎮 Bot Commands
| Command | Action |
|:--------|:-------|
| `/start` | Welcome + capabilities |
| `/status` | Health check (LLM, Serper, transcripts) |
| `/categories` | List research categories |
| `/search <query>` | Quick Serper web search |
| **Any message** | Full analysis pipeline |

### Input Types
- **YouTube URL** → transcript extraction + summary + related papers + web context
- **arXiv link** → paper analysis + related work
- **Any URL** → content extraction + insights
- **Plain text** → summarize + find papers + web search

---

## 📂 Project Structure
```
~/aphone/
├── nano_agent.py        # Core research engine
├── RESEARCH_LOG.md      # Unified categorized knowledge base
├── .env                 # API keys (gitignored)
├── db/                  # Individual research reports
├── docs/
│   ├── index.html       # GitHub Pages dashboard
│   └── style.css        # Dark premium theme
└── aphone.log           # Runtime logs
~/models/
└── model_a.gguf         # Optional LLM (Gemma 3 270M)
```

---

## 🛡️ Bulletproof Design

| Component | Primary | Fallback |
|:----------|:--------|:---------|
| YouTube transcript | `youtube-transcript-api` | `yt-dlp` auto-subtitles |
| Web search | Serper API | Skipped gracefully |
| Summarization | LLM synthesis | Extractive fallback |
| LLM server | `llama-server` + Gemma 3 | Extractive fallback |
| Git push | Auto-push | Local save only |

**No single failure kills the pipeline.** Every module degrades gracefully.

---

## ⚙️ Changelog
- **v2.0** — Complete rewrite: Serper search, YouTube transcripts, extractive summarization, bulletproof error handling
- **v1.0** — Initial release: basic arXiv loop with tiny local LLM

---

<p align="center">
  Generated with ❤️ by <b>APHONE Research Labs</b><br/>
  <i>"Summarize. Discover. Analyze."</i>
</p>
