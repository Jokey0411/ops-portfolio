-- =============================================================
--  造压测数据：约 30 万行订单 + 5000 用户
--  执行：docker exec -i lnmp-mysql mysql -uroot -pRoot@123456 < sql/gen_data.sql
--  ⚠ 2核2G 机器大约需要 1~3 分钟，别以为卡死了
-- =============================================================

USE shop;

-- ★★ 关键：MySQL 默认 cte_max_recursion_depth=1000，
--    不调大递归 CTE 最多只能生成 1000 行，这是最容易踩的坑
SET SESSION cte_max_recursion_depth = 1000000;

-- 造数期间关掉 binlog 落盘，能快一倍（root 有 SUPER 权限才行）
-- SET SESSION SQL_LOG_BIN = 0;

-- ---------------- 用户表：5000 行 ----------------
INSERT INTO users (username, city, vip_level, reg_time)
SELECT
    CONCAT('user_', n),
    ELT(FLOOR(1 + RAND() * 8), 'Nanjing','Shanghai','Beijing','Hangzhou',
                               'Shenzhen','Guangzhou','Chengdu','Wuhan'),
    FLOOR(RAND() * 5),
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 730) DAY)
FROM (
    WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 5000)
    SELECT n FROM seq
) t;

-- ---------------- 订单表：30 万行 ----------------
INSERT INTO orders (user_id, product, amount, status, qty, city, created_at)
SELECT
    FLOOR(1 + RAND() * 5000),
    CONCAT('product-', FLOOR(1 + RAND() * 300)),
    ROUND(10 + RAND() * 1990, 2),
    ELT(FLOOR(1 + RAND() * 5), 'pending','paid','shipped','done','canceled'),
    FLOOR(1 + RAND() * 5),
    ELT(FLOOR(1 + RAND() * 8), 'Nanjing','Shanghai','Beijing','Hangzhou',
                               'Shenzhen','Guangzhou','Chengdu','Wuhan'),
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 365 * 24 * 60) MINUTE)
FROM (
    WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 300000)
    SELECT n FROM seq
) t;

-- ---------------- 订单明细：每单 1~3 条（约 60 万行，可选）----------------
-- 这一步最耗时，可以按需要注释掉
INSERT INTO order_items (order_id, sku, price, num)
SELECT
    o.id,
    CONCAT('SKU-', FLOOR(1 + RAND() * 500)),
    ROUND(5 + RAND() * 500, 2),
    FLOOR(1 + RAND() * 4)
FROM orders o
WHERE o.id % 2 = 0;      -- 只给一半订单造明细，控制数据量

-- ---------------- 让数据分布更真实：造一个热点用户 ----------------
UPDATE orders SET user_id = 100 WHERE id % 500 = 0;   -- 用户 100 有大量订单，用于测试区分度

-- ---------------- 收尾 ----------------
ANALYZE TABLE orders;
ANALYZE TABLE users;
ANALYZE TABLE order_items;

SELECT
    (SELECT COUNT(*) FROM orders)      AS orders_rows,
    (SELECT COUNT(*) FROM users)       AS users_rows,
    (SELECT COUNT(*) FROM order_items) AS items_rows,
    (SELECT ROUND(SUM(data_length+index_length)/1024/1024,1)
       FROM information_schema.tables WHERE table_schema='shop') AS size_mb;
