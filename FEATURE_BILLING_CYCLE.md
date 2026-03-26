# 功能需求：自定义账单结算日 / 记账周期

**版本**：v1.4.0  
**状态**：待开发  
**关联文件**：`www/index.html`

---

## 一、背景与目标

当前 App 以**自然月**（每月 1 日起）作为固定统计周期，无法适应信用卡账单日、工资日等非 1 日结算场景。

本功能允许用户自定义**每月结算日**，App 的所有统计维度（预算进度、消费记录、周期导航）均随之切换到以该日期为起点的自定义周期。预算模式与记账模式的底层逻辑**完全相同**，仅在展示层面有差异（是否显示限额和进度条）。

---

## 二、核心概念

### 2.1 结算日（billingDay）

- 用户可设置 **1 ～ 28** 的整数（避开各月天数差异问题）
- 默认值：**1**（保持与现有行为完全兼容）
- 结算日 = 1 时，周期 = 自然月，行为与当前完全一致

### 2.2 周期（Cycle）定义

一个周期由**起始日**唯一确定，用 `{ cy, cm }` 表示（起始年、起始月，0 起始）。

| 结算日 | 周期示例 | cy / cm |
|--------|----------|---------|
| 1 | 3月1日 ～ 3月31日 | 2026 / 2 |
| 15 | 2月15日 ～ 3月14日 | 2026 / 1 |
| 25 | 2月25日 ～ 3月24日 | 2026 / 1 |

**周期起始时间戳**：`new Date(cy, cm, billingDay, 0, 0, 0)`  
**周期结束时间戳**（不含）：`new Date(cy, cm + 1, billingDay, 0, 0, 0)`

### 2.3 当前周期计算

```
今天日期 >= billingDay  →  当前周期起始 = 本月 billingDay
今天日期 <  billingDay  →  当前周期起始 = 上月 billingDay
```

---

## 三、数据模型变更

### 3.1 状态对象 `S` 新增字段

```js
S.billingDay = 1  // 新增，默认 1，范围 1-28
```

其余字段 `cats`、`txns`、`goals`、`budgetMode` **不变**。

### 3.2 全局变量语义变更

| 变量 | 旧语义 | 新语义 |
|------|--------|--------|
| `cy` | 当前查看的自然年 | 当前查看周期的**起始年** |
| `cm` | 当前查看的自然月（0起） | 当前查看周期的**起始月**（0起） |

当 `billingDay = 1` 时，两者语义完全相同，**向后兼容**。

### 3.3 交易记录 `txns` 字段

**不新增字段**，不修改存储结构。  
`t.y`、`t.m` 继续存储交易被记录时的 `cy`、`cm`（即周期起始年月），`t.ts` 始终是精确时间戳。

过滤逻辑改为**基于 `t.ts` 时间戳**判断是否属于当前周期，不再依赖 `t.y === cy && t.m === cm` 的字符串比较。这样历史数据的 `y/m` 无需迁移，`ts` 已经足够。

> **兼容性**：对于极少数无 `ts` 的旧记录，回退使用 `t.y === cy && t.m === cm` 判断。

---

## 四、核心逻辑变更（JS 函数）

### 4.1 新增：周期工具函数

```js
// 周期起始时间戳
function cycleStart(y, m) {
  return new Date(y, m, S.billingDay || 1).getTime();
}

// 周期结束时间戳（不含）
function cycleEnd(y, m) {
  return new Date(y, m + 1, S.billingDay || 1).getTime();
}

// 今天属于哪个周期 → 返回 { y, m }
function todayCycle() {
  const now = new Date();
  const bd = S.billingDay || 1;
  if (now.getDate() >= bd) {
    return { y: now.getFullYear(), m: now.getMonth() };
  } else {
    const prev = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    return { y: prev.getFullYear(), m: prev.getMonth() };
  }
}
```

### 4.2 修改：`mTxns()`

```js
// 旧
function mTxns() { return S.txns.filter(t => t.y === cy && t.m === cm); }

// 新
function mTxns() {
  const s = cycleStart(cy, cm);
  const e = cycleEnd(cy, cm);
  return S.txns.filter(t =>
    t.ts ? (t.ts >= s && t.ts < e) : (t.y === cy && t.m === cm)
  );
}
```

### 4.3 修改：`load()`

加载后自动判断是否需要跳转到当前周期：

```js
function load() {
  try {
    const d = localStorage.getItem(SK);
    if (d) {
      const p = JSON.parse(d);
      S = p.S;
      cy = p.cy;
      cm = p.cm;
    }
  } catch(e) {}
  // 自动推进到当前周期（如果存储的周期已过期）
  const tc = todayCycle();
  const storedTs = cycleStart(cy, cm);
  const todayTs  = cycleStart(tc.y, tc.m);
  if (todayTs > storedTs) { cy = tc.y; cm = tc.m; }
}
```

> **效果**：用户隔了一个账单周期再打开 App，会自动切换到新周期，不需要手动点导航箭头。

### 4.4 修改：`chMonth(d)`（无需改变，仅改 label）

月份导航逻辑（进位/借位）无需改变，`cm` 仍然做 0-11 环绕处理。  
变化仅在 `render()` 里更新 label 文字。

### 4.5 修改：`render()` 中的 `mlabel`

```js
// 旧
document.getElementById('mlabel').textContent = cy + '年 ' + MONTHS[cm];

// 新
function cycleLabel(y, m) {
  const bd = S.billingDay || 1;
  if (bd === 1) return y + '年 ' + MONTHS[m]; // 自然月，保持原样
  const start = new Date(y, m, bd);
  const end   = new Date(y, m + 1, bd - 1);
  const fmt   = d => (d.getMonth() + 1) + '/' + d.getDate();
  return fmt(start) + ' - ' + fmt(end);
}
document.getElementById('mlabel').textContent = cycleLabel(cy, cm);
```

示例输出：
- billingDay=1 → `2026年 三月`
- billingDay=15 → `2/15 - 3/14`
- billingDay=25 → `2/25 - 3/24`

### 4.6 修改：`renderRecordMonthFilter()`

消费记录的月份筛选下拉需展示周期 label，而不是自然月。

```js
function renderRecordMonthFilter() {
  const sel = document.getElementById('rec-filter-month');
  if (!sel) return;
  const cur = sel.value;
  // 从所有交易的 ts 推算其所在周期
  const cycleSet = new Set();
  S.txns.forEach(t => {
    if (t.ts) {
      const c = tsToCycle(t.ts);          // 新增工具函数，见下
      cycleSet.add(c.y + '-' + c.m);
    } else {
      cycleSet.add(t.y + '-' + t.m);
    }
  });
  const sorted = [...cycleSet].sort((a, b) => b.localeCompare(a));
  sel.innerHTML = '<option value="">全部周期</option>' + sorted.map(key => {
    const [y, m] = key.split('-').map(Number);
    return `<option value="${key}">${cycleLabel(y, m)}</option>`;
  }).join('');
  if (cur) sel.value = cur;
}

// 给定时间戳，计算其所在周期起始 {y, m}
function tsToCycle(ts) {
  const d   = new Date(ts);
  const bd  = S.billingDay || 1;
  if (d.getDate() >= bd) return { y: d.getFullYear(), m: d.getMonth() };
  const prev = new Date(d.getFullYear(), d.getMonth() - 1, 1);
  return { y: prev.getFullYear(), m: prev.getMonth() };
}
```

### 4.7 修改：`renderRecords()` 的筛选逻辑

记录列表按周期过滤时，`rec-filter-month` 的 value 仍是 `"y-m"` 格式，过滤时改用时间戳范围：

```js
// 旧的月份过滤
.filter(t => !mf || (t.y + '-' + t.m === mf))

// 新的周期过滤
.filter(t => {
  if (!mf) return true;
  const [fy, fm] = mf.split('-').map(Number);
  const s = cycleStart(fy, fm);
  const e = cycleEnd(fy, fm);
  return t.ts ? (t.ts >= s && t.ts < e) : (t.y === fy && t.m === fm);
})
```

---

## 五、UI 变更

### 5.1「我的」Tab — 新增结算日设置

在**预算模式切换**行之前插入：

```
┌─────────────────────────────────────┐
│  账单结算日                    [15] 日 │
│  每月 15 日自动开始新周期             │
└─────────────────────────────────────┘
```

- 使用 `<input type="number" min="1" max="28">` 内联输入
- 失焦或回车时保存，并**重新计算 cy/cm 到当前周期**后重渲染
- 提示文字随结算日动态更新（"每月 X 日自动开始新周期"）
- 修改后 toast 提示："结算日已设为每月 X 日"

### 5.2 顶部导航 label 变更

| 场景 | 显示效果 |
|------|----------|
| 结算日=1（默认）| `2026年 三月`（不变） |
| 结算日=15 | `2/15 - 3/14` |
| 结算日=25，跨年 | `12/25 - 1/24` |

### 5.3 月度预算 Tab

- "本月预算" → 结算日≠1 时改为 "本期预算"
- 其余卡片、进度条、超支逻辑**无需改变**，因为它们都依赖 `mTxns()` 的结果

### 5.4 消费记录 Tab

- 筛选下拉 "全部月份" → "全部周期"
- 选项 label 使用 `cycleLabel()` 的输出

---

## 六、向后兼容性 & 迁移

| 场景 | 处理方式 |
|------|----------|
| 首次加载旧数据（无 `S.billingDay`） | `S.billingDay` 默认为 `1`，行为与旧版完全一致 |
| 旧交易有 `t.ts` | `tsToCycle()` 直接从时间戳推算，无需修改记录 |
| 旧交易无 `t.ts`（极少数） | 回退到 `t.y === cy && t.m === cm` 比较 |
| 修改结算日后重新打开 | `load()` 中自动跳转到基于新结算日的当前周期 |
| 导出备份 | `S.billingDay` 随 `S` 对象一起导出，恢复后直接生效 |

**无需数据迁移脚本**，所有变更对现有数据透明。

---

## 七、边界情况处理

| 边界 | 处理 |
|------|------|
| 结算日设为 29/30/31 | 输入限制 max=28，超出时 toast 提示并拒绝保存 |
| 跨年周期（12月结算 → 1月结束） | `new Date(cy, cm+1, bd)` 原生处理月份进位，自动正确 |
| 结算日设为今天 | 立即切换到新周期（今天 >= billingDay） |
| 修改结算日后当前视图不在任何周期 | `load()` 末尾的自动推进逻辑保证跳到正确的当前周期 |

---

## 八、不在本期范围内的事项

- 不同周期设置不同的预算金额（每期预算统一沿用 `cats[].budget`）
- 跨周期消费趋势图表（属于独立功能）
- 推送通知提醒结算日到来（需要原生权限，Capacitor 插件支持）

---

## 九、改动文件清单

| 文件 | 改动类型 |
|------|----------|
| `www/index.html` | 主要改动（JS 逻辑 + HTML 片段 + 少量 CSS） |
| `www/sw.js` | 无需改动（CI 自动注入版本号） |
| `package.json` | 版本号从 1.3.0 → 1.4.0 |

---

## 十、实现步骤建议（开发顺序）

1. **Step 1**：在 `S` 默认值中加 `billingDay:1`，新增 `cycleStart()`、`cycleEnd()`、`todayCycle()`、`tsToCycle()`、`cycleLabel()` 五个工具函数
2. **Step 2**：修改 `mTxns()` 改用时间戳过滤
3. **Step 3**：修改 `load()` 加入自动推进逻辑
4. **Step 4**：修改 `render()` 中的 label 更新为 `cycleLabel()`
5. **Step 5**：修改 `renderRecordMonthFilter()` 和 `renderRecords()` 的过滤逻辑
6. **Step 6**：在「我的」Tab HTML 中插入结算日设置行，新增 `setBillingDay()` 函数
7. **Step 7**：在 `renderMine()` 中回填当前结算日到输入框
8. **Step 8**：本地测试各结算日场景（1、15、28），验证周期切换和历史数据展示
