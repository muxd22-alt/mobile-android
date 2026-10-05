#!/usr/bin/env python3
"""
APHONE Research Agent v2.0 — Bulletproof Edition
=================================================
Pipeline:
  1. YouTube → transcript extraction via youtube-transcript-api + yt-dlp fallback
  2. Text/URL → Serper web search for context enrichment
  3. arXiv → deep academic paper discovery
  4. Summarization → extractive pre-processing + LLM synthesis
  5. Insights → key takeaways, themes, gaps
  6. Report → categorized markdown → GitHub Pages

Uses Serper API for web search, youtube-transcript-api for transcripts,
and llama-server (Gemma 3) for content analysis and explanation.
"""

import os, sys, time, re, json, asyncio, subprocess, logging, hashlib
from datetime import datetime, timezone
from pathlib import Path
from collections import Counter

# ── Logging ──────────────────────────────────────────────────
logging.basicConfig(
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    level=logging.INFO,
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(os.path.expanduser("~/aphone/aphone.log"), mode="a"),
    ],
)
log = logging.getLogger("aphone")

# ── .env loader ──────────────────────────────────────────────
def load_env():
    env_path = Path(__file__).parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if line and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

load_env()

# ── Config ───────────────────────────────────────────────────
BOT_TOKEN    = os.getenv("APHONE_TOKEN", "")
SERPER_KEY   = os.getenv("SERPER_API_KEY", "")
LLM_PORT     = int(os.getenv("LLM_PORT", "8080"))
AGENT_DIR    = Path(os.path.expanduser("~/aphone"))
DB_DIR       = AGENT_DIR / "db"
REPORT_FILE  = AGENT_DIR / "RESEARCH_LOG.md"
INDEX_FILE   = AGENT_DIR / "docs" / "index.html"

DB_DIR.mkdir(parents=True, exist_ok=True)
(AGENT_DIR / "docs").mkdir(parents=True, exist_ok=True)

if not BOT_TOKEN:
    log.error("APHONE_TOKEN not set. Export it or add to .env")
    sys.exit(1)

# ── Lazy imports (installed by setup.sh) ─────────────────────
try:
    import httpx
except ImportError:
    log.error("httpx not installed. Run: pip install httpx")
    sys.exit(1)

try:
    import feedparser
except ImportError:
    feedparser = None
    log.warning("feedparser not installed — arXiv search disabled")

try:
    from youtube_transcript_api import YouTubeTranscriptApi
    HAS_YT_TRANSCRIPT = True
except ImportError:
    HAS_YT_TRANSCRIPT = False
    log.warning("youtube-transcript-api not installed — transcript extraction limited")

from telegram import Update
from telegram.ext import (
    Application, MessageHandler, ContextTypes,
    CommandHandler, filters,
)
from telegram.request import HTTPXRequest

# ═════════════════════════════════════════════════════════════
# SERPER WEB SEARCH
# ═════════════════════════════════════════════════════════════
async def serper_search(query: str, num: int = 10) -> list[dict]:
    """Google search via Serper.dev API."""
    if not SERPER_KEY:
        log.warning("SERPER_API_KEY not set — web search skipped")
        return []
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.post(
                "https://google.serper.dev/search",
                headers={"X-API-KEY": SERPER_KEY, "Content-Type": "application/json"},
                json={"q": query, "num": num},
            )
            r.raise_for_status()
            data = r.json()
            results = []
            for item in data.get("organic", []):
                results.append({
                    "title": item.get("title", ""),
                    "snippet": item.get("snippet", ""),
                    "link": item.get("link", ""),
                })
            if data.get("knowledgeGraph"):
                kg = data["knowledgeGraph"]
                results.insert(0, {
                    "title": kg.get("title", ""),
                    "snippet": kg.get("description", ""),
                    "link": kg.get("website", ""),
                    "type": "knowledge_graph",
                })
            log.info(f"Serper: {len(results)} results for '{query}'")
            return results
    except Exception as e:
        log.error(f"Serper search failed: {e}")
        return []


# ═════════════════════════════════════════════════════════════
# YOUTUBE TRANSCRIPT EXTRACTION
# ═════════════════════════════════════════════════════════════
def extract_video_id(url: str) -> str | None:
    """Extract YouTube video ID from various URL formats."""
    patterns = [
        r"(?:youtube\.com/watch\?.*v=|youtu\.be/|youtube\.com/embed/|youtube\.com/v/|youtube\.com/shorts/)([a-zA-Z0-9_-]{11})",
    ]
    for p in patterns:
        m = re.search(p, url)
        if m:
            return m.group(1)
    return None


async def get_youtube_transcript(url: str) -> dict:
    """
    Extract transcript + metadata from YouTube video.
    Strategy: youtube-transcript-api first, yt-dlp subtitle fallback.
    """
    video_id = extract_video_id(url)
    result = {"title": "", "description": "", "transcript": "", "duration": 0,
              "uploader": "", "tags": [], "source": url, "video_id": video_id or ""}

    # 1. Get metadata via yt-dlp
    try:
        proc = await asyncio.create_subprocess_exec(
            "yt-dlp", "--dump-json", "--no-playlist", "--no-download", url,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=30)
        if proc.returncode == 0:
            data = json.loads(stdout.decode("utf-8", errors="replace"))
            result["title"] = data.get("title", "")
            result["description"] = (data.get("description") or "")[:1500]
            result["duration"] = data.get("duration", 0)
            result["uploader"] = data.get("uploader", "")
            result["tags"] = data.get("tags", [])[:15]
    except Exception as e:
        log.warning(f"yt-dlp metadata failed: {e}")

    # 2. Extract transcript
    if video_id and HAS_YT_TRANSCRIPT:
        try:
            transcript_list = YouTubeTranscriptApi.get_transcript(
                video_id, languages=["en", "ar", "fr", "es", "de", "pt"]
            )
            result["transcript"] = " ".join(
                entry["text"] for entry in transcript_list
            )
            log.info(f"Transcript extracted: {len(result['transcript'])} chars")
        except Exception as e:
            log.warning(f"youtube-transcript-api failed: {e}")

    # 3. Fallback: yt-dlp auto-subs
    if not result["transcript"] and video_id:
        try:
            proc = await asyncio.create_subprocess_exec(
                "yt-dlp", "--write-auto-sub", "--sub-lang", "en",
                "--skip-download", "--sub-format", "vtt",
                "-o", f"/tmp/aphone_{video_id}", url,
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
            )
            await asyncio.wait_for(proc.communicate(), timeout=60)
            vtt_path = f"/tmp/aphone_{video_id}.en.vtt"
            if os.path.exists(vtt_path):
                raw = Path(vtt_path).read_text(errors="replace")
                lines = [l.strip() for l in raw.splitlines()
                         if l.strip() and not re.match(r"^\d", l) and "-->" not in l
                         and l.strip() != "WEBVTT" and not l.startswith("Kind:")]
                result["transcript"] = " ".join(dict.fromkeys(lines))
                os.remove(vtt_path)
                log.info(f"VTT fallback transcript: {len(result['transcript'])} chars")
        except Exception as e:
            log.warning(f"yt-dlp subtitle fallback failed: {e}")

    return result


# ═════════════════════════════════════════════════════════════
# ARXIV SEARCH (robust, non-blocking)
# ═════════════════════════════════════════════════════════════
async def arxiv_search(keywords: list[str], max_results: int = 20) -> list[dict]:
    """Search arXiv API asynchronously."""
    if not feedparser:
        return []
    papers = []
    seen = set()

    async with httpx.AsyncClient(timeout=15) as client:
        for kw in keywords[:6]:
            query = kw.replace(" ", "+")
            url = (
                f"https://export.arxiv.org/api/query"
                f"?search_query=all:{query}"
                f"&start=0&max_results=8"
                f"&sortBy=relevance&sortOrder=descending"
            )
            try:
                r = await client.get(url)
                feed = feedparser.parse(r.text)
                for entry in feed.entries:
                    if entry.id not in seen:
                        seen.add(entry.id)
                        papers.append({
                            "title": entry.title.replace("\n", " "),
                            "summary": entry.summary[:600],
                            "url": entry.id,
                            "authors": [a.name for a in entry.authors][:4],
                            "date": entry.get("published", "")[:10],
                        })
                log.info(f"arXiv '{kw}': {len(feed.entries)} hits")
            except Exception as e:
                log.warning(f"arXiv error for '{kw}': {e}")
            await asyncio.sleep(1.5)  # rate limit

    return papers[:max_results]


# ═════════════════════════════════════════════════════════════
# TEXT SUMMARIZER (extractive — no LLM needed)
# ═════════════════════════════════════════════════════════════
def extractive_summarize(text: str, num_sentences: int = 12) -> str:
    """
    TextRank-inspired extractive summarization.
    Picks the most representative sentences without needing an LLM.
    """
    if not text or len(text) < 100:
        return text

    sentences = re.split(r'(?<=[.!?])\s+', text)
    if len(sentences) <= num_sentences:
        return text

    # Word frequency scoring
    words = re.findall(r'\b[a-zA-Z]{3,}\b', text.lower())
    stop_words = {
        "the", "and", "for", "that", "this", "with", "are", "was", "were",
        "from", "have", "has", "had", "been", "will", "would", "could",
        "should", "can", "not", "but", "all", "they", "their", "there",
        "what", "when", "where", "which", "who", "how", "about", "into",
        "than", "then", "each", "other", "some", "such", "only", "also",
        "more", "most", "very", "just", "like", "being", "over", "between",
        "after", "before", "these", "those", "does", "did", "your", "you",
    }
    filtered = [w for w in words if w not in stop_words]
    freq = Counter(filtered)

    # Score each sentence
    scored = []
    for i, sent in enumerate(sentences):
        sent_words = re.findall(r'\b[a-zA-Z]{3,}\b', sent.lower())
        if not sent_words or len(sent) < 20:
            continue
        score = sum(freq.get(w, 0) for w in sent_words) / (len(sent_words) ** 0.5)
        # Boost early sentences (position bias)
        if i < 3:
            score *= 1.5
        scored.append((score, i, sent))

    scored.sort(reverse=True)
    top = sorted(scored[:num_sentences], key=lambda x: x[1])
    return " ".join(s[2] for s in top)


def extract_key_points(text: str, num_points: int = 8) -> list[str]:
    """Extract key bullet points from text."""
    sentences = re.split(r'(?<=[.!?])\s+', text)
    if len(sentences) <= num_points:
        return sentences

    words = re.findall(r'\b[a-zA-Z]{3,}\b', text.lower())
    freq = Counter(words)

    scored = []
    for sent in sentences:
        if len(sent) < 15 or len(sent) > 300:
            continue
        sent_words = re.findall(r'\b[a-zA-Z]{3,}\b', sent.lower())
        if sent_words:
            score = sum(freq.get(w, 0) for w in sent_words) / len(sent_words)
            scored.append((score, sent.strip()))

    scored.sort(reverse=True)
    return [s[1] for s in scored[:num_points]]


# ═════════════════════════════════════════════════════════════
# LLM — required for every analysis request
# ═════════════════════════════════════════════════════════════
async def llm_call(prompt: str, system: str = "You are a helpful assistant.",
                   max_tokens: int = 512) -> str:
    """Call local llama-server. Required for every analysis request."""
    try:
        async with httpx.AsyncClient(timeout=120) as client:
            r = await client.post(
                f"http://localhost:{LLM_PORT}/v1/chat/completions",
                json={
                    "messages": [
                        {"role": "system", "content": system},
                        {"role": "user", "content": prompt},
                    ],
                    "max_tokens": max_tokens,
                    "temperature": 0.3,
                    "stream": False,
                },
            )
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"].strip()
    except Exception as e:
        log.warning(f"LLM call failed: {e}")
        return ""


async def is_llm_online() -> bool:
    try:
        async with httpx.AsyncClient(timeout=3) as c:
            r = await c.get(f"http://localhost:{LLM_PORT}/health")
            return r.status_code == 200
    except Exception:
        return False


# ═════════════════════════════════════════════════════════════
# CONTENT ANALYSIS ENGINE
# ═════════════════════════════════════════════════════════════
def detect_content_type(text: str) -> str:
    """Detect if input is a URL, YouTube link, arXiv link, or plain text."""
    text = text.strip()
    if re.search(r"(youtube\.com|youtu\.be)", text, re.I):
        return "youtube"
    if re.search(r"arxiv\.org", text, re.I):
        return "arxiv"
    if re.match(r"https?://", text):
        return "url"
    return "text"


def extract_topics(text: str) -> list[str]:
    """Extract key topics/keywords from text for search queries."""
    words = re.findall(r'\b[A-Za-z]{4,}\b', text)
    freq = Counter(w.lower() for w in words)
    stop = {
        "this", "that", "with", "from", "have", "been", "will", "would",
        "could", "should", "about", "their", "there", "which", "these",
        "those", "other", "some", "just", "like", "also", "more", "very",
        "into", "than", "then", "each", "does", "your",
    }
    keywords = [(w, c) for w, c in freq.most_common(30) if w not in stop and c > 1]
    # Group into 2-3 word phrases where possible
    bigrams = []
    word_list = [w.lower() for w in words if w.lower() not in stop and len(w) > 3]
    for i in range(len(word_list) - 1):
        bigrams.append(f"{word_list[i]} {word_list[i+1]}")
    bigram_freq = Counter(bigrams)
    top_bigrams = [b for b, c in bigram_freq.most_common(5) if c > 1]

    topics = top_bigrams[:3] + [w for w, _ in keywords[:4]]
    return topics[:6] if topics else ["general research"]


async def analyze_content(input_text: str, chat_send) -> dict:
    """
    Main analysis pipeline. Works without LLM — LLM only enhances.
    Returns dict with: summary, key_points, papers, web_results, category, source_type
    """
    content_type = detect_content_type(input_text)
    result = {
        "source": input_text.strip(),
        "source_type": content_type,
        "title": "",
        "transcript": "",
        "summary": "",
        "key_points": [],
        "papers": [],
        "web_results": [],
        "category": "General",
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
    }

    # ── Step 1: Content extraction ────────────────────────────
    if content_type == "youtube":
        await chat_send("📹 Extracting YouTube transcript & metadata…")
        yt_data = await get_youtube_transcript(input_text.strip())
        result["title"] = yt_data["title"] or input_text
        result["transcript"] = yt_data["transcript"]
        base_text = yt_data["transcript"] or yt_data["description"]
        topics = extract_topics(base_text) if base_text else [yt_data["title"][:50]]

    elif content_type == "arxiv":
        await chat_send("📄 Fetching arXiv paper info…")
        # Extract arXiv ID and fetch abstract
        arxiv_match = re.search(r"(\d{4}\.\d{4,5})", input_text)
        base_text = ""
        if arxiv_match:
            arxiv_id = arxiv_match.group(1)
            try:
                async with httpx.AsyncClient(timeout=15) as c:
                    r = await c.get(f"https://export.arxiv.org/api/query?id_list={arxiv_id}")
                    if feedparser:
                        feed = feedparser.parse(r.text)
                        if feed.entries:
                            entry = feed.entries[0]
                            result["title"] = entry.title.replace("\n", " ")
                            base_text = entry.summary
            except Exception as e:
                log.warning(f"arXiv fetch failed: {e}")
        topics = extract_topics(base_text) if base_text else ["machine learning"]

    elif content_type == "url":
        await chat_send("🌐 Fetching web page content…")
        try:
            async with httpx.AsyncClient(timeout=15, follow_redirects=True) as c:
                r = await c.get(input_text.strip())
                # Basic HTML to text
                html = r.text
                text = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.S)
                text = re.sub(r'<style[^>]*>.*?</style>', '', text, flags=re.S)
                text = re.sub(r'<[^>]+>', ' ', text)
                text = re.sub(r'\s+', ' ', text).strip()
                base_text = text[:5000]
                title_match = re.search(r'<title>(.*?)</title>', html, re.I | re.S)
                result["title"] = title_match.group(1).strip() if title_match else input_text
        except Exception as e:
            log.warning(f"URL fetch failed: {e}")
            base_text = ""
        topics = extract_topics(base_text) if base_text else ["general"]

    else:  # plain text
        base_text = input_text.strip()
        result["title"] = base_text[:80]
        topics = extract_topics(base_text)

    # ── Step 2: Web search enrichment ─────────────────────────
    await chat_send(f"🔎 Searching the web for context…\n📌 Topics: {', '.join(topics[:4])}")
    await asyncio.sleep(2)  # pace the research
    search_tasks = [serper_search(t, num=5) for t in topics[:3]]
    search_results = await asyncio.gather(*search_tasks, return_exceptions=True)
    for sr in search_results:
        if isinstance(sr, list):
            result["web_results"].extend(sr)

    # Deduplicate web results
    seen_links = set()
    unique_web = []
    for wr in result["web_results"]:
        if wr["link"] not in seen_links:
            seen_links.add(wr["link"])
            unique_web.append(wr)
    result["web_results"] = unique_web[:15]
    await chat_send(f"✅ Web search done — {len(result['web_results'])} sources found")
    await asyncio.sleep(2)

    # ── Step 3: arXiv academic search ─────────────────────────
    await chat_send("📚 Searching arXiv for academic papers…")
    result["papers"] = await arxiv_search(topics[:4])
    await asyncio.sleep(1)
    await chat_send(f"📖 Found {len(result['papers'])} papers")

    # ── Step 4: Extractive pre-summary ─────────────────────────
    await asyncio.sleep(2)
    await chat_send("✍️ Pre-processing text & extracting key points…")
    if base_text:
        extractive_sum = extractive_summarize(base_text, num_sentences=10)
        result["key_points"] = extract_key_points(base_text, num_points=8)
    else:
        combined = "\n".join(
            f"{wr['title']}: {wr['snippet']}" for wr in result["web_results"][:10]
        )
        extractive_sum = extractive_summarize(combined, num_sentences=8)
        result["key_points"] = extract_key_points(combined, num_points=6)
    await chat_send(f"📌 Extracted {len(result['key_points'])} key insights")
    await asyncio.sleep(2)

    # ── Step 5: LLM synthesis (required) ──────────────────────
    await chat_send("🧠 Sending to LLM for deep analysis…\n⏳ This may take a moment…")
    papers_snippet = "\n".join(
        f"- {p['title']}" for p in result["papers"][:8]
    )
    web_snippet = "\n".join(
        f"- {wr['title']}: {wr['snippet'][:80]}" for wr in result["web_results"][:6]
    )
    llm_prompt = (
        f"Content title: {result['title']}\n\n"
        f"Extracted text summary:\n{extractive_sum[:1200]}\n\n"
        f"Related academic papers:\n{papers_snippet}\n\n"
        f"Web search context:\n{web_snippet}\n\n"
        "Based on all the above, write a clear and insightful research summary "
        "(3-4 paragraphs). Explain what this content is about, the key findings, "
        "connections to academic work, and what gaps or opportunities exist. "
        "Use Markdown formatting."
    )
    llm_summary = await llm_call(
        llm_prompt,
        "You are a research analyst. Explain content clearly and find insights.",
        max_tokens=500,
    )
    if llm_summary:
        result["summary"] = llm_summary
        await chat_send("✅ LLM analysis complete")
    else:
        result["summary"] = extractive_sum
        await chat_send("⚠️ LLM unavailable — using extractive summary")
        log.warning("LLM unavailable — falling back to extractive summary")

    # ── Step 6: Auto-categorize ───────────────────────────────
    top_words = [w for w, _ in Counter(
        re.findall(r'\b[A-Za-z]{4,}\b', (result["title"] + " " + " ".join(topics)).lower())
    ).most_common(3)]
    result["category"] = " / ".join(w.title() for w in top_words[:2]) if top_words else "General"

    return result


# ═════════════════════════════════════════════════════════════
# REPORT GENERATION
# ═════════════════════════════════════════════════════════════
def generate_report(analysis: dict) -> str:
    """Generate a full markdown report from analysis results."""
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    report = []
    report.append(f"# Research Report: {analysis['title'][:80]}\n")
    report.append(f"**Source:** {analysis['source']}")
    report.append(f"**Type:** {analysis['source_type']}")
    report.append(f"**Category:** {analysis['category']}")
    report.append(f"**Date:** {analysis['timestamp']}\n")

    report.append("## 📝 Summary\n")
    report.append(analysis["summary"] or "_No summary available._")
    report.append("")

    if analysis["key_points"]:
        report.append("## 📌 Key Insights\n")
        for kp in analysis["key_points"]:
            report.append(f"- {kp}")
        report.append("")

    if analysis["papers"]:
        report.append(f"## 📚 Related Papers ({len(analysis['papers'])})\n")
        for p in analysis["papers"][:12]:
            authors = ", ".join(p["authors"][:3])
            report.append(f"- [{p['title']}]({p['url']}) — {authors} ({p['date']})")
            report.append(f"  > {p['summary'][:150]}…")
        report.append("")

    if analysis["web_results"]:
        report.append(f"## 🌐 Web Context ({len(analysis['web_results'])})\n")
        for wr in analysis["web_results"][:10]:
            report.append(f"- [{wr['title']}]({wr['link']})")
            if wr.get("snippet"):
                report.append(f"  > {wr['snippet'][:120]}")
        report.append("")

    report.append("---\n*Generated by APHONE Research Agent v2.0*\n")
    return "\n".join(report)


def save_report(analysis: dict, report_md: str):
    """Save report to db/ and update RESEARCH_LOG.md + docs/index.html."""
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    filename = f"research_{ts}.md"
    filepath = DB_DIR / filename

    # Save individual report
    filepath.write_text(report_md, encoding="utf-8")

    # Update unified log
    now = analysis["timestamp"]
    cat = analysis["category"]
    log_entry = f"\n### [{now}] {analysis['title'][:60]}\n\n"
    log_entry += f"**Source:** {analysis['source']}\n\n"
    log_entry += f"{analysis['summary'][:500]}\n\n"
    if analysis["key_points"]:
        log_entry += "**Key Points:**\n"
        for kp in analysis["key_points"][:5]:
            log_entry += f"- {kp}\n"
    log_entry += f"\n[📄 Full Report](db/{filename})\n\n---\n"

    if REPORT_FILE.exists():
        content = REPORT_FILE.read_text(encoding="utf-8")
    else:
        content = "# APHONE Research Log\n\n> Auto-generated by APHONE v2.0\n\n---\n"

    section = f"\n## {cat}\n"
    if section in content:
        idx = content.index(section) + len(section)
        content = content[:idx] + log_entry + content[idx:]
    else:
        content += section + log_entry

    REPORT_FILE.write_text(content, encoding="utf-8")

    # Update docs/index.html with new history entry
    if INDEX_FILE.exists():
        html = INDEX_FILE.read_text(encoding="utf-8")
        title_safe = analysis["title"][:70].replace('"', '&quot;').replace('<', '&lt;')
        source_safe = analysis["source"].replace('"', '&quot;').replace('<', '&lt;')
        summary_preview = (analysis["summary"] or "")[:150].replace('"', '&quot;').replace('<', '&lt;')
        papers_count = len(analysis.get("papers", []))
        web_count = len(analysis.get("web_results", []))

        new_item = (
            f'        <div class="history-item" data-date="{date_str}">\n'
            f'          <div class="timestamp">{now}</div>\n'
            f'          <div class="category"><span class="badge badge-purple">{cat}</span></div>\n'
            f'          <div class="hist-title">{title_safe}</div>\n'
            f'          <div class="hist-preview">{summary_preview}…</div>\n'
            f'          <div class="hist-stats">'
            f'📚 {papers_count} papers · 🌐 {web_count} web sources</div>\n'
            f'          <div class="hist-links">'
            f'<a href="{source_safe}" target="_blank">Source</a> · '
            f'<a href="../db/{filename}">Full Report</a></div>\n'
            f'        </div>\n'
        )

        # Remove "No research history" placeholder
        html = html.replace(
            '<div class="muted">No research history yet. Send a link to start!</div>',
            ''
        )

        # Insert after history-list opening
        if 'id="history-list">' in html:
            html = html.replace('id="history-list">',
                                f'id="history-list">\n{new_item}')
            INDEX_FILE.write_text(html, encoding="utf-8")
            log.info(f"Dashboard updated: {title_safe[:40]}")

    log.info(f"Report saved: db/{filename}")
    return filename


# ═════════════════════════════════════════════════════════════
# GITHUB PUSH
# ═════════════════════════════════════════════════════════════
def push_to_github() -> bool:
    try:
        cwd = str(AGENT_DIR)
        subprocess.run(["git", "add", "-A"], cwd=cwd, check=True,
                       capture_output=True, timeout=15)
        subprocess.run(
            ["git", "commit", "-m",
             f"research: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M')}"],
            cwd=cwd, check=True, capture_output=True, timeout=15,
        )
        subprocess.run(["git", "push", "origin", "main"], cwd=cwd,
                       check=True, capture_output=True, timeout=30)
        return True
    except subprocess.CalledProcessError as e:
        log.error(f"Git push failed: {e}")
        return False


# ═════════════════════════════════════════════════════════════
# TELEGRAM HANDLERS
# ═════════════════════════════════════════════════════════════
async def handle_message(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    """Main message handler — routes to analysis pipeline."""
    text = update.message.text.strip()
    chat_id = update.effective_chat.id

    if not text:
        return

    async def chat_send(msg):
        try:
            await ctx.bot.send_message(chat_id, msg)
        except Exception as e:
            log.warning(f"Telegram send failed: {e}")

    try:
        user = update.effective_user
        name = user.first_name if user else "Researcher"
        await chat_send(
            f"� Hey {name}!\n\n"
            f"�🚀 APHONE v2 — Starting deep analysis…\n"
            f"📎 Input: {text[:80]}{'…' if len(text) > 80 else ''}\n\n"
            f"Sit tight — I'll search the web, find papers, and generate a full report."
        )
        await asyncio.sleep(1)

        analysis = await analyze_content(text, chat_send)

        await chat_send("📝 Writing final report…")
        await asyncio.sleep(1)
        report_md = generate_report(analysis)
        filename = save_report(analysis, report_md)

        # Try pushing to GitHub
        await chat_send("📤 Pushing to GitHub…")
        pushed = await asyncio.get_event_loop().run_in_executor(None, push_to_github)

        # Build final response
        resp = []
        resp.append(f"━━━━━━━━━━━━━━━━━━━━")
        resp.append(f"✅ Analysis Complete!")
        resp.append(f"━━━━━━━━━━━━━━━━━━━━\n")
        resp.append(f"📂 Category: {analysis['category']}")
        resp.append(f"📄 Papers found: {len(analysis['papers'])}")
        resp.append(f"🌐 Web sources: {len(analysis['web_results'])}")
        resp.append(f"📊 Report: db/{filename}")

        if analysis["key_points"]:
            resp.append(f"\n📌 **Key Insights:**")
            for kp in analysis["key_points"][:5]:
                resp.append(f"  • {kp[:120]}")

        if analysis.get("summary"):
            resp.append(f"\n📝 **Summary Preview:**")
            resp.append(analysis["summary"][:400] + "…")

        if pushed:
            resp.append(f"\n✅ Published → https://muxd22-alt.github.io/APHONE/")
        else:
            resp.append(f"\n⚠️ GitHub push failed — report saved locally at ~/aphone/db/{filename}")

        resp.append(f"\n💡 Send another link or text to analyze!")
        await chat_send("\n".join(resp))

    except Exception as e:
        log.exception(f"Analysis failed: {e}")
        await chat_send(f"❌ Analysis failed: {str(e)[:200]}\n\nPlease try again or check /status.")


async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    name = user.first_name if user else "there"
    await update.message.reply_text(
        f"� Welcome, {name}!\n\n"
        f"�🔬 **APHONE Research Agent v2.0**\n"
        f"━━━━━━━━━━━━━━━━━━━━\n\n"
        "I'm your personal research assistant. Send me anything and I'll:\n\n"
        "📹 YouTube link → Extract transcript, summarize, find related papers\n"
        "📄 arXiv link → Analyze paper, find related work\n"
        "🌐 Any URL → Extract content, find insights\n"
        "📝 Plain text → Summarize, search web & papers\n\n"
        "Each analysis includes:\n"
        "  • 🔎 Google-powered web search\n"
        "  • 📚 arXiv academic paper discovery\n"
        "  • 🧠 LLM-powered deep synthesis\n"
        "  • 📌 Key insights & bullet points\n"
        "  • 📄 Full report saved to GitHub Pages\n\n"
        "**Commands:**\n"
        "/status — system health check\n"
        "/categories — browse research categories\n"
        "/search <query> — quick web search\n\n"
        "💡 Just paste a link or text to get started!"
    )


async def cmd_status(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    llm_ok = await is_llm_online()
    serper_ok = bool(SERPER_KEY)
    yt_ok = HAS_YT_TRANSCRIPT
    report_count = len(list(DB_DIR.glob("research_*.md")))

    await update.message.reply_text(
        f"**APHONE v2.0 Status**\n"
        f"━━━━━━━━━━━━━━━━\n"
        f"🧠 LLM Server: {'✅' if llm_ok else '⚡ Offline (extractive mode)'}\n"
        f"🔎 Serper API: {'✅ Active' if serper_ok else '❌ No key'}\n"
        f"📹 YT Transcripts: {'✅' if yt_ok else '⚠️ Limited'}\n"
        f"📚 Reports saved: {report_count}\n"
        f"🌐 Dashboard: https://muxd22-alt.github.io/APHONE/"
    )


async def cmd_categories(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if REPORT_FILE.exists():
        cats = re.findall(r"^## (.+)$", REPORT_FILE.read_text(), re.MULTILINE)
        if cats:
            await update.message.reply_text(
                "📂 **Research Categories:**\n" + "\n".join(f"  • {c}" for c in cats)
            )
            return
    await update.message.reply_text("No categories yet — send something to analyze!")


async def cmd_search(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    query = " ".join(ctx.args) if ctx.args else ""
    if not query:
        await update.message.reply_text("Usage: /search <query>")
        return
    await update.message.reply_text(f"🔎 Searching: {query}")
    results = await serper_search(query, num=5)
    if results:
        resp = "\n".join(f"• [{r['title']}]({r['link']})\n  {r['snippet'][:100]}" for r in results[:5])
        await update.message.reply_text(f"**Results:**\n\n{resp}")
    else:
        await update.message.reply_text("No results found.")


# ═════════════════════════════════════════════════════════════
# BOOT
# ═════════════════════════════════════════════════════════════
if __name__ == "__main__":
    log.info("APHONE v2.0 starting…")
    log.info(f"  Serper API: {'configured' if SERPER_KEY else 'NOT SET'}")
    log.info(f"  YT Transcript: {'available' if HAS_YT_TRANSCRIPT else 'limited'}")

    req = HTTPXRequest(connect_timeout=20, read_timeout=60)
    app = (
        Application.builder()
        .token(BOT_TOKEN)
        .request(req)
        .build()
    )

    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("status", cmd_status))
    app.add_handler(CommandHandler("categories", cmd_categories))
    app.add_handler(CommandHandler("search", cmd_search))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    log.info("Polling Telegram…")
    app.run_polling(drop_pending_updates=True, pool_timeout=20)
