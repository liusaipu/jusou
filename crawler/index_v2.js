/**
 * jusou 爬虫 v2
 * 
 * 数据源: 自行抓取公开资源站，提取阿里云盘链接
 * 
 * 当前已知含云盘链接的资源站:
 * - NO视频 (novipnoad.com) → 但当前被墙
 * - 其他站需要验证
 * 
 * 临时策略: 只合并已经存在的真实索引数据
 * 后续手动维护 index.json 或通过社区共享
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const DATA_DIR = path.join(os.homedir(), '.jusou');
const INDEX_FILE = path.join(DATA_DIR, 'index.json');

function ensureDir() {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
}

// 仅放真实可打开的分享链接。不要写入 example/demo/sample/test 这类占位链接，
// 否则 App 搜索结果会指向无效分享页。
// 实际使用时，可以通过以下方式扩充:
// 1. 在 jusou App 内点击 "添加资源" 手动录入
// 2. 从社区共享的 index.json 同步
// 3. 未来接入资源搜索引擎 API
const seedData = [];

function generateIndex() {
  ensureDir();
  const existing = [];
  try {
    if (fs.existsSync(INDEX_FILE)) {
      existing.push(...JSON.parse(fs.readFileSync(INDEX_FILE, 'utf-8')));
    }
  } catch (e) { /* ignore */ }

  // 合并种子数据，去重
  const existingUrls = new Set(existing.map(r => r.share_url));
  for (const seed of seedData) {
    if (!existingUrls.has(seed.share_url)) {
      existing.push(seed);
      existingUrls.add(seed.share_url);
    }
  }

  fs.writeFileSync(INDEX_FILE, JSON.stringify(existing, null, 2), 'utf-8');
  console.log(`✅ 索引已生成: ${INDEX_FILE}`);
  console.log(`   共计 ${existing.length} 条记录`);
}

generateIndex();
