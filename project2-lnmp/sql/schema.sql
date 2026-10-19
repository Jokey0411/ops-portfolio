-- =============================================================
--  LNMP 项目：表结构（优化前基线）
--  注意：这里**故意只保留主键，不加任何二级索引**
--  目的是让慢查询真实出现，再用 EXPLAIN 分析后加索引做对比
--  这样简历上的"优化前后对比"才有真实数据支撑
-- =============================================================

CREATE DATABASE IF NOT EXISTS shop DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE shop;

DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id     INT      UNSIGNED NOT NULL            COMMENT '用户ID',
    product     VARCHAR(64)      NOT NULL DEFAULT ''  COMMENT '商品名',
    amount      DECIMAL(10,2)    NOT NULL DEFAULT 0.00 COMMENT '金额',
    status      VARCHAR(16)      NOT NULL DEFAULT 'pending' COMMENT 'pending/paid/shipped/done/canceled',
    qty         INT              NOT NULL DEFAULT 1,
    city        VARCHAR(32)      NOT NULL DEFAULT '',
    created_at  DATETIME         NOT NULL             COMMENT '下单时间',
    updated_at  DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
    -- ★ 无二级索引：这是"优化前"的状态
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单表';

DROP TABLE IF EXISTS users;
CREATE TABLE users (
    id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    username   VARCHAR(32)  NOT NULL DEFAULT '',
    city       VARCHAR(32)  NOT NULL DEFAULT '',
    vip_level  TINYINT      NOT NULL DEFAULT 0,
    reg_time   DATETIME     NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';

DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items (
    id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    order_id   BIGINT UNSIGNED NOT NULL,
    sku        VARCHAR(32)     NOT NULL DEFAULT '',
    price      DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    num        INT             NOT NULL DEFAULT 1,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单明细';

-- 少量种子数据（压力数据在 gen_data.sql 里造）
INSERT INTO users (username, city, vip_level, reg_time) VALUES
    ('alice','Nanjing',3,'2025-01-15 10:00:00'),
    ('bob','Shanghai',1,'2025-03-22 11:20:00'),
    ('carol','Beijing',2,'2025-05-09 09:15:00'),
    ('dave','Hangzhou',0,'2025-07-30 16:40:00'),
    ('eve','Shenzhen',4,'2025-11-02 20:05:00');
