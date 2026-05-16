/**
 * jusou 爬虫
 * 
 * 从外部页面提取分享链接。
 * 数据输出到 ~/.jusou/index.json，供 Flutter 客户端读取。
 * 
 * 用法: node crawler/index.js
 * 
 * 架构:
 * - 每个资源站写一个 adapter（解析器）
 * - 主循环遍历各站，收集资源
 * - 去重后写入 index.json
 */

const fs = require('fs');
const path = require('path');
const axios = require('axios').default;

const DATA_DIR = path.join(require('os').homedir(), '.jusou');
const INDEX_FILE = path.join(DATA_DIR, 'index.json');
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36';

// ========== Utils ==========

function ensureDir() {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
}

function loadExisting() {
  try {
    if (fs.existsSync(INDEX_FILE)) {
      const raw = fs.readFileSync(INDEX_FILE, 'utf-8');
      return JSON.parse(raw);
    }
  } catch (e) {
    console.warn('Failed to load existing index, starting fresh');
  }
  return [];
}

async function fetch(url) {
  const res = await axios.get(url, {
    headers: {
      'User-Agent': UA,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
    },
    timeout: 15000,
    // 跟进重定向
    maxRedirects: 5,
  });
  return res;
}

// ========== 分享链接提取 ==========

// 常见分享链接格式
const ALIYUN_REGEX = /https?:\/\/(?:www\.)?(?:aliyundrive|alipan)\.com\/s\/[a-zA-Z0-9]+/g;

// 另一类常见网盘链接
const QUARK_REGEX = /https?:\/\/pan\.quark\.cn\/s\/[a-zA-Z0-9]+/g;

// 另一类常见网盘链接
const BAIDU_REGEX = /https?:\/\/pan\.baidu\.com\/s\/[a-zA-Z0-9]+/g;

function extractShareLinks(html) {
  const links = [];
  for (const regex of [ALIYUN_REGEX, QUARK_REGEX, BAIDU_REGEX]) {
    const matches = html.match(regex);
    if (matches) {
      links.push(...matches);
    }
  }
  return [...new Set(links)];
}

function extractSharePwd(html) {
  // 提取码常见格式: "提取码: xxxx" 或 "密码: xxxx"
  const match = html.match(/提取码[：:]\s*([a-zA-Z0-9]{4,6})/);
  if (match) return match[1];
  const match2 = html.match(/密码[：:]\s*([a-zA-Z0-9]{4,6})/);
  if (match2) return match2[1];
  return null;
}

function extractTitle(html) {
  const match = html.match(/<title>([^<]*)<\/title>/);
  if (match) {
    let title = match[1].trim();
    // 去掉站点名称后缀
    title = title.replace(/[-–—|] *.+$/, '').trim();
    // 去掉常见的后缀词
    title = title.replace(/(在线观看|高清|免费|完整版)$/, '').trim();
    return title;
  }
  return '';
}

function guessType(title, html) {
  const lower = (title + ' ' + html).toLowerCase();
  if (lower.includes('电视剧') || lower.includes('剧集') || 
      lower.includes('连续剧') || lower.includes('全集') ||
      lower.includes('第') && lower.includes('集')) {
    return 'tv';
  }
  return 'movie';
}

function extractEpisodeCount(html) {
  // "共XX集"
  const match = html.match(/共\s*(\d+)\s*集/);
  if (match) return parseInt(match[1]);
  return null;
}

function extractFileSize(html) {
  const match = html.match(/(\d+(?:\.\d+)?\s*(?:GB|MB|TB))/i);
  if (match) return match[1];
  return null;
}

function extractYear(title) {
  // 标题中的年份: (2023) 或 [2023]
  const match = title.match(/[\(（\[\[【]\s*(19\d{2}|20\d{2})\s*[\)）\]\]】]/);
  if (match) return match[1];
  return null;
}

function cleanTitle(title) {
  return title
    .replace(/[\(（\[\[【]\s*(19\d{2}|20\d{2})\s*[\)）\]\]】]/, '') // 去除年份
    .replace(/\s+/g, ' ')
    .trim();
}

// ========== Adapters ==========

const adapters = [];

// ===== Adapter 1 =====
// 通过搜索结果页面提取
adapters.push({
  name: '外部适配器 1',
  async crawl() {
    const results = [];
    // 取最新电影列表
    try {
      const res = await fetch('https://www.kxyytv.com/vodtype/1.html');
      const html = res.data;
      // 提取链接列表
      const linkRegex = /<a[^>]*href="(\/voddetail\/[^"]+)"[^>]*title="([^"]*)"[^>]*>/g;
      let m;
      while ((m = linkRegex.exec(html)) !== null) {
        const detailUrl = `https://www.kxyytv.com${m[1]}`;
        const title = m[2];
        results.push({ title, detailUrl });
      }
    } catch (e) {
      console.warn('外部适配器 1 抓取失败:', e.message);
    }
    return results;
  },
  async parseDetail(detailUrl, item) {
    try {
      const res = await fetch(detailUrl);
      const html = res.data;
      const links = extractShareLinks(html);
      if (links.length === 0) return null;
      const pwd = extractSharePwd(html);
      const year = extractYear(item.title);
      const cleanName = cleanTitle(item.title);
      return {
        id: `source_1_${Buffer.from(links[0]).toString('base64').slice(0, 16)}`,
        title: cleanName,
        year,
        type: guessType(cleanName, html),
        episode_count: extractEpisodeCount(html) || null,
        poster_url: null,
        share_url: links[0],
        share_pwd: pwd,
        file_size: extractFileSize(html),
        source: 'source_1',
        updated_at: new Date().toISOString(),
      };
    } catch (e) {
      return null;
    }
  },
});

// ===== Adapter 2 =====
adapters.push({
  name: '外部适配器 2',
  async crawl() {
    const results = [];
    try {
      const res = await fetch('https://didahd.pro/vodtype/1.html');
      const html = res.data;
      const linkRegex = /<a[^>]*href="(\/voddetail\/[^"]+)"[^>]*title="([^"]*)"[^>]*>/g;
      let m;
      while ((m = linkRegex.exec(html)) !== null) {
        results.push({
          title: m[2],
          detailUrl: `https://didahd.pro${m[1]}`,
        });
      }
    } catch (e) {
      console.warn('外部适配器 2 抓取失败:', e.message);
    }
    return results;
  },
  async parseDetail(detailUrl, item) {
    try {
      const res = await fetch(detailUrl);
      const html = res.data;
      const links = extractShareLinks(html);
      if (links.length === 0) return null;
      const pwd = extractSharePwd(html);
      const year = extractYear(item.title);
      const cleanName = cleanTitle(item.title);
      return {
        id: `source_2_${Buffer.from(links[0]).toString('base64').slice(0, 16)}`,
        title: cleanName,
        year,
        type: guessType(cleanName, html),
        episode_count: extractEpisodeCount(html) || null,
        poster_url: null,
        share_url: links[0],
        share_pwd: pwd,
        file_size: extractFileSize(html),
        source: 'source_2',
        updated_at: new Date().toISOString(),
      };
    } catch (e) {
      return null;
    }
  },
});

// ===== Adapter 3 =====
adapters.push({
  name: '外部适配器 3',
  async crawl() {
    const results = [];
    try {
      const res = await fetch('https://www.zhenlang.cc/vodtype/1.html');
      const html = res.data;
      const linkRegex = /<a[^>]*href="(\/voddetail\/[^"]+)"[^>]*title="([^"]*)"[^>]*>/g;
      let m;
      while ((m = linkRegex.exec(html)) !== null) {
        results.push({
          title: m[2],
          detailUrl: `https://www.zhenlang.cc${m[1]}`,
        });
      }
    } catch (e) {
      console.warn('外部适配器 3 抓取失败:', e.message);
    }
    return results;
  },
  async parseDetail(detailUrl, item) {
    try {
      const res = await fetch(detailUrl);
      const html = res.data;
      const links = extractShareLinks(html);
      if (links.length === 0) return null;
      const pwd = extractSharePwd(html);
      const year = extractYear(item.title);
      const cleanName = cleanTitle(item.title);
      return {
        id: `source_3_${Buffer.from(links[0]).toString('base64').slice(0, 16)}`,
        title: cleanName,
        year,
        type: guessType(cleanName, html),
        episode_count: extractEpisodeCount(html) || null,
        poster_url: null,
        share_url: links[0],
        share_pwd: pwd,
        file_size: extractFileSize(html),
        source: 'source_3',
        updated_at: new Date().toISOString(),
      };
    } catch (e) {
      return null;
    }
  },
});

// ========== Main ==========

async function main() {
  console.log('🔍 jusou 爬虫启动');
  console.log(`📁 数据目录: ${DATA_DIR}`);
  ensureDir();

  const existing = loadExisting();
  const existingUrls = new Set(existing.map(r => r.share_url));
  console.log(`📦 已有 ${existing.length} 条记录`);

  let allResources = [...existing];
  let newCount = 0;

  for (const adapter of adapters) {
    console.log(`\n🌐 爬取: ${adapter.name}`);
    try {
      const items = await adapter.crawl();
      console.log(`   发现 ${items.length} 个资源链接`);

      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        console.log(`   [${i + 1}/${items.length}] ${item.title}`);

        try {
          const resource = await adapter.parseDetail(item.detailUrl, item);
          if (resource && !existingUrls.has(resource.share_url)) {
            allResources.push(resource);
            existingUrls.add(resource.share_url);
            newCount++;
            console.log(`      ✅ 新增: ${resource.title} → ${resource.share_url}`);
          } else if (resource) {
            console.log(`      ⏭️ 已存在, 跳过`);
          } else {
            console.log(`      ⏭️ 无分享链接, 跳过`);
          }
        } catch (e) {
          console.warn(`      ❌ 解析失败: ${e.message}`);
        }

        // 每个请求之间等 500ms，不要太快
        await new Promise(r => setTimeout(r, 500));
      }
    } catch (e) {
      console.warn(`   ❌ 爬取失败: ${e.message}`);
    }
  }

  // 去重
  const seen = new Set();
  const deduped = allResources.filter(r => {
    const key = r.share_url;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });

  // 按更新时间排序
  deduped.sort((a, b) => new Date(b.updated_at) - new Date(a.updated_at));

  fs.writeFileSync(INDEX_FILE, JSON.stringify(deduped, null, 2), 'utf-8');
  console.log(`\n✅ 完成! 共计 ${deduped.length} 条记录 (新增 ${newCount} 条)`);
  console.log(`   索引文件: ${INDEX_FILE}`);
}

main().catch(e => {
  console.error('爬虫执行失败:', e);
  process.exit(1);
});
