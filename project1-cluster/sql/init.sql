-- 项目一：业务库初始化（只在主库 node1-db 执行）
-- 从库的数据由 setup_replication.sh 从主库 dump 导入，不执行本文件

CREATE DATABASE IF NOT EXISTS shop DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE shop;

DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id    INT UNSIGNED NOT NULL                COMMENT '用户ID',
    product    VARCHAR(64)  NOT NULL DEFAULT ''     COMMENT '商品名',
    amount     DECIMAL(10,2) NOT NULL DEFAULT 0.00  COMMENT '金额',
    status     VARCHAR(16)  NOT NULL DEFAULT 'pending' COMMENT 'pending/paid/shipped/done/canceled',
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP TABLE IF EXISTS users;
CREATE TABLE users (
    id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    username   VARCHAR(32)  NOT NULL,
    city       VARCHAR(32)  NOT NULL DEFAULT '',
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 种子数据（少量即可，压力测试数据在项目二里造）
INSERT INTO users (username, city) VALUES
    ('alice','Nanjing'), ('bob','Shanghai'), ('carol','Beijing'),
    ('dave','Hangzhou'), ('eve','Shenzhen');

INSERT INTO orders (user_id, product, amount, status) VALUES
    (1,'keyboard',199.00,'paid'),
    (1,'mouse',   89.50,'paid'),
    (2,'monitor',1299.00,'shipped'),
    (3,'laptop', 5999.00,'pending'),
    (4,'cable',   29.90,'done'),
    (5,'desk',   899.00,'canceled');

-- 给复制账号用的用户（实际复制账号在 setup_replication.sh 里创建）
-- 这里只是占位说明：生产环境不要用 root 做复制账号
