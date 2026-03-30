# 功能需求：消费标签 & 位置自动打标

**版本**：v1.5.0  
**状态**：待开发  
**关联文件**：`www/index.html`、`patch-android.sh`

---

## 一、背景与目标

用户在记录消费时，仅有"分类"维度无法满足复杂的回溯需求。例如：
- 同样是"外卖"，用户希望区分"工作日点单"和"周末聚会"
- 同样是"买菜"，用户希望知道是在哪个城市消费的（出差 vs 居家）
- 希望把某类特殊支出（如"演唱会"、"旅行"）单独打标，方便日后查询

本功能引入**自定义标签**（自由文本）和**位置标签**（自动获取定位并转换为城市/区域名称），并在消费记录筛选中支持按标签检索。

---

## 二、功能概述

### 2.1 添加标签（记录消费时）

在快速记录表单中，"备注"行下方增加一个标签输入区域：

```
┌─────────────────────────────────────────────┐
│ [分类 ▼]              [金额 ¥ ___________]   │
│ [备注 ________________________] [记录]       │
│ 标签：[工作报销 ×] [+ 输入标签] [📍]          │
│ 常用：[工作报销] [聚餐] [出差]               │
└─────────────────────────────────────────────┘
```

- **已选标签**：以 chip 形式展示，点击 × 移除
- **输入框**：输入文字后按 Enter 或逗号确认，添加为新 chip
- **📍 按钮**：点击后自动获取当前位置，转换为城市名后以 `📍 城市名` 格式添加为标签
- **快捷标签栏**：显示用户预设标签库（见第四节），点击即可快速添加；若标签库为空则退而显示历史高频标签
- 标签数量无上限，但单个标签长度限制 20 字符

### 2.2 标签展示（消费记录列表）

记录卡片下方展示标签 chip（现有 CSS `.record-tags` / `.tag` 已支持，激活即可），无需新增样式。

### 2.3 按标签筛选（消费记录 Tab）

在现有两个筛选框（分类、周期）后面增加第三个标签筛选下拉：

```
[全部分类 ▼] [全部周期 ▼] [全部标签 ▼]    N 条
```

- 选中某个标签后，列表只显示包含该标签的记录
- 三个筛选条件取**交集**（AND 逻辑）
- "全部标签"为默认状态（不过滤）

---

## 三、位置标签详细设计

### 3.1 触发流程

```
用户点击 📍
    ↓
toast: "正在获取位置…"
    ↓
navigator.geolocation.getCurrentPosition()
    ↓ 成功
调用反向地理编码 API
    ↓ 成功
格式化为 "📍 城市/地区" 字符串
自动添加为标签（若已存在同名标签则忽略）
    ↓ 任一步骤失败
toast: "获取位置失败：[原因]"
```

### 3.2 权限告知

在记录表单中，📍 按钮旁展示一行小字提示：

> "点击 📍 将请求定位权限，仅用于标记消费地点，不上传任何数据"

此提示只在 `navigator.geolocation` 可用时显示（桌面端 / HTTPS / Android WebView 均支持）。

### 3.3 反向地理编码服务

使用 **BigDataCloud Reverse Geocoding API**：

```
GET https://api.bigdatacloud.net/data/reverse-geocode-client
    ?latitude={lat}
    &longitude={lng}
    &localityLanguage=zh
```

- **免费**，无需 API Key，每月 50,000 次请求
- 支持中文地名返回（`localityLanguage=zh`）
- 纯客户端调用，数据不经过任何自建服务器

**响应字段优先级**（就近到精确）：

```js
const tag = res.locality       // 区/街道，如"朝阳区"
           || res.city         // 城市，如"北京市"
           || res.principalSubdivision  // 省，如"北京"
           || '未知位置';
return '📍 ' + tag;
```

### 3.4 超时与降级

- fetch 请求设置 5 秒超时（`AbortController`）
- 超时或网络失败时 toast 提示，并将原始经纬度以 `📍 {lat},{lng}` 格式作为兜底标签

### 3.5 Android 定位权限

需在 `patch-android.sh` 中补充以下两条权限（加在现有 INTERNET 权限之后）：

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

---

## 四、数据模型

### 4.1 交易记录 `txns`（无变化）

`t.tags` 字段已存在，格式为字符串数组：

```js
{
  id, cid, amt, note,
  tags: ["演唱会", "📍 朝阳区"],   // 现有字段，本次激活
  y, m, ts
}
```

### 4.2 标签库 `S.tagLib`（新增字段）

在状态对象 `S` 中新增 `tagLib`，存储用户预定义的快捷标签：

```js
S.tagLib = ["演唱会", "音乐会", "旅行", "工作报销", "聚餐", "出差"]
```

- **类型**：`string[]`，纯字符串，顺序即展示顺序
- **默认值**：内置一组通用初始标签（见下方）
- **用户可管理**：在「我的」Tab 新增标签库管理入口（增/删/排序）
- 位置标签（`📍 ...`）**不**存入 `tagLib`，每次动态生成

**默认初始标签**（新用户首次打开时）：

```js
["演唱会", "音乐会", "展览", "旅行", "出差", "聚餐", "工作报销", "家庭支出"]
```

### 4.3 快捷标签栏的展示逻辑

```
tagLib 不为空  →  显示 tagLib 中的标签（全部展示，横向滚动）
tagLib 为空    →  fallback：显示历史高频标签（取出现次数最多的前 6 个）
两者都为空     →  隐藏整行
```

```js
function quickTags() {
  if (S.tagLib?.length) return S.tagLib;
  // fallback：频率统计
  const freq = {};
  S.txns.forEach(t => t.tags?.forEach(tag => {
    if (!tag.startsWith('📍')) freq[tag] = (freq[tag] || 0) + 1;
  }));
  return Object.entries(freq).sort((a,b) => b[1]-a[1]).slice(0,6).map(e=>e[0]);
}
```

---

## 五、UI 变更详情

### 5.1 记录表单（月度预算 Tab）

**HTML 新增**（在 `exp-note` 行之后，`记录` 按钮保持原位）：

```
[备注 ___________________] [记录]
───────────────────────────────────
标签区域：
  [已选chip × ] [已选chip ×] [输入框] [📍]
  <小字提示：点击📍将请求定位权限，仅用于标记消费地点>
  常用标签：[chip] [chip] [chip] ...
```

**交互细节**：
- 标签输入框 `placeholder="添加标签（回车确认）"`
- 输入框监听 `keydown` 事件，`Enter` 或 `,` 键确认
- 提交记录后清空所有已选标签（同备注清空）
- 常用标签区域在无历史数据时不展示（空则隐藏整行）

### 5.2 消费记录 Tab

新增标签筛选下拉（与分类、周期同行）：

```html
<select id="rec-filter-tag" onchange="renderRecords()">
  <option value="">全部标签</option>
  <!-- 动态填充所有已用标签，按字母/拼音排序 -->
</select>
```

**`renderTagFilter()`** 函数（新增）：从所有交易 tags 中提取去重列表，填充下拉。

### 5.3「我的」Tab — 标签库管理

在"管理分类"入口下方新增"管理标签库"入口，展开后：

```
┌──────────────────────────────────────────┐
│ 快捷标签库          直接修改即可，实时保存   │
│                                          │
│  [演唱会 ×] [音乐会 ×] [旅行 ×]           │
│  [工作报销 ×] [聚餐 ×] [出差 ×]           │
│                                          │
│  [+ 新增标签  ____________  添加]         │
└──────────────────────────────────────────┘
```

- 每个标签右侧有 × 删除按钮（删除仅从库中移除，不影响历史记录）
- 输入框 + "添加"按钮新增标签，重复时 toast 提示
- 标签库变更实时保存到 `S.tagLib`

### 5.4 记录列表标签高亮

当按标签筛选时，分组标题不变（仍按周期分组），但记录卡片内标签 chip 高亮匹配的标签（匹配标签的 chip 加深背景色）。

---

## 六、核心逻辑变更

### 6.1 新增函数

| 函数 | 说明 |
|------|------|
| `quickTags()` | 返回快捷标签：优先 `S.tagLib`，空则取历史高频 |
| `renderTagInput()` | 渲染标签输入区域（已选 chips + 输入框 + 快捷 chips） |
| `addTagChip(tag)` | 添加一个标签到当前待提交列表 |
| `removeTagChip(tag)` | 移除一个已选标签 |
| `getLocation()` | 触发定位 → 反向地理编码 → 添加位置标签 |
| `renderTagFilter()` | 渲染记录页的标签筛选下拉 |
| `renderTagLib()` | 渲染「我的」Tab 中的标签库管理面板 |
| `addTagToLib(name)` | 向 `S.tagLib` 新增标签，重复时提示 |
| `removeTagFromLib(name)` | 从 `S.tagLib` 删除标签 |

### 6.2 修改 `addExp()`

```js
// 旧
S.txns.push({id:S.nid++, cid, amt, note, tags:[], y:cy, m:cm, ts:Date.now()});

// 新
const tags = [...pendingTags];   // pendingTags 为模块级临时数组
S.txns.push({id:S.nid++, cid, amt, note, tags, y:cy, m:cm, ts:Date.now()});
pendingTags.length = 0;          // 提交后清空
renderTagInput();                // 刷新标签区域
```

### 6.3 修改 `renderRecords()` 过滤逻辑

```js
const filterTag = document.getElementById('rec-filter-tag')?.value || '';
// ...
if (filterTag) txns = txns.filter(t => t.tags?.includes(filterTag));
```

### 6.4 修改 `renderRecords()` 标签高亮

```js
const tagsHtml = t.tags?.length
  ? `<div class="record-tags">${
      t.tags.map(tag => {
        const active = filterTag && tag === filterTag;
        return `<span class="tag${active ? ' tag-active' : ''}">${tag}</span>`;
      }).join('')
    }</div>`
  : '';
```

新增 CSS：
```css
.tag-active { background: var(--purple-light); color: var(--purple); border-color: var(--purple); }
```

---

## 七、`patch-android.sh` 变更

在现有权限注入逻辑中，补充定位权限的检测和注入：

```bash
# 添加定位权限
if ! grep -q "ACCESS_FINE_LOCATION" "$MANIFEST"; then
  sed -i 's|<uses-permission android:name="android.permission.INTERNET" />|...\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />|' "$MANIFEST"
  echo "[1/2] Location permissions added"
fi
```

---

## 八、向后兼容性

| 场景 | 处理 |
|------|------|
| 旧交易 `tags` 为空数组 `[]` | 正常显示（不展示标签区域），不受影响 |
| 旧交易无 `tags` 字段（极少数） | 所有用到 `t.tags` 的地方加 `?.` 可选链保护 |
| 旧数据无 `S.tagLib` 字段 | `load()` 后检查，若不存在则写入默认 8 个初始标签 |
| 标签筛选选择一个旧记录没有的标签 | 正常返回 0 条，显示"暂无记录" |

---

## 九、不在本期范围内

- 标签管理 UI（重命名、合并、删除）→ 可在 v1.6 考虑
- 多标签 AND/OR 组合筛选 → 当前单选已满足基本需求
- 基于标签的统计图表 → 独立功能
- 位置历史记录 / 地图展示 → 需要地图 SDK，复杂度高
- 离线反向地理编码 → 需要本地数据库，体积大

---

## 十、实现步骤建议

1. **Step 1**：`S` 默认值加 `tagLib`（内置 8 个初始标签）；`load()` 后检查兼容旧数据；新增 `quickTags()`
2. **Step 2**：新增 `pendingTags` 模块级数组 + `addTagChip()` / `removeTagChip()` / `renderTagInput()`
3. **Step 3**：在记录表单 HTML 插入标签区域（已选 chips + 输入框 + 📍 按钮 + 快捷标签行 + 定位提示）
4. **Step 4**：修改 `addExp()` 提交时带上 `pendingTags` 并清空
5. **Step 5**：新增 `getLocation()` 函数（定位 → BigDataCloud → addTagChip）
6. **Step 6**：新增 CSS `.tag-active`；在 `renderRecords()` 中加标签高亮逻辑
7. **Step 7**：在记录筛选区 HTML 添加标签下拉，新增 `renderTagFilter()`，修改 `renderRecords()` 过滤逻辑
8. **Step 8**：在「我的」Tab 新增标签库管理入口 HTML + `renderTagLib()` / `addTagToLib()` / `removeTagFromLib()`
9. **Step 9**：修改 `patch-android.sh` 添加定位权限
10. **Step 10**：`package.json` 版本升至 1.5.0
