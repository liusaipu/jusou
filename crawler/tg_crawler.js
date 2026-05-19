// TG 公开频道爬虫 —— 每周运行一次
// 用法：node crawler/tg_crawler.js
// 输出：~/.jusou/sources/telegram.json
//
// 定期执行（crontab -e 添加）：
// 0 3 * * 0 cd /Users/lobster/myprojects/jusou && node crawler/tg_crawler.js

const fs = require('fs');
const path = require('path');
const os = require('os');
const https = require('https');

const DATA_DIR = path.join(os.homedir(), '.jusou');
const CHANNELS_FILE = path.join(__dirname, 'channels.txt');
const CONFIG_FILE = path.join(DATA_DIR, 'config.json');
const OUTPUT_FILE = path.join(DATA_DIR, 'sources', 'telegram.json');
const MAX_MESSAGES_PER_CHANNEL = 30;
const REQUEST_DELAY_MS = 2000; // Telegram 限速
const CONCURRENCY = 3;

// ─── 网盘链接匹配 ───
const SHARE_PATTERNS = [
  { regex: /https?:\/\/[^\s]*?alipan\.com\/s\/[^\s]+/gi, provider: 'alipan' },
  { regex: /https?:\/\/[^\s]*?aliyundrive\.com\/s\/[^\s]+/gi, provider: 'aliyun' },
  { regex: /https?:\/\/[^\s]*?pan\.quark\.cn\/s\/[^\s]+/gi, provider: 'quark' },
  { regex: /https?:\/\/[^\s]*?drive\.uc\.cn\/s\/[^\s]+/gi, provider: 'uc' },
  { regex: /https?:\/\/[^\s]*?pan\.xunlei\.com\/s\/[^\s]+/gi, provider: 'xunlei' },
  { regex: /https?:\/\/[^\s]*?(?:115cdn|115)\.com\/s\/[^\s]+/gi, provider: '115' },
  { regex: /https?:\/\/[^\s]*?123pan\.com\/s\/[^\s]+/gi, provider: '123pan' },
  { regex: /https?:\/\/[^\s]*?123865\.com\/s\/[^\s]+/gi, provider: '123pan' },
  { regex: /https?:\/\/[^\s]*?pan\.baidu\.com\/s\/[^\s]+/gi, provider: 'baidu' },
  { regex: /https?:\/\/[^\s]*?mypikpak\.com\/s\/[^\s]+/gi, provider: 'pikpak' },
];

// TG 频道链接匹配
const CHANNEL_PATTERN = /https?:\/\/t\.me\/([a-zA-Z0-9_]+)/gi;

// ─── 工具 ───
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function fetchPage(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
      if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode}`));
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data));
      res.on('error', reject);
    }).on('error', reject);
  });
}

function extractShareLinks(text) {
  const links = new Map(); // canonicalUrl -> { url, provider, pwd }
  for (const { regex, provider } of SHARE_PATTERNS) {
    for (const match of text.matchAll(regex)) {
      const url = match[0].split(/\s/)[0].replace(/[.,;)\]>]+$/, '');
      // 提取提取码
      const pwdMatch = new RegExp(`(?:提取码|密码|pwd|password)[：:=]\\s*(\\w+)`, 'i').exec(text);
      const pwd = pwdMatch ? pwdMatch[1] : null;
      const canonical = url.split('?')[0].split('#')[0];
      if (!links.has(canonical)) {
        links.set(canonical, { url: canonical, provider, sharePwd: pwd || null });
      }
    }
  }
  return [...links.values()];
}

function extractChannelNames(html) {
  const names = new Set();
  for (const match of html.matchAll(CHANNEL_PATTERN)) {
    const name = match[1].toLowerCase();
    if (name !== 's' && name !== 'share' && name.length >= 3) {
      names.add(name);
    }
  }
  return [...names];
}

function extractMessageBodies(html) {
  // 从 t.me/s/ 页面提取每条消息的文本
  const messages = [];
  const msgRegex = /<div class="tgme_widget_message_text[^"]*"[^>]*>([\s\S]*?)<\/div>/gi;
  let match;
  while ((match = msgRegex.exec(html)) !== null) {
    let text = match[1]
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .trim();
    if (text.length > 5) messages.push(text);
  }
  return messages;
}

function extractTitle(text) {
  // 尝试从消息中提取资源标题
  const patterns = [
    /[🎬📺🎥🎞️📀💿🔹🔥]{1,3}\s*(.+?)(?:\n|$|https?:\/\/|[🎬📺🎥])/,
    /【(.+?)】/,
    /《(.+?)》/,
    /^#?\s*(.+?)(?:\n|https?:\/\/|$)/,
  ];
  for (const p of patterns) {
    const m = text.match(p);
    if (m && m[1].trim().length > 2 && m[1].trim().length < 80) return m[1].trim();
  }
  // fallback：取第一行
  const firstLine = text.split('\n')[0].replace(/[🎬📺🎥🎞️📀💿🔹🔥]/g, '').trim();
  return firstLine.length > 2 ? firstLine : '未命名资源';
}

function extractYear(text) {
  const m = text.match(/(19\d{2}|20\d{2})/);
  return m ? m[1] : null;
}

function guessType(text) {
  const lower = text.toLowerCase();
  if (/电视剧|国产剧|短剧|集全|\d+\s*集/.test(lower)) return 'tv';
  if (/纪录片|纪实/.test(lower)) return 'documentary';
  if (/综艺/.test(lower)) return 'variety';
  return 'movie';
}

// ─── 主逻辑 ───
async function crawlChannel(name, index, total) {
  console.log(`[${index + 1}/${total}] 爬取 @${name} ...`);
  try {
    const html = await fetchPage(`https://t.me/s/${name}`);
    const messages = extractMessageBodies(html);
    const newChannels = extractChannelNames(html);

    const resources = [];
    let msgCount = Math.min(messages.length, MAX_MESSAGES_PER_CHANNEL);
    for (let i = 0; i < msgCount; i++) {
      const text = messages[i];
      const links = extractShareLinks(text);
      if (links.length === 0) continue;
      const title = extractTitle(text);
      for (const link of links) {
        resources.push({
          id: `tg_${Buffer.from(link.url).toString('base64url').replace(/=/g, '').slice(0, 40)}`,
          title,
          share_url: link.url,
          share_pwd: link.sharePwd,
          source: `tg:${name}`,
          provider: link.provider,
          year: extractYear(text),
          type: guessType(text),
          updated_at: new Date().toISOString(),
          merged_sources: ['tg'],
        });
      }
    }

    console.log(`  -> ${resources.length} 资源, ${newChannels.length} 新频道`);
    return { resources, newChannels, name };
  } catch (err) {
    console.log(`  -> 错误: ${err.message}`);
    return { resources: [], newChannels: [], name };
  }
}

function loadExistingOutput() {
  try {
    if (fs.existsSync(OUTPUT_FILE)) {
      const raw = fs.readFileSync(OUTPUT_FILE, 'utf-8');
      return JSON.parse(raw);
    }
  } catch {}
  return [];
}

function saveOutput(resources) {
  const dir = path.dirname(OUTPUT_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(resources, null, 2));
  console.log(`\n写入 ${resources.length} 条资源 -> ${OUTPUT_FILE}`);
}

function loadChannels() {
  return [...new Set([...loadFileChannels(), ...loadConfigChannels()])];
}

function saveChannels(channels) {
  const normalized = channels
    .map(normalizeChannel)
    .filter(Boolean)
    .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
  fs.writeFileSync(CHANNELS_FILE, normalized.join('\n') + '\n');
  saveConfigChannels(normalized);
}

function loadFileChannels() {
  try {
    const raw = fs.readFileSync(CHANNELS_FILE, 'utf-8');
    return raw.split('\n')
      .map(line => normalizeChannel(line))
      .filter(Boolean);
  } catch {
    return [];
  }
}

function loadConfigChannels() {
  try {
    if (!fs.existsSync(CONFIG_FILE)) return [];
    const raw = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf-8'));
    const settings = raw.settings && typeof raw.settings === 'object' ? raw.settings : raw;
    const channels = settings.telegram_channels || settings.telegramChannels || settings.tg_channels || settings.tgChannels;
    if (!Array.isArray(channels)) return [];
    return channels.map(item => normalizeChannel(String(item))).filter(Boolean);
  } catch {
    return [];
  }
}

function saveConfigChannels(channels) {
  try {
    let config = {};
    if (fs.existsSync(CONFIG_FILE)) {
      config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf-8'));
    }
    if (!config || typeof config !== 'object' || Array.isArray(config)) config = {};
    config.app = config.app || 'jusou';
    config.schema_version = config.schema_version || 1;
    if (!config.settings || typeof config.settings !== 'object' || Array.isArray(config.settings)) {
      config.settings = {};
    }
    config.settings.telegram_channels = channels;
    const dir = path.dirname(CONFIG_FILE);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
  } catch (err) {
    console.warn(`配置文件同步失败: ${err.message}`);
  }
}

function normalizeChannel(raw) {
  let value = raw.trim();
  if (!value || value.startsWith('#')) return null;
  value = value
    .replace(/^https?:\/\/t\.me\/s\//i, '')
    .replace(/^https?:\/\/t\.me\//i, '')
    .replace(/^@/, '')
    .split(/[/?#]/)[0]
    .trim()
    .toLowerCase();
  return /^[a-z0-9_]{3,}$/.test(value) ? value : null;
}

async function main() {
  console.log('Jusou TG Crawler');
  console.log(`频道文件: ${CHANNELS_FILE}`);
  console.log(`输出文件: ${OUTPUT_FILE}\n`);

  // 加载历史输出（合并去重）
  const existingResources = loadExistingOutput();
  const seenUrls = new Set(existingResources.map(r => r.share_url));

  // 加载频道列表
  const channels = loadChannels();
  console.log(`加载 ${channels.length} 个频道, ${existingResources.length} 条历史资源\n`);

  const allNewChannels = new Set();
  let totalNew = 0;

  // 分批并发
  for (let i = 0; i < channels.length; i += CONCURRENCY) {
    const batch = channels.slice(i, i + CONCURRENCY);
    const results = await Promise.all(
      batch.map((name, j) => crawlChannel(name, i + j, channels.length))
    );

    for (const { resources, newChannels } of results) {
      for (const r of resources) {
        if (!seenUrls.has(r.share_url)) {
          seenUrls.add(r.share_url);
          existingResources.push(r);
          totalNew++;
        }
      }
      for (const c of newChannels) allNewChannels.add(c);
    }

    await sleep(REQUEST_DELAY_MS);
  }

  // 去重并保存输出
  saveOutput(existingResources);

  // 更新频道列表
  let newAdded = 0;
  const currentChannels = new Set(loadChannels());
  for (const c of allNewChannels) {
    if (!currentChannels.has(c)) {
      currentChannels.add(c);
      newAdded++;
    }
  }
  if (newAdded > 0) {
    saveChannels([...currentChannels]);
    console.log(`新增 ${newAdded} 个频道`);
  }

  console.log(`\n完成: 新增 ${totalNew} 条资源, 频道列表 +${newAdded}`);
}

main().catch(err => {
  console.error('爬取失败:', err);
  process.exit(1);
});
