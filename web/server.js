// Horizon Angel Web — Server (کامل)
// کد انگلیسی، کامنت فارسی

const express = require('express');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// ─── env ───
const ROOT = path.resolve(__dirname, '..');
const ENV_FILE = path.join(ROOT, '.env.local');

if (!fs.existsSync(ENV_FILE)) {
  console.error('❌ .env.local پیدا نشد در', ENV_FILE);
  process.exit(1);
}

// خواندن env
for (const line of fs.readFileSync(ENV_FILE, 'utf-8').split('\n')) {
  const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)\s*$/);
  if (m) process.env[m[1]] = m[2];
}

const {
  OPENAI_BASE_URL,
  OPENAI_API_KEY,
  OPENAI_MODEL,
  PORT = 3030,
} = process.env;

// ─── master config ───
const MASTER_FILE = path.join(ROOT, '_master.md');
const MASTER_CONFIG = fs.existsSync(MASTER_FILE)
  ? fs.readFileSync(MASTER_FILE, 'utf-8')
  : '(بدون master config)';

// ─── agent discovery ───
const AGENT_DIRS = [
  'academic', 'design', 'engineering', 'finance', 'game-development',
  'gis', 'healthcare', 'marketing', 'paid-media', 'product',
  'project-management', 'sales', 'security', 'spatial-computing',
  'specialized', 'support', 'testing'
];

function listAgents() {
  const out = [];
  for (const d of AGENT_DIRS) {
    const dir = path.join(ROOT, d);
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      if (!f.endsWith('.md')) continue;
      if (f === 'README.md') continue;
      out.push({
        division: d,
        path: `${d}/${f}`,
        id: `${d}/${f.replace('.md', '')}`
      });
    }
  }
  return out;
}

// ─── dispatcher ───
const DISPATCH_RULES = [
  {
    patterns: [/پلتفرم|platform|اپلیکیشن|application|بساز|بسازی|ساخت|کد|develop/i],
    agents: [
      'engineering/engineering-devops-automator.md',
      'engineering/engineering-fullstack-engineer.md',
      'product/product-manager.md',
      'design/design-ui-designer.md'
    ]
  },
  {
    patterns: [/امنیت|security|هک|آسیب|vulnerab|attack/i],
    agents: [
      'security/security-ai-generated-code-auditor.md',
      'security/security-penetration-tester.md'
    ]
  },
  {
    patterns: [/دپلوی|deploy|نصب|استقرار|liara/i],
    agents: ['engineering/engineering-devops-automator.md']
  },
  {
    patterns: [/وضعیت|status|چک|مخزن|repo|git|بک‌آپ|backup/i],
    agents: ['engineering/engineering-devops-automator.md']
  },
  {
    patterns: [/پول|مالی|finance|بودجه|money|cost|هزینه/i],
    agents: ['finance/finance-analyst.md']
  },
  {
    patterns: [/طراحی|design|رنگ|UI|UX|ظاهر|برند|brand/i],
    agents: [
      'design/design-ui-designer.md',
      'design/design-ux-architect.md',
      'design/design-brand-guardian.md'
    ]
  },
  {
    patterns: [/بازار|مارکتینگ|marketing|تبلیغ|محتوا/i],
    agents: ['marketing/marketing-strategist.md']
  },
  {
    patterns: [/تست|test|QA|کیفیت/i],
    agents: ['testing/testing-automation-engineer.md']
  }
];

function pickAgents(text) {
  const picked = new Set();
  for (const rule of DISPATCH_RULES) {
    if (rule.patterns.some(p => p.test(text))) {
      for (const a of rule.agents) {
        const full = path.join(ROOT, a);
        if (fs.existsSync(full)) picked.add(a);
      }
    }
  }
  return [...picked];
}

// ─── call agent ───
async function callAgent(agentPath, userMessage) {
  const full = path.join(ROOT, agentPath);
  if (!fs.existsSync(full)) {
    return `❌ ایجنت پیدا نشد: ${agentPath}`;
  }
  const agentContent = fs.readFileSync(full, 'utf-8');

  // تزریق master + agent prompt
  const fullSystem = `${MASTER_CONFIG}

---

# Agent Prompt

${agentContent}

---

# قالب پاسخ اجباری

پاسخ خود را دقیقاً در این ساختار بنویس:

## 🎯 هدف
(یک خط: چه خواسته شده)

## 📋 وضعیت
- ✅ انجام شد / ⏳ در حال انجام / ❌ نیاز به تأیید / ⚠️ هشدار

## 🔧 اقدامات
(مراحل انجام‌شده)

## 📊 نتیجه
(خروجی واقعی، عدد، جدول، فایل)

## ➡️ قدم بعدی
(اگر لازم است)

مالک پروژه: Mahdi Amoli Moghaddam.
زبان پاسخ: فارسی.`;

  const body = {
    model: OPENAI_MODEL,
    messages: [
      { role: 'system', content: fullSystem },
      { role: 'user', content: userMessage }
    ],
    max_tokens: 2500
  };

  try {
    const res = await fetch(`${OPENAI_BASE_URL}/chat/completions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });

    if (!res.ok) {
      return `❌ خطا از سرور AI: HTTP ${res.status}`;
    }
    const json = await res.json();
    const msg = json.choices?.[0]?.message;
    return msg?.content || msg?.reasoning || '(بدون پاسخ)';
  } catch (e) {
    return `❌ خطای شبکه: ${e.message}`;
  }
}

// ─── git helpers ───
function git(args, cwd) {
  const r = spawnSync('git', args, {
    cwd: cwd || ROOT,
    encoding: 'utf-8',
    timeout: 15000
  });
  return {
    stdout: r.stdout || '',
    stderr: r.stderr || '',
    code: r.status
  };
}

// ─── path safety ───
function safePath(relPath) {
  if (!relPath) return null;
  const clean = String(relPath).replace(/^\.\.\//, '').replace(/^\//, '');
  const full = path.join(ROOT, clean);
  if (!full.startsWith(ROOT)) return null;
  return { clean, full };
}

// ─── express ───
const app = express();
app.use(express.json({ limit: '5mb' }));
app.use(express.static(path.join(__dirname, 'public')));

// لیست ایجنت‌ها
app.get('/api/agents', (req, res) => {
  res.json(listAgents());
});

// انتخاب ایجنت بر اساس متن
app.post('/api/dispatch', (req, res) => {
  const text = (req.body?.message || '').trim();
  if (!text) return res.json({ agents: [] });
  res.json({ agents: pickAgents(text) });
});

// چت
app.post('/api/chat', async (req, res) => {
  const { message, agents } = req.body || {};
  if (!message) return res.status(400).json({ error: 'message required' });

  const targets = (agents && agents.length) ? agents : pickAgents(message);
  if (!targets.length) {
    return res.json({
      replies: [{
        agent: 'dispatcher',
        text: '## 🎯 هدف\nدرخواست شما دریافت شد.\n\n## 📋 وضعیت\n⚠️ هیچ ایجنتی برای این درخواست پیدا نشد.\n\n## 📊 نتیجه\nلطفاً واضح‌تر بگویید یا از پنل چپ یک ایجنت انتخاب کنید.'
      }]
    });
  }

  const replies = [];
  for (const a of targets) {
    const text = await callAgent(a, message);
    replies.push({ agent: a, text });
  }
  res.json({ replies });
});

// وضعیت گیت
app.post('/api/git/status', (req, res) => {
  const repo = req.body?.repo || ROOT;
  res.json({
    status: git(['status', '--short'], repo),
    branch: git(['branch', '--show-current'], repo),
    log: git(['log', '-5', '--oneline'], repo)
  });
});

// pull گیت
app.post('/api/git/pull', (req, res) => {
  const repo = req.body?.repo || ROOT;
  res.json(git(['pull', '--ff-only'], repo));
});

// ساخت فایل
app.post('/api/file/create', (req, res) => {
  const p = safePath(req.body?.path);
  if (!p) return res.status(400).json({ error: 'invalid path' });

  try {
    fs.mkdirSync(path.dirname(p.full), { recursive: true });
    fs.writeFileSync(p.full, req.body?.content || '', 'utf-8');
    res.json({ ok: true, path: p.clean });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

// خواندن فایل
app.post('/api/file/read', (req, res) => {
  const p = safePath(req.body?.path);
  if (!p) return res.status(400).json({ error: 'invalid path' });

  try {
    const content = fs.readFileSync(p.full, 'utf-8');
    res.json({ ok: true, path: p.clean, content });
  } catch (e) {
    res.status(404).json({ error: String(e) });
  }
});

// لیست پوشه
app.post('/api/file/list', (req, res) => {
  const p = safePath(req.body?.path || '.');
  if (!p) return res.status(400).json({ error: 'invalid path' });

  try {
    const items = fs.readdirSync(p.full).map(name => {
      const full = path.join(p.full, name);
      let dir = false;
      let size = 0;
      try {
        const st = fs.statSync(full);
        dir = st.isDirectory();
        size = st.size;
      } catch {}
      return { name, dir, size };
    });
    res.json({ ok: true, path: p.clean, items });
  } catch (e) {
    res.status(404).json({ error: String(e) });
  }
});

// ─── start ───
app.listen(PORT, '127.0.0.1', () => {
  const n = listAgents().length;
  console.log('');
  console.log('✅ Horizon Angel Web');
  console.log(`   http://127.0.0.1:${PORT}`);
  console.log(`   Owner:  Mahdi Amoli Moghaddam`);
  console.log(`   Model:  ${OPENAI_MODEL}`);
  console.log(`   Agents: ${n}`);
  console.log(`   Root:   ${ROOT}`);
  console.log('');
});
