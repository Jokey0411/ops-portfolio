# SQL 优化记录

> 简历对应：「通过减少回表，合理设计复合索引，控制索引数量来优化结构，提升查询效率」
>
> **这张表里的数字必须是你自己机器上跑出来的**，用 `bash scripts/bench.sh before` / `after` 采集。
> 面试官追问"提升了多少、为什么"时，你能答得出来才有价值。

---

## 一、优化前后对比表（跑完 bench.sh 后填写）

### 环境
| 项目 | 值 |
|---|---|
| 机器 | 2核2G 轻量服务器 |
| MySQL 版本 | 8.0（官方 `mysql:8.0` 镜像） |
| orders 表行数 | 300 000 |
| users 表行数 | 5 005 |
| innodb_buffer_pool_size | 256M |

> ⚠️ **本节所有耗时都是 MySQL 服务端耗时**（`EXPLAIN ANALYZE` 的 `actual time`），
> 不是 `docker exec` 墙钟时间。原因见下方「测量方法的坑」——
> 两者差了整整一个数量级，用错了会把结论完全带偏。

### Q1：用户订单分页
```sql
SELECT id,user_id,amount,status,created_at FROM orders
WHERE user_id=100 AND status='paid' ORDER BY created_at DESC LIMIT 20;
```

| 指标 | 优化前 | 优化后 |
|---|---|---|
| type | `ALL` | `ref` |
| rows（预估扫描行数） | 约 300 000 | 数十（该用户的 paid 订单，`LIMIT 20` 提前终止） |
| Extra | `Using where; Using filesort` | `Using index condition` |
| **服务端耗时** | **133 ms** | **0.11 ms** |
| 表面耗时（`docker exec` 计时） | 164 ms | 69 ms |
| **提升** | — | **约 1200 倍** |

**加的索引**：`CREATE INDEX idx_orders_user_status_created ON orders (user_id, status, created_at);`

**为什么提升这么夸张（1200 倍不是笔误）**：
优化前要**全表扫 30 万行**才能筛出 20 条；优化后索引直接定位到
`(user_id=100, status='paid')` 这个区间，按 `created_at` 倒序读 **20 行就停**。
这是「扫描量从 30 万降到 20」的**量级差异**，不是调参技巧——也正因为有 `LIMIT 20`，
差异才会这么极端。没有 `LIMIT` 的话索引收益会小得多。

### Q2：分组统计
```sql
SELECT user_id, SUM(amount) FROM orders WHERE status='done' GROUP BY user_id;
```

| 指标 | 优化前 | 优化后 |
|---|---|---|
| type | `ALL` | `ref` |
| rows | 约 300 000 | 约 60 000（`status='done'` 的行） |
| Extra | `Using where; Using temporary; Using filesort` | **`Using index`**（覆盖索引，无回表） |
| **服务端耗时** | **145 ms** | **65.8 ms** |
| 表面耗时 | 183 ms | 90 ms |
| **提升** | — | **2.2 倍** |

**加的索引**：`CREATE INDEX idx_orders_status_user_amount ON orders (status, user_id, amount);`

**为什么只有 2.2 倍，而不是像 Q1 那样几十倍**：
这条查询要扫的行太多。`status='done'` 占了约 1/5 的数据，覆盖索引只是把
「扫 30 万行整行」变成「扫 6 万行索引条目」，**扫描量减了 5 倍，耗时只减 2.2 倍**——
因为 B+ 树叶子节点遍历本身也有成本，不是线性的。

> 这也说明一件事：**索引能减少的是「回表」和「无效行的扫描」，减少不了「必须扫的行数」。**
> 聚合类查询如果命中比例高，索引的天花板很明显，真正的解法是预聚合或汇总表。

### Q3：范围 + 排序（索引不是万能的）
```sql
SELECT id,city,amount,created_at FROM orders
WHERE city='Nanjing' AND created_at >= '2025-06-01' ORDER BY amount DESC LIMIT 20;
```

| 指标 | 优化前 | 优化后 |
|---|---|---|
| type | `ALL` | `range` |
| rows | 约 300 000 | 约 6 万（`city='Nanjing'` 且满足时间范围） |
| Extra | `Using where; Using filesort` | `Using index condition;` **仍有 `Using filesort`** |
| **服务端耗时** | **125 ms** | **101 ms** |
| 表面耗时 | 161 ms | 145 ms |
| **提升** | — | **仅 1.24 倍（几乎无效）** |

**加的索引**：`CREATE INDEX idx_orders_city_created ON orders (city, created_at);`

**为什么排序还是走 filesort？**（这个问题答对很加分）
> 范围条件（created_at >=）之后的列在 B+ 树里已经无序了，
> 索引 (city, created_at) 只能保证 city 有序、city 相同时 created_at 有序，
> 但**无法保证 amount 有序**，所以 ORDER BY amount 必须额外排序。
> 我的取舍是：先靠索引把扫描行数从 30 万降到几万，
> 剩下的 filesort 在内存里完成，代价可接受。
> 硬要消除 filesort 得建 (city, amount) 索引，但那样过滤性变差，得不偿失。

**还能再优化吗——可以，但收益有限**：
把索引改成 `(city, created_at, amount)`，让 `amount` 进入索引形成**覆盖索引**，
可以消掉「回表取 amount」这一步。但**排序本身仍然要去掉不了**（created_at 是范围列，
其后无序），所以预期只能从 101 ms 降到 70-80 ms。
这条查询是**"索引无法彻底解决"的典型案例**——真正的解法是改查询语义
（换成 `ORDER BY created_at`、或加缓存、或做读模型），而不是继续堆索引。

### Q4：JOIN 查询
```sql
SELECT o.id,u.username,o.amount FROM orders o JOIN users u ON o.user_id=u.id
WHERE o.status='paid' AND u.city='Nanjing' LIMIT 20;
```

| 指标 | 优化前 | 优化后 |
|---|---|---|
| 驱动表 `u` 的 type | `ALL`（5 005 行全扫） | `ref`（`idx_users_city`，rows=640） |
| 被驱动表 `o` 的 type | `ALL` | `ref`（`idx_orders_status_user_amount`，rows=11） |
| `o` 的 Extra | `Using where` | **`Using index`**（覆盖索引，无回表） |
| **服务端耗时** | **0.677 ms** | **0.138 ms** |
| 表面耗时 | 66 ms | 67 ms |
| **结论** | — | **这条根本不需要优化** |

**关键点 1：这条查询从来就不慢。**
服务端耗时 **0.677 毫秒**，加了索引也只是 0.138 毫秒——**两个都是微秒级，差异没有意义**。

原因是 `LIMIT 20` 加驱动表只有 5 005 行：优化器选定 `u.city='Nanjing'` 的 640 行后，
逐行去 `orders` 里找匹配，**凑够 20 条就停**，压根不需要扫完 30 万行。

**关键点 2：`docker exec` 计时把它彻底骗了。**
表面值 66 ms → 67 ms，看起来「优化完全无效」。实际上这 66 ms 里，
真实查询只占 0.677 ms，**剩下 65 ms 全是 `docker exec` 启动进程的开销**。
换句话说：**测到的不是查询速度，是容器启动速度。**

> 这个案例的价值不在「优化成功」，而在「**判断出它不需要优化**」。
> 拿着 66ms 的表面数据去堆索引，是最典型的「用错误的度量做正确的努力」。

**关键点 3：`orders.user_id` 为什么不单独建索引。**
`idx_orders_user_status_created(user_id, status, created_at)` 的**最左前缀**已经覆盖 `user_id`，
再单独建 `(user_id)` 就是冗余索引——这就是简历上说的**控制索引数量**：
不建冗余索引，避免写放大和优化器选错。

---

## 一之二、测量方法的坑（★ 这一节的含金量比优化本身还高）

### 现象：同一组查询，两套数字差一个数量级

| 查询 | `docker exec` 墙钟 | `EXPLAIN ANALYZE` 服务端 | 差距 |
|---|---|---|---|
| Q1 优化前 | 164 ms | 133 ms | 31 ms |
| Q1 优化后 | 69 ms | **0.11 ms** | **69 ms（几乎全是开销）** |
| Q2 优化后 | 90 ms | 65.8 ms | 24 ms |
| Q3 优化后 | 145 ms | 101 ms | 44 ms |
| Q4 优化前 | 66 ms | **0.677 ms** | **65 ms（几乎全是开销）** |
| Q4 优化后 | 67 ms | **0.138 ms** | **67 ms（几乎全是开销）** |

**Q4 两轮都是 66-67 ms，看起来「加索引毫无效果」。真相是：这条查询本来只用 0.1 毫秒。**

### 为什么

初版 `bench.sh` 是这么计时的：

```bash
S=$(date +%s%3N)
docker exec -e MYSQL_PWD=... lnmp-mysql mysql -uroot -N -B -e "$SQL"
E=$(date +%s%3N)
```

每一次测量都要**启动一整套进程链**：

```
docker exec  →  runc 进入容器命名空间  →  启动 mysql 客户端
             →  建立 TCP 连接 + 认证  →  发送 SQL  →  取回结果  →  退出
```

**在 2 核机器上这一套要 30-70 ms**，而真实的索引查询可能只要 0.1 ms。
于是：

```
测到的耗时 = 固定开销（30-70ms）  +  真实查询耗时（0.1~133ms）
                ↑
        这一项占了绝大部分，而且完全不反映数据库性能
```

**当查询本身快到开销量级以下时，这个指标就彻底失效了**——你测的是进程启动速度，不是 SQL 速度。

### 后果：结论会被完全带偏

如果用表面数字，会得出三个**全错**的结论：

| 表面数据 | 错误结论 | 实际 |
|---|---|---|
| Q1：164 → 69，"提升 2.4 倍" | 索引效果一般 | 133 → 0.11，**1200 倍** |
| Q4：66 → 67，"优化无效" | 索引没用 | 0.677 → 0.138，**本来就快，无需优化** |
| Q2：183 → 90，"提升 2 倍" | 覆盖索引收益有限 | 145 → 65.8，确实只有 2.2 倍（这个碰巧对） |

**最危险的是 Q4**：它会让一个已经很快的查询看起来"优化失败"，
于是你去堆更多索引、改 SQL、甚至怀疑表结构——**全都是白费功夫**。

### 正确做法

**以服务端耗时为准**，三种测法从好到差：

```sql
-- ① 最优：EXPLAIN ANALYZE（MySQL 8.0.18+），服务端计时，含各节点耗时
EXPLAIN ANALYZE SELECT ...;
-- 看最外层节点的 actual time=开始..结束，第二个数就是总耗时

-- ② 次优：performance_schema 直接读
SELECT TIMER_WAIT/1e9 AS ms FROM performance_schema.events_statements_history
ORDER BY TIMER_START DESC LIMIT 1;

-- ③ 可用：一次连接内跑 N 次，摊薄启动开销
--   总耗时 / N 之后，固定开销被稀释
```

**`docker exec` + `date` 的测法只适合粗筛**（比如判断一条 SQL 是 10ms 还是 10s），
**不适合做优化前后的精确对比**，更不适合写进简历。

### 怎么一眼识破

**如果你测出来所有查询的耗时都收敛到同一个数值（比如都是 60-70ms），那多半是在测开销，不是在测查询。**

这是最实用的判据：**多个无关查询耗时高度一致 = 瓶颈在测量工具，不在被测对象。**

---

## 二、核心原理（面试要能讲清楚）

### 1. 什么是回表？怎么减少？

```
二级索引 B+ 树的叶子节点存的是「索引列 + 主键值」，不是整行数据。
用二级索引定位到主键后，还要再回主键（聚集索引）树查一次，把完整行取出来 —— 这叫回表。
回表是随机 IO，是慢查询的主要来源之一。
```

**减少回表的办法：覆盖索引**
```sql
-- 需要 user_id 和 amount，索引里正好都有 → Extra 出现 Using index，不回表
CREATE INDEX idx_orders_status_user_amount ON orders (status, user_id, amount);
SELECT user_id, SUM(amount) FROM orders WHERE status='done' GROUP BY user_id;  -- 覆盖

-- 但 SELECT * 一定回表（除非所有列都在索引里，不现实）
SELECT * FROM orders WHERE status='done';  -- 必然回表
```
> **生产经验**：`SELECT *` 是回表的最大帮凶。我在优化时把业务里几处 `SELECT *`
> 改成只查需要的列，配合覆盖索引，直接消灭了回表。

### 2. 复合索引的列顺序怎么定？

口诀：**等值 → 排序/分组 → 范围**

```sql
WHERE user_id=? AND status=? ORDER BY created_at DESC
→ (user_id, status, created_at)   ✅ 过滤和排序都能用上

-- 反例：把范围列放中间
WHERE city=? AND created_at>? AND amount=?
→ (city, created_at, amount)：amount 用不上索引（范围后失效）
```

**区分度原则**：区分度高的列尽量靠前。
```sql
-- 计算区分度：越接近 1 越适合建索引、越适合放前面
SELECT COUNT(DISTINCT user_id)/COUNT(*) AS user_id_selectivity,
       COUNT(DISTINCT status)/COUNT(*)  AS status_selectivity
FROM orders;
```
> 注意：区分度不是唯一标准，还要看查询频率和最左前缀约束。
> 比如 status 区分度只有 0.2，但它在 WHERE 里是等值条件，放在复合索引第二位仍然有效。

### 3. 索引数量为什么要控制？

| 代价 | 说明 |
|---|---|
| 写放大 | 每个二级索引都是一棵 B+ 树，一次 INSERT 要写 N+1 棵树 |
| 占用空间 | 索引本身也占磁盘和宝贵的 buffer pool |
| 优化器选错 | 索引多了，优化器基于统计信息可能选次优索引 |
| 维护成本 | 表结构变更、重建索引的时间变长 |

**我的做法**：
1. 单表索引控制在 5~6 个以内
2. 优先建复合索引，而不是多个单列索引
3. 定期检查冗余索引
```sql
SELECT * FROM sys.schema_redundant_indexes WHERE table_schema='shop';
-- performance_schema=OFF 时该视图不可用，改用手工核对：
SHOW INDEX FROM orders;
```
> 冗余的判断标准：已有 (a, b, c)，再建 (a) 或 (a, b) 就是冗余——
> 因为最左前缀原则下它们能被 (a,b,c) 完全覆盖。

### 4. 慢查询分析的标准流程

```bash
# ① 确认慢日志开启
docker exec lnmp-mysql mysql -uroot -pRoot@123456 -e \
  "SHOW VARIABLES LIKE 'slow_query%'; SHOW VARIABLES LIKE 'long_query_time';"

# ② 汇总慢日志，按总耗时排序取 Top5
docker exec lnmp-mysql sh -c 'mysqldumpslow -s t -t 5 /var/log/mysql/slow.log'

# 更专业的工具：pt-query-digest（Percona Toolkit）
# docker exec lnmp-mysql sh -c 'pt-query-digest /var/log/mysql/slow.log | head -50'

# ③ 拿到 SQL 后 EXPLAIN 看执行计划
docker exec lnmp-mysql mysql -uroot -pRoot@123456 -e "EXPLAIN <SQL>"

# ④ MySQL 8.0.18+ 用 EXPLAIN ANALYZE 看真实耗时（比 EXPLAIN 的估算准）
docker exec lnmp-mysql mysql -uroot -pRoot@123456 -e "EXPLAIN ANALYZE <SQL>"
```

**EXPLAIN 各字段要看什么**
| 字段 | 关注点 |
|---|---|
| type | 性能从好到差：system > const > eq_ref > ref > range > index > **ALL**（见到 ALL 就要优化） |
| key | 实际用到的索引，NULL 说明没用上 |
| rows | 预估扫描行数，越小越好 |
| Extra | `Using filesort`（额外排序）、`Using temporary`（临时表）都要警惕；`Using index` 是好事（覆盖索引） |

---

## 三、面试话术（30 秒版本）

> "我在 LNMP 项目里对订单表做过一次索引优化。表里有 30 万行数据，
> 慢查询日志里最高频的是按用户查订单分页的语句，EXPLAIN 出来 type=ALL，
> 扫描 30 万行还要 filesort。
>
> 我按'等值→排序→范围'的顺序建了复合索引 (user_id, status, created_at)，
> 服务端耗时从 **133 毫秒降到 0.11 毫秒**——因为原来是全表扫 30 万行，
> 现在索引直接定位到目标区间，读 20 行就停。
>
> 另一个分组统计的查询，我把索引建成 (status, user_id, amount)，
> 让查询需要的列都在索引里，Extra 出现 Using index，直接消除了回表。
> 但这条只提升了 2.2 倍（145ms → 66ms），因为它要扫的行太多（约 6 万行），
> **索引能减少回表和无效行扫描，减少不了必须扫的行数**。
>
> 索引数量上我做了控制：orders.user_id 没有单独建索引，
> 因为复合索引的最左前缀已经能覆盖它，再建就是冗余索引，会白白增加写成本。
>
> 另外有个反例我印象很深：city + created_at 范围 + ORDER BY amount 的查询，
> 加索引后排序还是 filesort，因为范围条件之后的列在 B+ 树里已经无序了。
> 这条只提升到 1.24 倍，最后我的结论是**索引解决不了它**，得改查询语义或加缓存。
>
> 还有个 JOIN 查询，我一开始以为加索引能优化，测出来发现服务端只要 0.68 毫秒——
> 因为驱动表只有 5000 行、还带 LIMIT 20 提前终止，它本来就不慢。
> **判断出'这条不需要优化'，比强行优化它更有价值。**"

**这段话里有五个加分点**：
1. 真实数据量（30 万行）和真实指标（type、Extra、毫秒数）
2. 复合索引列顺序的原则（等值→排序→范围）
3. **知道索引的边界**——聚合类查询和范围+排序查询的收益天花板
4. **知道什么时候不该优化**（Q4 那条本来就 0.68ms）
5. **能说出「减少回表 vs 减少扫描行数」的区别**——这是初级和中级的分界线

### 如果被追问「你怎么测的耗时」

**这是最容易露馅的地方，一定要答对**：

> "**以 MySQL 服务端耗时为准**，用 `EXPLAIN ANALYZE` 的 `actual time`。
>
> 我一开始用的是 `docker exec` 外面包一层 `date` 前后相减，结果发现所有查询都稳定在 60-70 毫秒，
> 连一条只查 20 行的 JOIN 也是 66 毫秒——**多个无关查询耗时高度一致，说明瓶颈在测量工具本身**。
> 后来对比服务端数据，那条 JOIN 实际只用了 0.68 毫秒，**65 毫秒全是 `docker exec` 启动进程的开销**。
>
> 改成服务端计时之后，同一条分页查询的优化效果从'看起来提升 2.4 倍'变成'实际提升 1200 倍'。
> **如果我拿最初那组数字去写结论，会得出'JOIN 加索引无效'的错误判断。**"

**这段回答的价值**：它证明你不只是会跑 SQL，还知道**测量本身会撒谎**。
绝大多数候选人答不出这一层。
