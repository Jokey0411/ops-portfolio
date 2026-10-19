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
| MySQL 版本 | （`SELECT VERSION()` 的结果） |
| orders 表行数 | 约 30 万 |
| innodb_buffer_pool_size | 256M |

### Q1：用户订单分页
```sql
SELECT id,user_id,amount,status,created_at FROM orders
WHERE user_id=100 AND status='paid' ORDER BY created_at DESC LIMIT 20;
```

| 指标 | 优化前 | 优化后 |
|---|---|---|
| type | ALL | ref/range |
| rows（扫描行数） | | |
| Extra | Using where; Using filesort | Using index condition / Using where |
| 执行耗时(ms) | | |
| **提升** | — | **约 X 倍** |

**加的索引**：`CREATE INDEX idx_orders_user_status_created ON orders (user_id, status, created_at);`

### Q2：分组统计
```sql
SELECT user_id, SUM(amount) FROM orders WHERE status='done' GROUP BY user_id;
```

| 指标 | 优化前 | 优化后 |
|---|---|---|
| type | ALL | ref |
| rows | | |
| Extra | Using where; Using temporary; Using filesort | **Using index**（覆盖索引，无回表） |
| 执行耗时(ms) | | |
| **提升** | — | **约 X 倍** |

**加的索引**：`CREATE INDEX idx_orders_status_user_amount ON orders (status, user_id, amount);`

### Q3：范围 + 排序（索引不是万能的）
```sql
SELECT id,city,amount,created_at FROM orders
WHERE city='Nanjing' AND created_at >= '2025-06-01' ORDER BY amount DESC LIMIT 20;
```

| 指标 | 优化前 | 优化后 |
|---|---|---|
| type | ALL | range |
| rows | | |
| Extra | Using where; Using filesort | Using index condition; **仍有 Using filesort** |
| 执行耗时(ms) | | |

**加的索引**：`CREATE INDEX idx_orders_city_created ON orders (city, created_at);`

**为什么排序还是走 filesort？**（这个问题答对很加分）
> 范围条件（created_at >=）之后的列在 B+ 树里已经无序了，
> 索引 (city, created_at) 只能保证 city 有序、city 相同时 created_at 有序，
> 但**无法保证 amount 有序**，所以 ORDER BY amount 必须额外排序。
> 我的取舍是：先靠索引把扫描行数从 30 万降到几千，
> 剩几千行的 filesort 在内存里就能完成，代价可接受。
> 硬要消除 filesort 得建 (city, amount) 索引，但那样过滤性变差，得不偿失。

### Q4：JOIN 查询
```sql
SELECT o.id,u.username,o.amount FROM orders o JOIN users u ON o.user_id=u.id
WHERE o.status='paid' AND u.city='Nanjing' LIMIT 20;
```

| 指标 | 优化前 | 优化后 |
|---|---|---|
| orders 的 type | ALL | ref |
| rows | | |
| Extra | Using where; Using join buffer (Block Nested Loop) | Using where |
| 执行耗时(ms) | | |

**关键点**：JOIN 优化的核心是**被驱动表的关联字段必须有索引**。
这里 `orders.user_id` 之所以没单独建索引，是因为
`idx_orders_user_status_created(user_id, status, created_at)` 的**最左前缀**已经覆盖 user_id 了
——这就是简历上说的**控制索引数量**：不建冗余索引。

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
> 扫描行数降到几十行，耗时从 X 毫秒降到 Y 毫秒。
>
> 另一个分组统计的查询，我把索引建成 (status, user_id, amount)，
> 让查询需要的列都在索引里，Extra 出现 Using index，直接消除了回表。
>
> 索引数量上我做了控制：orders.user_id 没有单独建索引，
> 因为复合索引的最左前缀已经能覆盖它，再建就是冗余索引，会白白增加写成本。
>
> 另外有个反例我印象很深：city + created_at 范围 + ORDER BY amount 的查询，
> 加索引后排序还是 filesort，因为范围条件之后的列在 B+ 树里已经无序了。
> 我的取舍是先靠索引把扫描量降下来，剩下的 filesort 数据量很小，可以接受。"

**这段话里有四个加分点**：真实数据量、EXPLAIN 指标、复合索引顺序原则、以及知道索引的边界。
