# 04 · 负载均衡与 SQL 连接查询

> **定位**：简历一写就必问的两块——Nginx 负载均衡（Q1–Q9）与 MySQL JOIN 陷阱（Q1–Q10）+ 手写题。
> **用法**：LB 那部分要能**拿项目一现场演示**（`/whoami` 看轮询、`max_fails` 看摘除）。
> ★ = 高危题，索引见 `README.md`。

---

## 第一部分：负载均衡（Nginx）

### Q1 什么是负载均衡？解决什么问题？

> 「把流量按某种策略分发到多台后端，解决三件事：
> **扛量**（单机扛不住）、**高可用**（一台挂了还有别的）、**扩展性**（加机器就能扩容）。」

---

### Q2 ★★ 你怎么检查负载均衡是不是生效了？

> ★ 这题是「最像干活的人」和「背过」的分水岭。**五种方法按可信度从高到低说：**

**方法 1（最直接）**：连续发请求，看响应里有没有节点标识在轮换
```bash
# 项目一里有 /whoami 返回节点名，连续打几次看输出是否交替
for i in 1 2 3 4 5 6; do curl -s http://lb-ip/whoami; echo; done
# 预期输出：node1 / node2 / node1 / node2 ...（轮询时交替出现）
```
> 说这句就是 L3：「我的节点容器里跑了个 `/whoami` 接口返回 hostname，
> 连续 curl 六次看到 node1、node2 交替，就确认轮询生效了」

**方法 2（生产最常用）**：Nginx 日志里打 `$upstream_addr`，看请求落到哪台后端
```nginx
log_format main '$remote_addr $upstream_addr "$request" $status $upstream_response_time';
```
然后 `awk '{print $2}' access.log | sort | uniq -c` 统计各后端分到的请求数。

**方法 3**：看 LB 到各后端的连接分布
```bash
ss -tn state established | awk '{print $5}' | awk -F: '{print $1}' | sort | uniq -c
```

**方法 4**：两边后端各自打自己的 access log，对比请求数是否接近。

**方法 5（压测验证）**：`ab -n 1000 -c 50 http://lb/` 或 `wrk`，再看两个后端的请求数是不是一半一半（轮询时）。

| 追问 | 答点 |
|---|---|
| 你 curl 了六次全是 node1，说明什么？ | ① 后端挂了被摘除了；② 用了 `ip_hash`（同一源 IP 永远到同一台）；③ 后端权重或健康检查配置问题 |
| 线上能随便用方法 1 压测吗？ | 不能，低峰期做，或先摘一台做对比；生产主要看**日志统计**（方法 2） |

---

### Q3 ★ 负载均衡算法有哪些？区别和适用场景？

| 算法 | 怎么分 | 适用场景 | 坑 |
|---|---|---|---|
| **轮询（默认）** | 依次轮流 | 后端性能一致、请求耗时均匀 | 节点性能不均时弱者被打爆 |
| **weight 权重** | 按比例分 | 后端配置不一样 | 权重拍脑袋设，要结合压测 |
| **ip_hash** | 按客户端 IP 哈希，**固定落到一台** | 需要会话保持 | ★ 节点增减会导致大量会话漂移；公司出口 IP 集中时会严重不均 |
| **least_conn** | 分给当前**连接数最少**的 | 请求耗时差异大（有长有短）、长连接 | 短连接高并发下和轮询差别不大 |
| fair / url_hash | 第三方模块 | 按响应时间 / 按 URL 哈希 | 需要编译第三方模块 |

★ 追问「**什么时候用 least_conn**」：后端请求处理时间不均匀时（比如有的接口快有的慢），
轮询会把慢请求继续往已经压了一堆慢请求的节点上堆，least_conn 能避开。

---

### Q4 现场写：一个 upstream 配置

```nginx
upstream backend {
    least_conn;                              # 算法写在最上面
    server 10.0.0.1:80 weight=3;             # 性能好，多分担
    server 10.0.0.2:80;
    server 10.0.0.3:80 backup;               # 备用节点，前两个都挂了才上
    server 10.0.0.4:80 down;                 # 暂时下线（维护时用）
    keepalive 32;                            # 和后端保持长连接，减少建连开销
}

server {
    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;   # ★ 把真实客户端 IP 传给后端
        proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
    }
}
```

★ 追问「**不加 `X-Forwarded-For` 会怎样**」：后端日志里所有请求的源 IP 都是 LB 的 IP，
真实客户端 IP 丢了，做限流、审计、风控全瞎。

---

### Q5 ★ 健康检查怎么做？后端挂了 LB 怎么知道？

> 「开源版 Nginx 是**被动健康检查**：`max_fails=3 fail_timeout=30s`
> 表示 30 秒内失败 3 次就把这台摘除，30 秒后再试探。
> 摘掉的请求会自动转发给健康的节点（`proxy_next_upstream`）。
> **主动健康检查**（LB 主动去探测后端）开源版没有，要 Nginx Plus 或第三方模块 `nginx_upstream_check_module`。」

★ 追问「**为什么被动检查有问题**」：故障发生到被摘除之间，**真实用户的请求已经失败了**——
用户是探测的代价。主动检查能在用户请求打到坏节点前就摘掉。

---

### Q6 会话保持问题（用户登录态怎么跨节点）

| 方案 | 说明 | 评价 |
|---|---|---|
| **无状态（推荐）** | 用 JWT 或把 session 放 Redis，请求带 token 哪台都能处理 | ★ 生产标准做法 |
| `ip_hash` | 同一客户端 IP 固定到一台 | 下策：节点增减会话全漂移，IP 集中时不均衡 |
| 本地 session + 复制 | 各节点同步 session | 基本不用了 |

★ 追问「**为什么 ip_hash 是下策**」：绑死了「IP → 节点」，扩缩容、节点重启都会让一大批用户掉登录；
而且 NAT 下一个小区可能共用一个出口 IP，全部打到同一台。

---

### Q7 四层负载均衡和七层负载均衡的区别？

| | 四层（LVS / HAProxy tcp 模式） | 七层（Nginx） |
|---|---|---|
| 工作在哪层 | TCP/UDP（传输层） | HTTP/应用层 |
| 看什么分发 | IP + 端口 | URL、Header、Cookie 都能看 |
| 性能 | 极高（不解析内容） | 低一些（要解析 HTTP） |
| 典型用途 | ★ **流量入口第一层**，抗大流量 | 按路径路由、灰度、读写分离 |

★ 追问「**什么时候用四层**」：流量大到 Nginx 单机扛不住时，前面用 LVS 做四层分担到多台 Nginx。
经典架构：**LVS（四层）→ Nginx（七层）→ 应用**。

---

### Q8 ★ 你的架构里 LB 是单点，挂了怎么办？

> ★ 这题是「交底题」，主动说比被问出来好：
> 「我这套环境里 LB 确实是单点，这是这个模拟架构的边界，我很清楚。
> 生产环境的做法是 **Keepalived + VIP**：两台 Nginx 做主备，对外暴露一个虚拟 IP，
> 主挂了 VIP 漂移到备机，用户无感知。」

| 追问 | 答点 |
|---|---|
| Keepalived 原理？ | VRRP 协议，主备之间心跳；主挂了就由备把虚拟 IP 抢过来 |
| 云环境呢？ | 直接用云厂商的 LB（腾讯云的 CLB），人家把高可用做好了，自己不用搭 |

---

### Q9 负载均衡能 100% 均匀吗？为什么不均匀也没事？

> 不能也不需要。轮询只保证长期统计上大致平均，瞬时一定有偏斜。
> 关键是**每个节点留够余量**，不要因为 5% 的不均匀去折腾算法——先把单机性能和安全水位做对。

---

## 第二部分：MySQL 连接查询

### Q1 ★ INNER JOIN 和 LEFT JOIN 的区别（必考）

| | INNER JOIN | LEFT JOIN |
|---|---|---|
| 结果 | **两边都匹配才保留** | **左表全保留**，右表没匹配补 NULL |
| 结果行数 | ≤ 两边匹配的行 | ≥ 左表行数（一对多时会放大） |
| 典型用途 | 查「两边都有的」 | 查「左表全部 + 有就带上」 |

```sql
-- 只查有订单的用户
SELECT u.name, o.id FROM user u INNER JOIN orders o ON u.id = o.user_id;

-- 查所有用户，没下过订单的也列出来
SELECT u.name, o.id FROM user u LEFT JOIN orders o ON u.id = o.user_id;
```

★ 追问「LEFT JOIN 结果行数会比左表多吗」：会。一个用户有 3 个订单，LEFT JOIN 后这个用户出现 3 行。
**行数 = 左表行数 × 右表匹配数（≥1 的部分）**。所以「LEFT JOIN 结果一定等于左表行数」是错的。

---

### Q2 LEFT JOIN 和 RIGHT JOIN 的区别？

> 完全一样，只是**谁是「全保留」的那边**：
> `A LEFT JOIN B` 保留 A 全部；`A RIGHT JOIN B` 保留 B 全部。
> 两者可互换：`A LEFT JOIN B` ≡ `B RIGHT JOIN A`。
> ★ 习惯上**统一用 LEFT JOIN**，混着用可读性差。

---

### Q3 ★★ ON 里的条件和 WHERE 里的条件有什么区别？（最高频陷阱）

```sql
-- 写法 1：条件放 ON
SELECT u.name, o.id FROM user u LEFT JOIN orders o ON u.id = o.user_id AND o.status = 1;

-- 写法 2：条件放 WHERE
SELECT u.name, o.id FROM user u LEFT JOIN orders o ON u.id = o.user_id WHERE o.status = 1;
```

**这两个结果不一样：**
- 写法 1：条件只影响「匹配」，左表**全保留**，右表不满足 status=1 的补 NULL → 还是 LEFT JOIN
- 写法 2：先 JOIN 出结果，再用 WHERE 过滤掉 `o.status=1` 不满足的行——而右表补的 NULL 行 `status` 是 NULL，全被滤掉了 → **等价于 INNER JOIN**

★ 一句话：**LEFT JOIN 后接 WHERE 过滤右表字段，会把 LEFT JOIN 变成 INNER JOIN。**
要过滤右表，条件写进 `ON`。

---

### Q4 现场写：查出**没有下过订单**的用户

```sql
-- 写法 1（经典）：LEFT JOIN + 右表主键 IS NULL
SELECT u.*
FROM user u
LEFT JOIN orders o ON u.id = o.user_id
WHERE o.id IS NULL;

-- 写法 2：NOT EXISTS（性能更好，语义更清楚）
SELECT * FROM user u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 写法 3（有坑）：NOT IN
SELECT * FROM user WHERE id NOT IN (SELECT user_id FROM orders);
-- ★ 危险：如果 orders.user_id 里存在 NULL，整个结果集为空！因为 NOT IN 等价于 id<>每个值，
--   而 NULL 参与比较结果是 NULL（非真非假），导致所有行都被排除。面试提这句是明显加分。
```

---

### Q5 自连接是什么？举个例子

> 表和自己 JOIN。经典场景：查员工和他的上级（都存在一张 employee 表里）。

```sql
SELECT e.name AS 员工, m.name AS 上级
FROM employee e
LEFT JOIN manager_rel r ON e.id = r.emp_id
LEFT JOIN employee m ON r.mgr_id = m.id;
-- 或者用一张表两个别名
SELECT a.name, b.name
FROM employee a JOIN employee b ON a.dept_id = b.dept_id AND a.id <> b.id;
```
★ 关键：**同一张表必须起两个不同的别名**，否则 MySQL 分不清。

---

### Q6 MySQL 支持 FULL OUTER JOIN 吗？怎么模拟？

> **不支持**。用 `LEFT JOIN + RIGHT JOIN（或反向 LEFT JOIN）+ UNION` 模拟：

```sql
SELECT u.id, o.id FROM user u LEFT JOIN orders o ON u.id = o.user_id
UNION
SELECT u.id, o.id FROM user u RIGHT JOIN orders o ON u.id = o.user_id;
-- UNION 会去重，正好把两边重叠的 INNER 部分去掉一次
```

---

### Q7 CROSS JOIN 是什么？什么时候用？

> 笛卡尔积：左表每行 × 右表每行。10 行 × 10 行 = 100 行。
> 用途很少，典型是「生成组合」——比如颜色和尺码做 SKU 组合。
> ★ 反面教材：JOIN **忘了写 ON**，就可能退化成笛卡尔积，行数爆炸把库打爆。

---

### Q8 ★ JOIN 底层是怎么执行的？（区分背过和懂原理）

> 核心是 **Nested Loop Join（嵌套循环）**：
> 拿驱动表的每一行，去被驱动表里找匹配的行。
>
> - 被驱动表的 JOIN 字段**有索引**：走索引查，叫 `Index NLJ`，效率高（推荐）
> - 没索引：每行都要全表扫，叫 `Block Nested-Loop`，MySQL 会把驱动表一批行放进 `join_buffer` 再比对，尽量少扫
> - MySQL 8.0.18+ 对无索引的等值 JOIN 引入了 **Hash Join**：把小表建成哈希表，大表扫一遍探测，比 BNL 快

★ 追问「**为什么叫小表驱动大表**」：驱动表（外层循环）的行数决定内层循环执行次数。
用小表驱动，内层循环次数少；让大表做被驱动方且 JOIN 字段有索引，每次都走索引。

---

### Q9 ★ JOIN 两个字段类型不一致会怎样？

> ★ 高频坑：`u.id` 是 INT，`o.user_id` 是 VARCHAR → **隐式类型转换，索引失效，JOIN 变全表扫**。
> 同理字符集/排序规则不一致（一个 utf8mb4 一个 utf8）也会失效。
> 规范：**JOIN 字段的类型、长度、字符集、排序规则完全一致**。

---

### Q10 多表 JOIN 的优化建议？

> ① 小表驱动大表；② 被驱动表的 JOIN 字段**必须有索引**且类型一致；
> ③ 能先 WHERE 过滤缩小结果集再 JOIN 就先过滤；
> ④ 别超过 3 张表 JOIN（多了优化器容易选错，也难维护）；
> ⑤ 大表统计类 JOIN 考虑放到离线数仓做，别在在线库跑。

---

## 第三部分：现场手写题（直接默写）

### 题 1：负载均衡配置（含健康检查 + 真实 IP 透传）

```nginx
upstream app {
    least_conn;
    server 10.0.0.1:80 max_fails=3 fail_timeout=30s;
    server 10.0.0.2:80 max_fails=3 fail_timeout=30s backup;
}
server {
    listen 80;
    location / {
        proxy_pass http://app;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 5s;
    }
}
```

### 题 2：查每个用户的订单数（包括 0 单的）

```sql
SELECT u.name, COUNT(o.id) AS order_cnt       -- ★ COUNT(o.id) 不是 COUNT(*)，NULL 不计
FROM user u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.name;
```
★ 追问：为什么用 `COUNT(o.id)` 不用 `COUNT(*)`？
（没订单的用户 LEFT JOIN 后右表是 NULL，`COUNT(*)` 会把它算成 1，`COUNT(o.id)` 对 NULL 不计数，得 0）

### 题 3：查下过订单但**最近一单超过 30 天**的用户

```sql
SELECT u.name, MAX(o.created_at) AS last_order
FROM user u
JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.name
HAVING MAX(o.created_at) < NOW() - INTERVAL 30 DAY;
```
★ 追问：为什么不能写成 `WHERE o.created_at < NOW() - INTERVAL 30 DAY`？
（WHERE 是逐行过滤，会漏掉「有新单也有旧单」的用户；要对**分组后的最大值**判断，只能 HAVING）

### 题 4：两张表结构相同，合并去重

```sql
SELECT * FROM t1
UNION                    -- UNION 去重；UNION ALL 不去重更快
SELECT * FROM t2;
```

---

## 第四部分：自检

| 能答出来吗 | ☐ |
|---|:--:|
| 「负载均衡怎么检查」能说出 5 种方法，并讲出你 curl /whoami 的实测 | ☐ |
| 5 种 LB 算法 + least_conn 和 ip_hash 的适用场景 | ☐ |
| 被动健康检查 `max_fails / fail_timeout` 的含义和缺陷 | ☐ |
| LB 单点怎么解决（Keepalived + VIP）+ 主动交底你的架构边界 | ☐ |
| LEFT JOIN 接 WHERE 变 INNER JOIN 的陷阱 | ☐ |
| 查「没有订单的用户」三种写法 + NOT IN 的 NULL 坑 | ☐ |
| JOIN 的 NLJ / Hash Join 原理 + 小表驱动大表 | ☐ |
| JOIN 字段类型不一致导致索引失效 | ☐ |
| `COUNT(o.id)` 和 `COUNT(*)` 在 LEFT JOIN 后的区别 | ☐ |
| HAVING 和 WHERE 在聚合场景的区别 | ☐ |
