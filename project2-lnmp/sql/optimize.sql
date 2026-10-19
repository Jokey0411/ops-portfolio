-- =============================================================
--  索引优化方案（简历："减少回表，合理设计复合索引，控制索引数量"）
--
--  执行顺序：
--    1) 先跑 bash scripts/bench.sh before   —— 记录优化前基线
--    2) 再执行本文件建索引
--    3) 再跑 bash scripts/bench.sh after    —— 记录优化后数据
-- =============================================================

USE shop;

-- =============================================================
-- Q1: 用户订单分页（最高频场景：WHERE 等值 + ORDER BY + LIMIT）
--   原 SQL: SELECT id,user_id,amount,status,created_at FROM orders
--           WHERE user_id=100 AND status='paid' ORDER BY created_at DESC LIMIT 20;
--   优化前: type=ALL, rows≈300000, Extra=Using where; Using filesort
-- =============================================================
-- 设计思路：
--   ① 等值条件放前面（user_id, status），范围/排序列放后面（created_at）
--   ② 顺序遵循「等值 → 排序 → 范围」，这样 WHERE 和 ORDER BY 都能用上索引
--   ③ 区分度：status 只有 5 个值区分度低，但它在等值过滤里，放第二位可接受
CREATE INDEX idx_orders_user_status_created ON orders (user_id, status, created_at);

-- =============================================================
-- Q2: 分组统计（覆盖索引，消除回表）
--   原 SQL: SELECT user_id, SUM(amount) FROM orders
--           WHERE status='done' GROUP BY user_id;
--   优化前: type=ALL, Extra=Using where; Using temporary; Using filesort
-- =============================================================
-- 设计思路：
--   ① 索引包含查询需要的全部列（status, user_id, amount）→ 覆盖索引
--   ② Extra 里出现 Using index 就说明不用回表了（★ 简历"减少回表"的直接证据）
--   ③ GROUP BY user_id 能利用索引有序性，避免临时表
CREATE INDEX idx_orders_status_user_amount ON orders (status, user_id, amount);

-- =============================================================
-- Q3: 范围条件 + 排序（演示：索引不能解决所有排序）
--   原 SQL: SELECT id,city,amount,created_at FROM orders
--           WHERE city='Nanjing' AND created_at >= '2025-06-01'
--           ORDER BY amount DESC LIMIT 20;
--   优化前: type=ALL, rows≈300000
-- =============================================================
-- 设计思路：
--   ① (city, created_at) 能大幅缩小扫描范围（等值 + 范围，符合最左前缀）
--   ② 但 ORDER BY amount 无法用这个索引排序，仍会 filesort
--      —— 关键认知：范围条件之后的列无法再走索引（B+树在范围后就无序了）
--   ③ 这时不要硬加 (city,amount) 索引，因为收益有限且增加写成本
--      取舍原则：先保证过滤性，排序的数据量已经很小了，filesort 可接受
CREATE INDEX idx_orders_city_created ON orders (city, created_at);

-- =============================================================
-- Q4: JOIN 优化（被驱动表的 join 字段必须有索引）
--   原 SQL: SELECT o.id, u.username, o.amount FROM orders o
--           JOIN users u ON o.user_id = u.id
--           WHERE o.status='paid' AND u.city='Nanjing' LIMIT 20;
-- =============================================================
-- 设计思路：
--   ① JOIN 优化的核心是「小表驱动大表」+ 「被驱动表的关联字段有索引」
--   ② users 是 filtered 后的小表，用它做驱动表去 orders 里查
--   ③ orders.user_id 必须有索引，否则每次匹配都要全表扫（Block Nested Loop）
--      注：idx_orders_user_status_created 的最左前缀已经覆盖了 user_id，
--      ★ 所以这里不需要再单独建 idx_orders_user_id —— 这就是"控制索引数量"
CREATE INDEX idx_users_city ON users (city);

-- =============================================================
--  索引冗余检查（★ 简历"控制索引数量"的落实手段）
-- =============================================================
-- 执行下面这条，看看有没有冗余索引：
--   SELECT * FROM sys.schema_redundant_indexes WHERE table_schema='shop';
-- 注意：performance_schema=OFF 时 sys 视图不可用，
-- 替代办法：手动列出索引，检查是否存在前缀重复
SHOW INDEX FROM orders;
SHOW INDEX FROM users;

-- =============================================================
--  索引的代价（面试必问：为什么不多建几个索引？）
-- =============================================================
-- 1. 写放大：每个二级索引都是一棵 B+ 树，INSERT/UPDATE/DELETE 都要同步维护
--    —— 这张表有 4 个索引，一次 INSERT 就要写 5 棵树（含主键）
-- 2. 空间：30 万行表，4 个索引约占几十 MB
-- 3. 优化器选错：索引太多，优化器可能选到次优索引，反而更慢
-- 结论：单表索引控制在 5~6 个以内，优先建复合索引而不是多个单列索引

-- =============================================================
--  回滚（想回到优化前状态时执行）
-- =============================================================
-- DROP INDEX idx_orders_user_status_created ON orders;
-- DROP INDEX idx_orders_status_user_amount ON orders;
-- DROP INDEX idx_orders_city_created ON orders;
-- DROP INDEX idx_users_city ON users;
