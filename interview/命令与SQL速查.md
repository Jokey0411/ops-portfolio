# Linux 命令 & MySQL 写法速查

> 定位：和 `高频追问与答法.md` 配套。那份是**口述题怎么答**，这份是**命令和 SQL 怎么写**。
> 环境背景：OpenCloudOS / CentOS 系（systemd），MySQL 8.0。
> 用法：面试前一天过一遍，**遮住右栏自己默念**，卡住的做标记。
>
> ★ = 面试高频 / 容易答错

---

## 一、Linux 命令

### 1.1 文件与目录

| 命令 | 作用 | 常用写法 / 说明 |
|---|---|---|
| `pwd` | 显示当前路径 | `pwd -P` 显示真实路径（穿透软链接） |
| `cd` | 切换目录 | `cd -` 回上一次目录；`cd ~` 回家；`cd ..` 上一级 |
| `ls` | 列出内容 | `ls -lh`（人类可读）、`ls -lt` 按时间排、`ls -la` 含隐藏文件 |
| `mkdir` | 建目录 | `mkdir -p /a/b/c` ★ 递归创建，脚本里必加 |
| `touch` | 建空文件 / 更新时间戳 | `touch file` |
| `cp` | 复制 | `cp -a src dst` ★ `-a` = 保留权限属主时间 + 递归（备份首选）；`-r` 仅递归 |
| `mv` | 移动 / 改名 | 同分区 mv 是改 inode，瞬间完成 |
| `rm` | 删除 | `rm -rf dir` ⚠ 危险；`rm -ri` 逐个确认 |
| `ln` | 链接 | `ln -s /real/path /link` 软链接（可跨分区、可指向目录）；硬链接不加 `-s` |
| `stat` | 看文件详细元信息 | atime / mtime / ctime、inode、权限位 |
| `file` | 判断文件类型 | 比看后缀靠谱，`file xxx.conf` |

### 1.2 查看文件内容

| 命令 | 作用 | 说明 |
|---|---|---|
| `cat` | 全文输出 | `cat -n` 带行号；**大文件别用 cat** |
| `less` / `more` | 分页查看 | ★ `less` 可上下翻，`/关键字` 搜索，`G` 到末尾，`q` 退出 |
| `head` / `tail` | 头 / 尾 N 行 | `tail -n 100`、`head -n 20` |
| `tail -f` | 实时跟踪日志 | ★ 面试必会：`tail -f access.log`；`-F` 在文件被轮转后能自动重开（比 `-f` 稳） |
| `wc` | 统计 | `wc -l` 行数、`wc -c` 字节 |

### 1.3 查找与定位

| 命令 | 作用 | 常用写法 |
|---|---|---|
| `find` | 按条件查找 | 见下方经典四条 |
| `which` | 查命令的可执行文件路径 | `which nginx`（只在 PATH 里找） |
| `whereis` | 找二进制 + 源码 + man | |
| `locate` | 基于索引库，极快 | 新文件要先 `updatedb` |
| `grep -r` | 在文件内容里搜 | `grep -rn "error" /var/log/` 递归搜文本 |

**find 四条必背：**

```bash
find / -name "*.log"                    # 按名字找
find /var -type f -size +100M           # 找大于 100M 的文件（磁盘满了第一时间用）
find /data -mtime +7 -name "*.sql"      # 找 7 天前修改的（-7 表示 7 天内）
find /data -mtime +7 -name "*.sql" -exec rm -f {} \;    # 找到并处理
# 或更安全：find ... -delete   /  find ... | xargs rm -f
```

★ `-mtime +7` = 7 天前（不含第 7 天），`-mtime -7` = 7 天内。面试爱问。

### 1.4 权限与属主

| 命令 | 作用 | 说明 |
|---|---|---|
| `chmod` | 改权限 | `chmod 755 file`、`chmod u+x script.sh`、`chmod -R 644 dir/` |
| `chown` | 改属主属组 | ★ `chown -R nginx:nginx /var/www`（顺序是 用户:组，别写反） |
| `chgrp` | 只改属组 | |
| `umask` | 默认权限掩码 | `umask 022` → 文件 644、目录 755 |
| `sudo` / `su` | 提权 / 切用户 | `sudo -i` 拿 root 环境；`su - user` 带 `-` 才加载目标用户环境 |
| `setfacl` | 精细授权 | `setfacl -m u:tom:rwx /data` |

★ 权限数字：`r=4 w=2 x=1`。
`755` = 所有者 rwx，组和其他 rx；`600` = 只有自己可读写（**私钥文件必须 600**）。

★ 目录必须要有 `x`（执行）权限才能 `cd` 进去——只有 `r` 能 ls 但进不去，面试常问。

### 1.5 文本处理三剑客（面试必考）

#### grep —— 行过滤

```bash
grep "error" app.log              # 基本
grep -i "error" app.log           # 忽略大小写
grep -v "health" app.log          # 反向：排除
grep -n "error" app.log           # 显示行号
grep -c "error" app.log           # 只统计行数
grep -E "err|fail|warn" app.log   # 扩展正则（等同 egrep）
grep -A5 -B5 "error" app.log      # 显示匹配行的前后 5 行（★ 看异常上下文）
grep -rn "timeout" /etc/nginx/    # 递归搜目录
```

#### sed —— 流编辑 / 批量替换

```bash
sed -n '10,20p' file              # 只打印 10~20 行
sed -i 's/old/new/g' file         # ★ 全文替换（加 -i 才写回文件）
sed -i.bak 's/old/new/g' file     # 替换前先备份（改配置前养成习惯）
sed -i 's/#*Port 22/Port 2222/' /etc/ssh/sshd_config
sed '/^$/d' file                  # 删空行
sed -n '/2026-10-19 10/,/2026-10-19 11/p' app.log   # ★ 按时间区间截日志
```

#### awk —— 按列处理（最强）

```bash
awk '{print $1}' file                  # 第 1 列（默认空格分隔）
awk -F: '{print $1, $3}' /etc/passwd   # -F 指定分隔符
awk '$3 > 1000 {print $1}' file        # 带条件
awk '{sum += $2} END {print sum}' file # 求和
awk 'NR>=10 && NR<=20' file            # 取 10~20 行
# $0=整行  $1..$n=第n列  NF=列数  NR=行号
```

#### 组合技（★ 面试说得出这几个很加分）

```bash
# 1) 统计访问 IP Top10（Nginx 日志）
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10

# 2) 统计日志里各状态码数量
awk '{print $9}' access.log | sort | uniq -c | sort -rn

# 3) 查当前目录下最大的 10 个文件/目录
du -sh * | sort -rh | head -10

# 4) 一次性把多个文件里的旧 IP 换掉
grep -rl "1.2.3.4" /etc/nginx/ | xargs sed -i 's/1.2.3.4/5.6.7.8/g'

# 5) 批量杀进程
ps -ef | grep php-fpm | grep -v grep | awk '{print $2}' | xargs kill -9
```

### 1.6 进程管理

| 命令 | 作用 | 说明 |
|---|---|---|
| `ps` | 看进程 | ★ `ps -ef`（全格式）、`ps aux`（带 CPU/内存占用）、`ps -ef --forest` 看父子关系 |
| `top` | 实时看负载 | ★ 第一行 load average 三个值 = 1/5/15 分钟；按 `1` 展开每核；`P` 按 CPU 排、`M` 按内存排 |
| `htop` | top 增强版 | 需安装，支持鼠标和树状 |
| `kill` | 发信号 | ★ `kill -15 PID` 优雅退出（默认），`kill -9 PID` 强杀（**最后手段，可能丢数据**） |
| `pkill` / `killall` | 按名字杀 | `pkill -f "python run.py"`；`-u nginx` 杀某用户的 |
| `nice` / `renice` | 调整优先级 | `nice -n 10 cmd` 低优先级启动；PRI 越小优先级越高 |
| `jobs` / `fg` / `bg` | 作业控制 | `Ctrl+Z` 挂起 → `bg` 放后台 → `fg` 拉回前台 |
| `nohup` | 脱离终端运行 | ★ `nohup cmd > out.log 2>&1 &`，退出 shell 也不死 |
| `&` | 后台运行 | 仅后台，终端关了会挂（要配 nohup / disown） |

### 1.7 系统监控与排障（★ 重点）

| 命令 | 作用 | 面试常问点 |
|---|---|---|
| `uptime` | 看运行时间 + 负载 | load 高 ≠ CPU 高，也可能是 **IO 等待 / D 状态进程** |
| `free -h` | 内存 | ★ `available` 才是可用量；`buff/cache` 高不是问题，Linux 会拿空闲内存做缓存 |
| `df -h` | 磁盘使用率 | `df -i` ★ 看 inode 是否耗尽（小文件太多会 inode 满但空间还剩） |
| `du -sh` | 目录大小 | `du -sh /var/*`、`du -h --max-depth=1 /` |
| `lsof` | 列出打开的文件 | ★ `lsof \| grep deleted`（磁盘满了但 du 找不到，元凶在这）；`lsof -i:80` 看谁占端口 |
| `iostat -x 1` | 磁盘 IO | ★ 看 `%util`（接近 100% = 打满）和 `await`（响应毫秒） |
| `vmstat 1` | 综合 | `r` 运行队列、`b` 不可中断睡眠、`si/so` swap 换入换出（非 0 = 内存不足） |
| `sar` | 历史性能数据 | `sar -n DEV 1` 看网卡流量，`sar -r` 看内存历史 |
| `dmesg` | 内核日志 | ★ `dmesg \| tail -50`，**OOM Kill** 会在这里留证据 |
| `journalctl` | systemd 日志 | `journalctl -u nginx --since "1 hour ago"`；`-f` 跟踪；`--no-pager` 不分页 |
| `uname -a` | 内核版本 | |
| `nproc` / `lscpu` | CPU 核数 | |
| `strace` | 跟踪系统调用 | `strace -p PID` 看进程卡在哪个 syscall（进阶加分） |

★ **服务器卡顿排查顺序（背下来）**：
`top` 看 load/CPU → `free` 看内存和 swap → `iostat -x 1` 看磁盘 → `ss -s` 看连接 → `dmesg | tail` 看 OOM。
一句话：**CPU → 内存 → 磁盘 IO → 网络**。

### 1.8 网络

| 命令 | 作用 | 常用写法 |
|---|---|---|
| `ss` | 查连接/端口（替代 netstat） | ★ `ss -tlnp`（监听端口+进程）、`ss -tnp \| grep :3306`、`ss -s`（总连接数）、`ss -tn state established \| wc -l` |
| `netstat` | 老工具 | `netstat -tlnp`（最小化系统可能没装） |
| `ip` | 网卡/路由 | `ip a`（看 IP）、`ip r`（看路由）、`ip -s link`（看流量统计） |
| `ping` | 连通性 | `ping -c 4 host` |
| `curl` | HTTP 调试 | ★ `-I` 只要响应头、`-v` 详细过程、`-w '%{http_code} %{time_total}'` 看状态码耗时、`-m 5` 超时、`-X POST -d 'a=1'` |
| `wget` | 下载 | `wget -O /tmp/x.tar.gz URL`；`--spider` 只探测不下载 |
| `nc` / `telnet` | 测端口通不通 | `nc -zv 10.0.0.2 3306`（★ 比 telnet 好，有明确退出码） |
| `dig` / `nslookup` | DNS 解析 | `dig +short www.baidu.com` |
| `mtr` | ping+traceroute 合体 | ★ 看链路哪一跳丢包（比 traceroute 好用） |
| `tcpdump` | 抓包 | `tcpdump -i any -nn -A port 80`、`-s0 -w /tmp/cap.pcap host 1.2.3.4` |
| `ssh` | 远程登录 | `ssh -p 2222 user@host`、`-i key.pem`；`ssh -v` 排错 |
| `scp` | 传文件 | `scp -P 2222 file user@host:/tmp/`（★ 端口是大写 `-P`） |
| `rsync` | 增量同步 | ★ `rsync -avz --delete src/ user@host:/dst/`（注意 `src/` 带不带斜杠含义不同） |
| `firewall-cmd` | 防火墙 | `--list-ports`、`--add-port=80/tcp --permanent` + `--reload` |

★ `ss -tlnp | grep :80` 查端口占用是**最高频的一题**。

### 1.9 压缩打包

```bash
tar -czf backup.tar.gz /data          # 打包并用 gzip 压缩（c=创建 z=gzip f=文件）
tar -tzf backup.tar.gz                # 不解压先看内容
tar -xzf backup.tar.gz -C /restore    # 解压到指定目录
tar -czf - /data | ssh host "cat > /tmp/b.tar.gz"   # 边打包边传（不落盘）
gzip -t backup.tar.gz                 # ★ 校验压缩包完整性（备份脚本必做）
zip -r a.zip dir/    /    unzip a.zip
```

★ `f` 参数必须在最后（紧跟文件名）。

### 1.10 用户、磁盘、定时任务、软件包

```bash
# 用户
useradd -m -s /bin/bash ops && passwd ops
usermod -aG wheel ops          # ★ -a 必须加，否则会覆盖原有附加组（经典坑）
id ops                          # 看 uid/gid/组
who / w / last                  # 谁在线 / 登录历史（last 看有没有异常登录）
passwd -l ops                   # 锁定用户

# 磁盘
lsblk                           # 看块设备与挂载关系
fdisk -l                        # 分区表
mount /dev/vdb1 /data          # 挂载（永久要写 /etc/fstab）
blkid                           # 查 UUID（fstab 推荐用 UUID）

# 定时任务
crontab -l / crontab -e
# 格式：分 时 日 月 周  命令
0 2 * * * /opt/backup.sh >> /var/log/backup.log 2>&1
# ★ 面试必答：cron 不执行三大原因
#   ① PATH 很短 → 脚本里写绝对路径或 source /etc/profile
#   ② 脚本没执行权限 / 是 Windows 的 CRLF 换行
#   ③ 没重定向输出，报错看不见
systemctl status cron / crond   # 看 cron 服务

# 软件包
yum install -y nginx  /  apt install -y nginx
yum remove -y pkg     /  yum list installed
rpm -qa | grep nginx  /  dpkg -l | grep nginx
```

### 1.11 systemd 服务管理

```bash
systemctl start|stop|restart|reload nginx
systemctl enable --now nginx      # 设开机自启并立即启动
systemctl status nginx            # 看状态 + 最近几行日志
systemctl is-enabled nginx
systemctl --failed                # 看启动失败的服务
journalctl -u nginx -f            # 跟踪该服务日志
systemctl daemon-reload           # ★ 改了 unit 文件后必须执行
```

★ `reload` vs `restart`：**reload 不中断连接**（nginx 平滑加载配置），生产优先 reload。

### 1.12 重定向与管道（基础但爱考）

```bash
cmd > file          # 标准输出覆盖写入
cmd >> file         # 追加
cmd 2> err.log      # 只重定向错误
cmd > out.log 2>&1  # ★ 正确输出和错误都进同一个文件
cmd &> all.log      # 同上（bash 简写）
cmd1 | cmd2         # 管道：前者的输出作为后者的输入
cmd | tee out.log   # ★ 既屏幕上看到又存文件
cmd < input.txt     # 输入重定向
cmd << 'EOF' ... EOF   # here document
```

★ `2>&1` 的顺序不能写成 `&1>2`，且 `>` file `2>&1` 里 2>&1 必须在后。

---

## 二、MySQL 写法

### 2.1 库 / 表 DDL

```sql
CREATE DATABASE appdb
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_general_ci;
-- ★ 面试点：utf8mb4 才是真 UTF-8（支持 emoji），utf8 是 3 字节的残废版

USE appdb;

CREATE TABLE `user` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键',
  `username`   VARCHAR(64)  NOT NULL                  COMMENT '用户名',
  `mobile`     CHAR(11)     NOT NULL DEFAULT ''       COMMENT '手机号',
  `age`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `balance`    DECIMAL(10,2)   NOT NULL DEFAULT 0.00  COMMENT '金额-Decimal不丢精度',
  `status`     TINYINT      NOT NULL DEFAULT 1        COMMENT '1正常 0禁用',
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                            ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_username` (`username`),
  KEY `idx_status_created` (`status`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';
```

**字段类型选型（面试爱问）**

| 场景 | 选型 | 说明 |
|---|---|---|
| 主键 | `BIGINT UNSIGNED AUTO_INCREMENT` | 别用 INT，会溢出 |
| 字符串/用户名 | `VARCHAR(n)` | n 是**字符数**不是字节；VARCHAR(255) 不一定比 (64) 慢 |
| 手机号/定长编码 | `CHAR(11)` | 定长用 CHAR 更省 |
| 金额 | ★ `DECIMAL(10,2)` | **绝不用 FLOAT/DOUBLE**，会丢精度 |
| 状态/枚举 | `TINYINT` | 比 ENUM 好扩展，别用 VARCHAR 存状态 |
| 时间 | `DATETIME` / `TIMESTAMP` | TIMESTAMP 只到 2038 年且随时区变，★ 推荐 DATETIME |
| 大文本 | `TEXT` | 尽量拆到独立表，避免主表行太长 |

**ALTER TABLE**

```sql
ALTER TABLE user ADD COLUMN email VARCHAR(100) DEFAULT '' COMMENT '邮箱' AFTER mobile;
ALTER TABLE user MODIFY COLUMN email VARCHAR(200) NOT NULL DEFAULT '';   -- 改类型
ALTER TABLE user CHANGE COLUMN email mail VARCHAR(200);                  -- 改列名+类型
ALTER TABLE user DROP COLUMN email;
ALTER TABLE user ADD INDEX idx_age (age);
ALTER TABLE user ADD UNIQUE KEY uk_mobile (mobile);
ALTER TABLE user DROP INDEX idx_age;
ALTER TABLE user RENAME TO t_user;
-- MySQL 8.0 在线 DDL（★ 大表加索引要带上，避免锁表）
ALTER TABLE user ADD INDEX idx_age (age), ALGORITHM=INPLACE, LOCK=NONE;
```

★ **`DROP` / `TRUNCATE` / `DELETE` 三兄弟（必考）**

| | 类型 | 能否回滚 | 是否重置自增 | 速度 | 触发触发器 |
|---|---|---|---|---|---|
| `DROP TABLE` | DDL | ✗ | 表都没了 | 最快 | ✗ |
| `TRUNCATE TABLE` | DDL | ✗ | ★ 重置为 1 | 快 | ✗ |
| `DELETE FROM` | DML | ✓（事务内） | 不重置 | 慢，逐行 | ✓ |

`TRUNCATE` 不走事务、不写 binlog 逐行（只记一条），所以**不能靠 binlog 恢复**。

### 2.2 增删改 DML

```sql
-- 插入
INSERT INTO user (username, mobile, age) VALUES ('tom', '13800138000', 20);
INSERT INTO user (username, mobile) VALUES ('a','1'), ('b','2'), ('c','3');  -- 批量，比单条快很多
INSERT IGNORE INTO user (username) VALUES ('tom');            -- 冲突则跳过不报错
INSERT INTO user (username, login_cnt) VALUES ('tom', 1)
  ON DUPLICATE KEY UPDATE login_cnt = login_cnt + 1;          -- ★ 有则更新（upsert），高频考点
INSERT INTO user_bak SELECT * FROM user WHERE age > 30;       -- 插查询结果

-- 更新
UPDATE user SET status = 0 WHERE last_login < '2025-01-01';
UPDATE user SET balance = balance - 100 WHERE id = 1 AND balance >= 100;  -- 防超卖式写法
UPDATE user u JOIN dept d ON u.dept_id = d.id SET u.dept_name = d.name;   -- 联表更新
UPDATE user SET status = 0 ORDER BY id LIMIT 1000;            -- ★ 大批量更新要加 LIMIT 分批

-- 删除
DELETE FROM user WHERE status = 0 ORDER BY id LIMIT 1000;     -- 分批删，避免长事务
DELETE u FROM user u JOIN dept d ON u.dept_id = d.id WHERE d.name = 'test';  -- 联表删
-- ★ 大表清数据别直接 DELETE（会产生大量 undo + binlog），用 pt-archiver 或分批
```

### 2.3 查询 SELECT —— ★ 书写顺序 vs 执行顺序

**书写顺序（你写的顺序）：**
```sql
SELECT  [DISTINCT] 列 / 聚合函数
FROM    表
[JOIN ... ON ...]
WHERE   行过滤
GROUP BY 分组列
HAVING  分组后过滤
ORDER BY 排序
LIMIT   分页
```

**★ 实际执行顺序（面试必背，背错了整题崩）：**
```
FROM → ON → JOIN → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → LIMIT
```

**由此推出的三个结论（超高频追问）：**
1. `WHERE` 里**不能**用 SELECT 的别名（`SELECT amount*2 AS x ... WHERE x > 10` ❌），因为 WHERE 先于 SELECT 执行；`ORDER BY` 里**可以**用。
2. `WHERE` 在 `GROUP BY` 前 → **能用 WHERE 先过滤就别放 HAVING**，减少分组数据量。
3. `HAVING` 才能用聚合函数（`HAVING COUNT(*) > 5`），`WHERE` 里不行。

```sql
-- 完整示例
SELECT dept_id, COUNT(*) AS cnt, AVG(salary) AS avg_sal
FROM   employee
WHERE  status = 1                      -- 先过滤行
GROUP BY dept_id
HAVING COUNT(*) > 5                    -- 再过滤分组
ORDER BY avg_sal DESC                  -- 这里能用别名
LIMIT 10;
```

### 2.4 常用子句

```sql
-- 条件
WHERE age BETWEEN 18 AND 30
WHERE dept_id IN (1, 2, 3)             -- IN 走索引；NOT IN 遇到 NULL 会返回空集 ⚠
WHERE name LIKE 'tom%'                 -- ★ 前缀匹配走索引；'%tom' 前导通配符不走索引
WHERE name IS NOT NULL                 -- ★ 判空用 IS NULL，不能用 = NULL
WHERE status = 1 AND (age > 20 OR vip = 1)   -- 注意 AND/OR 优先级，加括号

-- 去重与排序
SELECT DISTINCT dept_id FROM employee;         -- 多列 DISTINCT 是对组合去重
ORDER BY created_at DESC, id ASC;              -- 多列排序

-- 分页
SELECT * FROM user ORDER BY id LIMIT 0, 20;    -- 等价于 LIMIT 20 OFFSET 0
SELECT * FROM user ORDER BY id LIMIT 20 OFFSET 40;   -- 第 3 页

-- ★ 深分页优化（必考）：LIMIT 1000000,20 会先扫 100 万行
SELECT * FROM user
  JOIN (SELECT id FROM user ORDER BY id LIMIT 1000000, 20) t USING (id);   -- 延迟关联
-- 或记录上一页最大 id：
SELECT * FROM user WHERE id > 上一页最大id ORDER BY id LIMIT 20;           -- 游标分页，最快

-- 聚合函数
COUNT(*)、COUNT(1)、COUNT(列)   -- ★ COUNT(列) 不计 NULL；COUNT(*) 计所有行
SUM() AVG() MAX() MIN()
GROUP_CONCAT(name SEPARATOR ',')  -- 组内拼接
```

### 2.5 多表 JOIN

```sql
-- INNER JOIN：两边都匹配才保留
SELECT u.name, d.name FROM user u INNER JOIN dept d ON u.dept_id = d.id;

-- LEFT JOIN：★ 左表全保留，右表没匹配补 NULL
SELECT u.name, d.name FROM user u LEFT JOIN dept d ON u.dept_id = d.id;
-- ★ 高频陷阱：WHERE d.name = 'x' 会把 LEFT JOIN 变成 INNER JOIN（NULL 行被过滤掉）
--   要过滤右表，条件写到 ON 里：LEFT JOIN dept d ON u.dept_id = d.id AND d.name = 'x'

-- 查"没有部门的人"（LEFT JOIN + IS NULL，经典题）
SELECT u.* FROM user u LEFT JOIN dept d ON u.dept_id = d.id WHERE d.id IS NULL;

-- 自连接：查同一部门的其他人
SELECT a.name, b.name FROM employee a JOIN employee b ON a.dept_id = b.dept_id
WHERE a.id <> b.id;

-- UNION / UNION ALL
SELECT name FROM t1 UNION ALL SELECT name FROM t2;   -- 不去重，快
SELECT name FROM t1 UNION      SELECT name FROM t2;  -- 去重（有排序开销），慢
```

★ **`UNION` vs `UNION ALL`**：UNION 会去重 + 排序，性能差，能用 ALL 就用 ALL。

### 2.6 常用函数

```sql
-- 字符串
CONCAT(a, '-', b)              -- 拼接
CONCAT_WS(',', a, b, c)        -- 带分隔符拼接，自动跳过 NULL
SUBSTRING(str, 1, 10)          -- 截取（★ 下标从 1 开始）
LEFT(str, 3) / RIGHT(str, 3)
LENGTH(str) / CHAR_LENGTH(str) -- 字节数 / 字符数（中文区别明显）
REPLACE(str, 'old', 'new')
TRIM(str) / UPPER() / LOWER()
LOCATE('a', str)               -- 找位置，返回 0 表示没有

-- 日期
NOW() / CURDATE() / CURTIME()
DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s')
STR_TO_DATE('2026-10-19', '%Y-%m-%d')
DATEDIFF(d1, d2)                       -- 相差天数
TIMESTAMPDIFF(DAY, start, end)         -- ★ 更通用，单位可选 SECOND/MINUTE/HOUR/DAY/MONTH/YEAR
DATE_ADD(NOW(), INTERVAL 7 DAY)        -- 加 7 天；INTERVAL -1 MONTH 减一月
UNIX_TIMESTAMP() / FROM_UNIXTIME(ts)   -- 时间戳互转

-- 流程控制（★ 行转列、统计必备）
CASE WHEN score >= 90 THEN '优'
     WHEN score >= 60 THEN '及格'
     ELSE '不及格' END
IF(cond, a, b)                 -- 三元
IFNULL(x, 0)                   -- NULL 替换
COALESCE(a, b, c)              -- 返回第一个非 NULL
NULLIF(a, b)                   -- a=b 返回 NULL

-- 类型转换
CAST('123' AS UNSIGNED) / CONVERT('123', SIGNED)
-- ★ 隐式类型转换会导致索引失效：varchar 字段用数字查会全表扫
```

### 2.7 窗口函数（MySQL 8.0+，★ 加分项）

```sql
ROW_NUMBER() OVER (...)              -- 1,2,3,4（无并列）
RANK()       OVER (...)              -- 1,2,2,4（并列跳号）
DENSE_RANK() OVER (...)              -- 1,2,2,3（并列不跳号）

-- 语法
函数名 OVER (PARTITION BY 分组列 ORDER BY 排序列 ROWS BETWEEN ... AND ...)

-- 经典题 1：每个部门工资最高的 3 个人（分组 TopN）
SELECT * FROM (
  SELECT name, dept_id, salary,
         ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rn
  FROM employee
) t WHERE rn <= 3;

-- 经典题 2：查每个部门工资排名第二的人（用 DENSE_RANK 处理并列）
SELECT * FROM (
  SELECT name, dept_id,
         DENSE_RANK() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rk
  FROM employee
) t WHERE rk = 2;

-- 经典题 3：去重保留最新一条（★ 删除重复数据只留一条）
DELETE FROM user WHERE id NOT IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY mobile ORDER BY created_at DESC) rn
    FROM user
  ) t WHERE rn = 1
);
-- ★ MySQL 不允许"边查边改同一张表"，必须再套一层子查询（经典报错 You can't specify target table）

-- 累计求和
SELECT month, amount,
       SUM(amount) OVER (ORDER BY month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM sales;
```

### 2.8 子查询与 EXISTS

```sql
-- 标量子查询
SELECT name, (SELECT dept_name FROM dept d WHERE d.id = u.dept_id) FROM user u;

-- IN 子查询
SELECT * FROM user WHERE dept_id IN (SELECT id FROM dept WHERE city = '深圳');

-- ★ EXISTS vs IN（必考）
SELECT * FROM user u WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
-- 结论：
--   子查询结果集小 → 用 IN
--   外表小、内表大且内表有索引 → 用 EXISTS（命中即返回，不做临时表）
--   5.6 以后优化器会自动改写，但原理要会说
-- ★ NOT IN 子查询里若有 NULL，结果恒为空；改用 NOT EXISTS
SELECT * FROM user u WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

### 2.9 索引

```sql
CREATE INDEX idx_mobile ON user(mobile);
CREATE INDEX idx_status_ctime ON user(status, created_at);   -- 复合索引
CREATE UNIQUE INDEX uk_email ON user(email);
DROP INDEX idx_mobile ON user;
SHOW INDEX FROM user;
```

★ **最左前缀原则**：索引 `(a, b, c)` 相当于有 `(a)`、`(a,b)`、`(a,b,c)` 三个索引。
- `WHERE a=1` ✅　`WHERE a=1 AND b=2` ✅　`WHERE b=2` ❌（跳过 a 不走索引）
- `WHERE a=1 AND b>10 AND c=5` → **c 用不上**（范围条件后的列失效，因为 B+ 树范围内后续列无序）

★ **索引失效场景（背 5 条）**
1. 违反最左前缀
2. 对索引列用函数：`WHERE DATE(created_at) = '2026-10-19'` ❌ → 改成范围比较
3. 隐式类型转换：varchar 字段传数字
4. 前导模糊：`LIKE '%abc'`
5. `OR` 连接不同列（除非两列都有索引）、`!=` / `NOT IN` 通常不走

★ **回表与覆盖索引**
二级索引叶子节点存的是**主键值**，查整行要再回主键树查一次 = 回表。
如果查询的列全在索引里，就不用回表 = **覆盖索引**，EXPLAIN 的 `Extra` 显示 `Using index`。

### 2.10 EXPLAIN（★ 面试必会读）

```sql
EXPLAIN SELECT * FROM user WHERE mobile = '138...';
EXPLAIN FORMAT=JSON SELECT ...;      -- 更详细
EXPLAIN ANALYZE SELECT ...;          -- MySQL 8.0.18+，带真实耗时
```

| 列 | 看什么 |
|---|---|
| `type` | ★ 性能从好到坏：`system > const > eq_ref > ref > range > index > ALL`。**出现 ALL（全表扫）就要优化**，至少到 `range` |
| `possible_keys` | 可能用到的索引 |
| `key` | ★ 实际用到的索引（为 NULL = 没用上） |
| `key_len` | 用到的索引长度，越短越"精准" |
| `rows` | ★ 预估扫描行数，越小越好 |
| `Extra` | ★ `Using index`（覆盖索引，好）、`Using filesort`（额外排序，要优化）、`Using temporary`（临时表，要优化）、`Using where` |

### 2.11 事务

```sql
BEGIN;   -- 或 START TRANSACTION
UPDATE account SET balance = balance - 100 WHERE id = 1;
UPDATE account SET balance = balance + 100 WHERE id = 2;
COMMIT;      -- 提交
-- ROLLBACK;   回滚
SAVEPOINT sp1;  ROLLBACK TO sp1;   -- 部分回滚

SET autocommit = 0;                       -- 关闭自动提交（默认 1）
SELECT @@transaction_isolation;            -- 8.0 查隔离级别
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

SELECT * FROM user WHERE id = 1 FOR UPDATE;       -- ★ 排他锁（行锁，必须走索引否则变表锁）
SELECT * FROM user WHERE id = 1 FOR SHARE;        -- 共享锁（8.0，旧版 LOCK IN SHARE MODE）
```

★ **四个隔离级别**（由低到高）：读未提交 → **读已提交(RC)** → **可重复读(RR，MySQL 默认)** → 串行化。
分别解决：脏读 → 不可重复读 → 幻读。MySQL 的 RR 靠 **MVCC + 间隙锁**已经能防大部分幻读。
★ **RR 和 RC 的核心区别**：RR 在事务开始时生成 ReadView，整个事务看到的快照一致；RC 每条 SQL 都生成新 ReadView。

### 2.12 用户与权限

```sql
CREATE USER 'app'@'%' IDENTIFIED BY 'StrongPwd123!';     -- % = 任意主机
CREATE USER 'app'@'10.0.0.%' IDENTIFIED BY 'pwd';        -- 限定网段
GRANT SELECT, INSERT, UPDATE ON appdb.* TO 'app'@'%';
GRANT ALL PRIVILEGES ON appdb.* TO 'app'@'%';
REVOKE INSERT ON appdb.* FROM 'app'@'%';
SHOW GRANTS FOR 'app'@'%';
DROP USER 'app'@'%';
FLUSH PRIVILEGES;    -- 直接改 mysql.user 表后才需要，GRANT 语句不用
ALTER USER 'app'@'%' IDENTIFIED BY 'NewPwd';
-- 8.0 注意：不能用 GRANT 顺带建用户了，必须先 CREATE USER
```

★ 面试点：**权限最小化原则**，应用账号只给 DML，不给 DROP/ALTER。

### 2.13 运维排查语句

```sql
SHOW PROCESSLIST;                  -- ★ 当前所有连接/在跑的 SQL（CPU 高第一反应）
SELECT * FROM information_schema.PROCESSLIST
  WHERE COMMAND != 'Sleep' AND TIME > 10 ORDER BY TIME DESC;   -- 找慢会话
KILL 12345;                        -- 杀会话（先 KILL QUERY 只杀当前语句，更温和）

SHOW VARIABLES LIKE '%max_connections%';
SHOW VARIABLES LIKE '%innodb_buffer_pool_size%';
SHOW GLOBAL STATUS LIKE 'Threads_connected';
SHOW GLOBAL STATUS LIKE 'Slow_queries';
SHOW TABLE STATUS LIKE 'user';      -- 表大小、行数（估算）、引擎
SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024,2) AS MB
  FROM information_schema.TABLES GROUP BY table_schema;    -- 各库占用

-- 慢查询
SET GLOBAL slow_query_log = ON;
SET GLOBAL long_query_time = 1;
SHOW VARIABLES LIKE 'slow_query_log_file';

-- 锁等待
SHOW ENGINE INNODB STATUS\G        -- ★ 看 LATEST DETECTED DEADLOCK 段
SELECT * FROM performance_schema.data_locks;    -- 8.0

-- 主从（8.0 新叫法；老版本是 SHOW SLAVE STATUS）
SHOW REPLICA STATUS\G              -- ★ 看 Replica_IO_Running / Replica_SQL_Running / Seconds_Behind_Master
SHOW BINARY LOGS;
SHOW MASTER STATUS;
```

### 2.14 备份与恢复

```bash
# 备份单个库（InnoDB 一致性快照，不锁表）
mysqldump -uroot -p --single-transaction --master-data=2 --routines --triggers \
  appdb > /backup/appdb_$(date +%F).sql
# ★ --single-transaction：InnoDB + RR 下拿一致性视图，不锁表（有 MyISAM 表则失效）
# ★ --master-data=2：把 binlog 位点写进备份（做 PITR 必需），=1 时是不注释的 CHANGE MASTER

# 只备份表结构 / 只备份数据
mysqldump -uroot -p -d appdb > schema.sql
mysqldump -uroot -p -t appdb > data.sql

# 压缩备份
mysqldump -uroot -p --single-transaction appdb | gzip > /backup/appdb_$(date +%F).sql.gz
# 校验：gzip -t xxx.sql.gz

# 恢复
mysql -uroot -p appdb < /backup/appdb.sql
gunzip < /backup/appdb.sql.gz | mysql -uroot -p appdb

# ★ 时间点恢复 PITR（误删库救命）
mysql -uroot -p appdb < 全量备份.sql
mysqlbinlog --start-datetime="2026-10-19 00:00:00" \
            --stop-datetime="2026-10-19 10:29:00" \
            /var/lib/mysql/binlog.000012 | mysql -uroot -p
# 关键：binlog 必须是 ROW 格式且保留足够久，否则做不了
```

---

## 三、面试手写 SQL 模板（背这 5 个够用）

```sql
-- ① 第 N 高的薪水（经典 LeetCode 题）
SELECT DISTINCT salary FROM employee ORDER BY salary DESC LIMIT 1 OFFSET 1;   -- 第二高
-- 或（不存在返回 NULL）
SELECT IFNULL((SELECT DISTINCT salary FROM employee ORDER BY salary DESC LIMIT 1 OFFSET 1), NULL) AS SecondHighestSalary;

-- ② 分组 TopN
SELECT * FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) rn
  FROM employee
) t WHERE rn <= 3;

-- ③ 删除重复数据，保留 id 最小的一条
DELETE FROM user WHERE id NOT IN (
  SELECT id FROM (SELECT MIN(id) AS id FROM user GROUP BY mobile) t
);

-- ④ 行转列（按状态统计）
SELECT DATE(created_at) AS d,
       SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) AS ok_cnt,
       SUM(CASE WHEN status = 0 THEN 1 ELSE 0 END) AS fail_cnt
FROM orders GROUP BY DATE(created_at);

-- ⑤ 查连续登录 3 天的用户（窗口函数法）
SELECT user_id FROM (
  SELECT user_id, login_date,
         DATE_SUB(login_date, INTERVAL ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date) DAY) AS grp
  FROM (SELECT DISTINCT user_id, DATE(login_time) login_date FROM login_log) a
) b GROUP BY user_id, grp HAVING COUNT(*) >= 3;
-- 思路：日期 - 行号 = 常量 → 说明连续（★ 这套"差值分组"套路通用）
```

---

## 四、自检清单

| 能默写出来吗 | ☐ |
|---|:--:|
| `ss -tlnp \| grep :80` 查端口、`lsof \| grep deleted` 查满盘真凶 | ☐ |
| find 按时间/大小查文件的两条写法 | ☐ |
| IP Top10 那条 awk/sort/uniq 管道 | ☐ |
| sed 批量替换 + 备份原文件 | ☐ |
| 卡顿排查五步：CPU→内存→磁盘→网络→内核日志 | ☐ |
| crontab 不执行的 3 个坑 | ☐ |
| SELECT 的 10 步执行顺序 | ☐ |
| LEFT JOIN 变 INNER JOIN 的陷阱 | ☐ |
| 深分页优化的两种写法 | ☐ |
| 分组 TopN（窗口函数） | ☐ |
| EXPLAIN 的 type / key / rows / Extra | ☐ |
| DROP / TRUNCATE / DELETE 三者的差别 | ☐ |
| 索引失效 5 个场景 | ☐ |
| 主从备份 + PITR 的命令 | ☐ |
| RR 和 RC 的区别 | ☐ |

**打叉的，回服务器敲一遍再背——面试时嘴比手容易忘。**
