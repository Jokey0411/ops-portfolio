# 13 · Linux 基础面试总纲（按重要度排序）

> **定位**：把 `01-Linux基础问答.md`（110 题）+ `06-运维八股.md` 基础条 + `12-基础保底题.md` 合并去重、**按「出现概率 × 重要度」重新排序**的一份总纲。共 **96 题**，面试前只看这一份就够。  
> **和 01 的区别**：01 按知识点分章（系统→权限→进程…），适合系统性补洞；本文件按**考场顺序**排（先问什么、后问什么、哪个答不上直接挂），适合**突击和自测**。  
> **答案标准**：每题给「30 秒版（背这个）+ 展开（理解这个）+ 追问（防被挖）」。答到 L1 是及格，L2 是熟练，**L3（能说我当时看到什么现象）才是录用线**。

---

## 分层说明

| 层级       | 题量 | 出现概率   | 意味着什么          |
| -------- | -- | ------ | -------------- |
| **S 必问** | 26 | 90% 以上 | 答不上基本就凉，必须条件反射 |
| **A 高频** | 30 | 60–80% | 决定面试官认为你"熟不熟"  |
| **B 常考** | 24 | 30–50% | 用来拉开与其他人差距     |
| **C 加分** | 16 | 30% 以下 | 答得出来显功底，答不出不扣分 |

**答题四段式**（所有题通用）：  
`先给结论 → 再给命令 → 说判断依据（阈值/看哪个指标）→ 挂一句自己的实际现象`

---

# 第一层 · S 级必问（26 题）

## S01 · 服务器很卡，你从哪开始查？

|                                                                                                                               |                            |
| ----------------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| **30 秒版**：按 **CPU → 内存 → 磁盘 IO → 网络 → 内核日志** 五步走，工具是 `uptime`/`top` → `free -h` → `df -h` + `iostat -x 1` → `ss -s` → \`dmesg | tail\`。**先保留现场再动手**，不急着重启。 |

**展开**：

```bash
uptime                    # ① 先看 load（1/5/15 分钟），判断"卡"是不是真卡
top                       # ② CPU 谁在吃（按 P 排序）；顺手看 %wa、%st、内存
free -h                   # ③ 看 available、swap 用了多少
df -h && df -i            # ④ 磁盘满没满、inode 满没满
iostat -x 1               # ⑤ %util 接近 100 = 磁盘打满；await 高 = 响应慢
ss -s / ss -tn state established | wc -l   # ⑥ 连接数爆炸没、TIME_WAIT 多不多
dmesg -T | tail -50       # ⑦ 有没有 OOM Killer、磁盘报错、网卡 down
```

判断矩阵（这是真正值钱的部分，能背出来就赢一半）：

| load | CPU 使用率 | %wa | 结论                           |
| ---- | ------- | --- | ---------------------------- |
| 高    | 高（us 高） | 低   | 算力不够 / 业务有死循环                |
| 高    | 低       | 高   | **IO 瓶颈**（等磁盘，最常见）           |
| 高    | 低       | 低   | 大量 D 状态进程（NFS/磁盘挂死）、内存不足频繁回收 |
| 低    | 低       | 低   | 不是本机问题 → 查网络、下游依赖、数据库慢查询     |

**追问**

- 「为什么不先重启？」→ 重启会把现场（进程、连接、日志缓冲）全抹掉，**下次还会复现**。只有在"服务已经不可用且确认无法短期定位"时才重启止损，并且重启前抓 `top -b -n1`、`ss -tnp`、`dmesg` 存文件。
- 「多久要给结论？」→ 5 分钟内先说方向（是 CPU/内存/IO/网络哪一类），再深入，不要让面试官等你敲十分钟命令。
- 「怎么证明是 IO？」→ `iostat -x 1` 的 `%util` 和 `await`，再加 `vmstat 1` 的 `b` 列（阻塞进程数）和 `wa`，三个一起看。

**挂项目**：2C2G 上凌晨备份和业务抢 IO，`%util` 拉满、网站变慢——这就是我真实遇到的那次，解法是错峰 + `ionice`。

---

## S02 · load average 多少算高？

**30 秒版**：load 是「**处于运行态 + 不可中断睡眠态**的平均任务数」，1/5/15 分钟三个值。**要除以 CPU 核数**：超过核数说明有排队，等于核数基本满载，超过 2 倍就要处理。`nproc` 或 `lscpu` 看核数。

**展开**：

```
load average: 1.50, 2.00, 2.50     # 2 核机器 → 1/5/15 分钟趋势
```

- **看趋势不看单点**：1 分钟 >> 15 分钟 = 正在恶化；15 分钟高而 1 分钟低 = 已经过去了。
- **必须看核数**：8 核 load 4 很正常（50%），2 核 load 4 已经很卡。`cat /proc/loadavg` 是同一个数据源。
- **load 里包含 D 状态**（Linux 特有）——所以高 load + 低 CPU 才是 IO 瓶颈的入口。这一点是区分"背过"和"懂"的关键。

**追问**

|   |   |
| - | - |

|   |   |
| - | - |

- 「load 高但 CPU 空闲怎么回事？」→ 有三种：① 大量进程卡在 D 状态（磁盘/NFS 挂死）② 内存不足在疯狂回收（`si/so` 高）③ 云主机被 steal。用 `ps -eo stat | grep -c D` 直接数 D 状态进程。
- 「load 会不会骗人？」→ 会。容器里看到的是**宿主机 load**（`/proc/loadavg` 没做 namespace 隔离），所以容器内 load 高不一定是自己的锅，要用 `cat /sys/fs/cgroup/cpu.stat` 看自己的 throttling。

---

## S03 · CPU 突然 100%，怎么定位到具体进程？

**30 秒版**：`top` 按 P 排序找 PID → `top -Hp <pid>` 找线程 → 线程号转 16 进制对上 `jstack` → 看启动命令和可执行文件确认真身 → 先 `kill -15` 再 `kill -9` → 查根因（业务峰值/死循环/挖矿）。

**展开**：

```bash
top                        # 1. 按 P 以 CPU 排序，记下 PID
top -Hp 12345              # 2. 看这个进程内部哪个线程在烧 CPU，记 TID
printf '%x\n' 12346        # 3. TID 转十六进制 → 对应 Java 栈里的 nid=0x303a
cat /proc/12345/cmdline | tr '\0' ' '   # 4. 完整启动命令：是哪个服务
ls -l /proc/12345/exe      # 5. 可执行文件真实路径（挖矿常伪装成 kworker）
lsof -p 12345              # 6. 打开了哪些文件、连了哪些外网
strace -p 12345 -c -t 5    # 7. 统计 5 秒系统调用，看卡在哪类操作
```

处理顺序：**确认身份 → 评估能不能杀（是不是核心业务）→ `kill -15` 等 3 秒 → 还在再 `kill -9` → 看是否被自动拉起 → 挖根因**。

**追问**

- 「kill -9 杀不掉怎么办？」→ 两种：**D 状态**（等 IO，信号排队但进程不响应，只能等 IO 返回或重启）和 **Z 僵尸**（已经死了，杀它没用，要杀父进程）。`ps -o pid,stat,wchan,cmd -p <pid>` 看 `wchan` 卡在哪。
- 「怎么判断是挖矿？」→ 特征四连：可执行文件在 `/tmp`、`/dev/shm` 下、`ps` 里名字像 `kdevtmpfsi`/`xmrig`、有异常外连（`ss -tnp` 连矿池 3333/5555 端口）、`crontab -l` 里被塞了下载命令。处理：断网 → 保存样本 → 杀进程 → 清 crontab/自启 → 查入侵入口（弱密码 SSH）。
- 「怎么防住下次？」→ 资源限制（`systemd` 的 `CPUQuota=`）、告警（CPU > 80% 持续 5 分钟）、最小权限运行。

---

## S04 · 内存不够怎么排查？free 里该看哪个值？

**30 秒版**：看 **`available`**，不是 `free`。Linux 会把空闲内存拿去做 `buff/cache` 加速，需要时自动回收，所以 `free` 小是正常的。真正的信号是 `available` 很小 + `swap` 被大量使用 + `si/so` 持续不为 0。

**展开**：

```
              total   used   free  shared  buff/cache  available
Mem:           2.0G   1.1G   100M    50M        800M       700M
Swap:          2.0G   300M   1.7G
```

- `available` = 真正还能给新程序用的（含可回收的 cache）。
- `free` 只有 100M 但 available 700M → 健康。
- `available` 只剩几十 M + swap 在涨 → **内存真的不够**。
- `vmstat 1` 看 `si/so`（换入/换出）：持续非 0 说明已经在颠簸（thrashing），性能断崖式下降。

排查顺序：

```bash
free -h
ps aux --sort=-%mem | head -10      # 谁在吃（%MEM 列）
smem -rs rss 2>/dev/null | head     # 按真实 RSS 汇总（比 ps 准，要装 smem）
dmesg -T | grep -i "killed process" # 有没有被 OOM 杀过
```

**追问**

- 「OOM Killer 是什么？」→ 内存耗尽时内核按 `oom_score` 挑一个进程杀掉保系统。日志在 `dmesg` 和 `/var/log/messages`。可以调 `oom_score_adj`（-1000~1000）保护关键进程，把 MySQL 设成 -500 之类。
- 「cache 占满了要不要清？」→ **不要**。`echo 3 > /proc/sys/vm/drop_caches` 只是把缓存扔掉，短期 free 好看，但接下来所有读都要回磁盘，性能更差。这是网上"优化脚本"最常见的坑，面试主动点出是加分项。
- 「OOM 之后服务起不来？」→ 先看是不是被杀了，`systemctl status` 里会有 `killed`；再确认 `Restart=always` 有没有配。

---

## S05 · 磁盘空间满了，怎么定位？

|                                                                |                                                       |
| -------------------------------------------------------------- | ----------------------------------------------------- |
| **30 秒版**：`df -h` 找哪个挂载点满 → `du -sh /*` 一层层下钻找大目录 → 别忘了 \`lsof | grep deleted`（已删除但被进程占用的文件）→ 也看 `df -i\` 是不是 inode 满。 |

**展开**：

```bash
df -h                                  # 1. 哪个分区 100%
du -sh /* 2>/dev/null | sort -rh | head -10    # 2. 从根开始逐层下钻
du -sh /var/* 2>/dev/null | sort -rh | head    # 3. 换到最肥的那层继续
find / -type f -size +500M -exec ls -lh {} \; 2>/dev/null   # 4. 直接揪大文件
lsof +L1 2>/dev/null | head            # 5. ★已删除未释放（df 高 du 低的元凶）
df -i                                  # 6. inode 满不满（小文件太多）
```

**最快的落地结论**：80% 的情况是 `/var/log` 日志没切、`/var/lib/docker` 镜像堆爆、备份文件堆在本地。

**追问**

- 「df 说满了，du 加起来不到一半，为什么？」→ 见 S06。
- 「怎么预防？」→ `logrotate` 按天/按大小切 + 保留 N 份；`docker system prune` 定期清；备份文件加 `find -mtime +7 -delete`；磁盘使用率 > 80% 就告警（不要等 100%）。
- 「根分区满了，服务还能救吗？」→ 先删日志腾出空间（`> /var/log/xxx.log` 清空而不是 `rm`，`rm` 对已打开的文件不释放），`journalctl --vacuum-size=200M` 清 journal，再慢慢迁数据。

---

## S06 · df 和 du 为什么会对不上？

**30 秒版**：正常。`df` 看的是**文件系统层面**（超级块里的块占用），`du` 是**逐个文件累加**。对不上有三个原因：① 已删除但被进程占用的文件（最常见）② 目录被挂载点遮盖 ③ 权限不足 du 看不到某些目录。

**展开**：

| 原因      | 现象            | 怎么验证 / 解决                                                    |
| ------- | ------------- | ------------------------------------------------------------ |
| 已删除未释放  | df 满、du 加起来小  | `lsof +L1` 或 `lsof \| grep deleted` 找到进程，**重启该进程**释放         |
| 挂载覆盖    | 某目录 du 很小甚至为空 | 挂载点下面原本有数据，被新挂的文件系统盖住了；`umount` 后能看到                         |
| 权限/稀疏文件 | du 偏小         | `du` 用 root 跑；稀疏文件（`ls -l` 大但实际占用小）用 `du --apparent-size` 对比 |
| 硬链接重复统计 | du 偏大         | `du -l` 会重复计算，默认不重复                                          |

**追问**

- 「为什么不重启进程就一直占着？」→ Linux 的规则是**文件被打开时，即使 unlink 了，inode 和数据块也不会释放**，直到最后一个 fd 关闭。所以 `rm` 一个正在写的日志，空间不会回来（这也是"日志删了磁盘没降"的经典原因）。
- 「正确清日志的方式？」→ `> app.log`（truncate，fd 不变，空间立即释放）或 `: > app.log`；用 `rm` 就得重启进程。

---

## S07 · 怎么查端口被谁占用？服务起没起来怎么确认？

|                      |                                                                                                                                      |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| **30 秒版**：\`ss -tlnp | grep :80` 看谁监听；`lsof -i :80`备选；测对端通不通用`nc -zv ip port`或`curl -v telnet://ip:port\`。服务三层确认：**进程在（ps/systemctl）→ 端口在（ss）→ 能响应（curl）**。 |

**展开**：

```bash
ss -tlnp                 # t=TCP l=listen n=数字不解析 p=进程（需要 root）
ss -tn state established # 已建立连接（排查"连上了但没响应"）
lsof -i :3306            # 按端口反查进程（没有 ss 的老系统用）
netstat -tunlp           # 老命令，net-tools 包，新系统默认不装
nc -zv 1.2.3.4 3306      # 测端口通不通（-z 只探测不发送数据）
curl -v telnet://1.2.3.4:3306   # 没装 nc 时的替代品
```

**重点区分「进程在」和「端口在」**：

- 进程在但端口没监听 → 服务启动失败（配置错、端口被占），看日志。
- 端口监听在 `127.0.0.1:80` 而不是 `0.0.0.0:80` → **外部连不上**，这是最高频的坑（php-fpm 默认就监听 127.0.0.1:9000，容器里 nginx 连不上）。

**追问**

- 「端口被占了怎么办？」→ `ss -tlnp` 拿 PID → `ps -fp <pid>` 确认是不是能杀 → 能杀就 `kill`，不能杀就改自己服务的端口。**不要上来就 `kill -9`**。
- 「服务显示 active (running) 但访问不了？」→ 四查：监听地址对不对（`0.0.0.0` vs `127.0.0.1`）、防火墙/安全组放行没、SELinux 拦没（`ausearch -m AVC -ts recent`）、上游（反代/负载均衡）配置对不对。

---

## S08 · 三次握手、四次挥手？为什么是三次不是两次？

**30 秒版**：握手 SYN → SYN+ACK → ACK，**三次是为了让双方都确认"我能发、你能收"以及对方的初始序列号**，两次无法防止历史失效连接请求突然到达造成错误建连。挥手 FIN → ACK → FIN → ACK，**四次是因为 TCP 全双工**，两个方向要各自关闭。

**展开**：

```
握手：  client --SYN(seq=x)-->  server
        client <--SYN+ACK(seq=y,ack=x+1)-- server
        client --ACK(ack=y+1)-->  server
挥手：  client --FIN-->  server        （我要关了）
        client <--ACK---  server        （知道了，但我还有数据要发）
        client <--FIN---  server        （我也发完了）
        client --ACK-->  server → client 进入 TIME_WAIT 等 2MSL
```

- **为什么不能两次**：网络里滞留的旧 SYN 可能在连接关闭后到达，服务器两次就建连，白白占资源等一个永远不会来的数据；三次让客户端有机会用 ACK 否认。
- **为什么 TIME_WAIT 要等 2MSL**：① 保证最后一个 ACK 能到达（丢了对方会重发 FIN）② 让本次连接的残余报文在网络中消散，不污染下一个同端口的新连接。

**追问**

|   |   |
| - | - |

|   |   |
| - | - |

- 「TIME_WAIT 大量堆积怎么处理？」→ 先分清是谁在等：`ss -tan state time-wait | wc -l`，看是本地端口还是对端。**治本是长连接/连接池**；治标是 `net.ipv4.tcp_tw_reuse=1`（只对**主动发起**的连接有效，且需要时间戳开启）和扩大 `ip_local_port_range`。**`tcp_tw_recycle` 千万别开**（NAT 环境下会丢包，新内核已删除）。
- 「SYN Flood 怎么防？」→ `net.ipv4.tcp_syncookies=1`、`tcp_max_syn_backlog` 调大、上云 WAF/高防。
- 「半连接队列和全连接队列？」→ `ss -lnt` 的 `Recv-Q`（全连接队列当前长度）和 `Send-Q`（backlog 上限），满了会丢 SYN，对应 `net.core.somaxconn`。这个追问答得出来是明显加分。

---

## S09 · TCP 和 UDP 的区别？各用在什么场景？

**30 秒版**：TCP **面向连接、可靠**（握手、确认重传、排序、流控），开销大；UDP **无连接、不可靠**，头部只有 8 字节，快。TCP 用于 HTTP/SSH/MySQL 这类"一个字节都不能丢"的场景，UDP 用于 DNS、视频直播、游戏、DHCP 这类"晚到不如不到"的场景。

**展开**：

|      | TCP                           | UDP                            |
| ---- | ----------------------------- | ------------------------------ |
| 连接   | 三次握手                          | 无                              |
| 可靠性  | 确认+重传+排序                      | 不保证                            |
| 头部   | 20 字节起                        | **8 字节**                       |
| 传输方式 | 字节流                           | 数据报（有边界）                       |
| 拥塞控制 | 有（慢启动/拥塞避免）                   | 无                              |
| 典型   | HTTP/HTTPS、SSH、MySQL、SMTP、FTP | DNS、DHCP、视频/直播、游戏、SNMP、QUIC 底层 |


**追问**

- 「DNS 为什么用 UDP 也能用 TCP？」→ 常规查询小包走 UDP 53 快；**响应超过 512 字节**（或 EDNS 协商更大）以及**区域传送（主从同步）**&#x8D70; TCP 53。
- 「UDP 怎么保证可靠？」→ 应用层自己做确认重传，QUIC/KCP 就是这套思路——一句话点出 QUIC（HTTP/3 的底层）就是加分。
- 「视频会议为什么不用 TCP？」→ 实时性 > 完整性，重传一个已经过期的帧没有意义，宁可丢帧也不卡顿。

---

## S10 · 进程有哪些状态？D 状态和 Z 状态怎么处理？

**30 秒版**：`R` 运行/可运行、`S` 可中断睡眠（等事件，最常见）、`D` **不可中断睡眠**（等 IO，`kill -9` 都杀不掉）、`T` 停止（被 Ctrl+Z 或调试挂起）、`Z` **僵尸**（已退出但父进程没 wait 回收）。

**展开**：

```bash
ps -eo pid,ppid,stat,wchan:20,cmd | grep -E "^ *[0-9]+ .* D"   # 数 D 状态，看 wchan 卡在哪
ps -eo stat | grep -c Z                                        # 数僵尸
ps -ef | grep defunct                                          # 僵尸显示 <defunct>
```

- **D 状态**：进程在等内核完成 IO（磁盘、NFS），此时信号不处理，所以 `kill -9` 无效。真正原因是**存储层卡了**：查 `dmesg` 有没有 IO error、`iostat` 的 `await`、NFS 服务器是否失联。NFS 挂死导致满屏 D 状态是很经典的线上事故。
- **Z 僵尸**：进程已经死了，只留一个 PCB 占着 PID。**杀僵尸本身没用**，要杀它的**父进程**（`ps -o ppid= -p <zombie_pid>`）让 init/systemd 接管并回收。父进程是 1 号进程的僵尸一般会被自动收掉；收不掉说明父进程代码有 bug（没 wait）。

**追问**

- 「僵尸多了会怎样？」→ 占 PID（`kernel.pid_max` 打满就 fork 不了新进程，整机起不了新服务）和内核内存（task_struct）。
- 「S 和 D 的关键区别？」→ S 能被信号唤醒（`kill` 有效），D 不能。一句话："D 状态的进程你只能等它，或者重启机器。"

---

## S11 · kill -9 和 kill -15 有什么区别？

**30 秒版**：`-15`（SIGTERM）是**礼貌通知**，进程可以捕获、清理临时文件、关连接、刷盘后再退出，是默认信号；`-9`（SIGKILL）是内核**直接剥夺**，进程没有任何机会清理。所以**先 15，等等再 9**。


**展开**：

```bash
kill -15 1234        # 等价 kill 1234，先给机会
sleep 3; ps -p 1234  # 还在？
kill -9 1234         # 兜底强杀
kill -l              # 看全部信号
```

常用信号：

| 信号           | 编号     | 用途                      |
| ------------ | ------ | ----------------------- |
| SIGHUP       | 1      | 重载配置（很多守护进程约定）          |
| SIGINT       | 2      | Ctrl+C                  |
| SIGKILL      | **9**  | 强杀，不可捕获                 |
| SIGTERM      | **15** | 优雅退出，默认                 |
| SIGSTOP/CONT | 19/18  | 挂起/恢复（Ctrl+Z 是 SIGTSTP） |

**追问**

- 「直接 -9 有什么后果？」→ 数据库可能留下未完成事务（靠 redo 恢复但慢）、Nginx 留下 pid 文件、应用留下临时文件和锁；严重时数据不一致。
- 「容器里 kill 有什么不同？」→ 容器 1 号进程如果没正确转发信号（比如用 `sh -c` 启动），`docker stop` 的 SIGTERM 会打不到真正的应用进程，等 10 秒超时后被 SIGKILL，退出码 **137**（128+9）；正常优雅退出是 **143**（128+15）。这两个码能说出来是实战加分。

---

## S12 · 软链接和硬链接的区别？

**30 秒版**：硬链接和源文件**共用同一个 inode**，删源文件内容还在，不能跨分区、不能链目录；软链接是**独立的新文件**（新 inode），内容只是一条路径，源文件删了就变成悬空链接，可以跨分区、可以链目录。

**展开**：

|       | 硬链接 `ln a b` | 软链接 `ln -s a b`             |
| ----- | ------------ | --------------------------- |
| inode | 同一个（链接数 +1）  | 新的 inode                    |
| 删除源文件 | 数据还在，b 仍可读   | b 失效（红色闪烁 / `No such file`） |
| 跨文件系统 | 不行           | 行                           |
| 链目录   | 不行（防止循环）     | 行                           |
| 原文件大小 | 不额外占空间       | 占一个 inode + 路径长度            |

```bash
ln /data/app/config.yml /data/app/config.bak     # 硬链接
ln -s /usr/local/php82 /usr/local/php            # 软链接（升级时只切一次指向，很常用）
ls -li                                           # -i 看 inode，硬链接两个文件 inode 相同
```

**追问**

- 「链接数是什么？」→ `ls -l` 第 2 列，文件是硬链接计数，目录是「自身 + 子目录数 + 父目录里的一条」，所以**子目录数 = 链接数 − 2**（`.` 和父目录记录）。
- 「删除文件的真正条件？」→ **链接数归 0 且没有进程打开它**。这就是"删了文件空间没释放"的底层原因（S06）。
- 「软链接指向相对路径会怎样？」→ 相对的是**软链接所在目录**，不是执行时的当前目录——这是打包迁移后链接失效的常见原因，生产建议用绝对路径。

---

## S13 · inode 是什么？inode 满了怎么办？

**30 秒版**：inode 是文件系统里存**文件元数据**的结构（权限、属主、大小、时间戳、数据块指针），**不存文件名**，文件名在目录项里。每个文件一个 inode，格式化时就固定了总数——**inode 用完，磁盘再有空间也创建不了新文件**。`df -i` 看。

**展开**：

- 一个文件 = 目录项（文件名 → inode 号）+ inode（元数据 + 数据块指针）+ 数据块。
- 文件名不重要，**inode 号才是身份**；改名不影响 inode。
- `ls -i file`、`stat file` 看 inode 号。
- inode 耗尽的典型场景：`/var/spool/postfix` 邮件队列堆积、session 文件、大量小日志、临时文件没清、恶意程序在 `/tmp` 造小文件。

```bash
df -i                                     # IUse% 到 100% 就是满了
find /var -type f | wc -l                 # 哪个目录文件数异常多
find /path -type f -delete                # 清（先确认再删！）
du -s --inodes /var/* 2>/dev/null | sort -rn | head   # 按 inode 数量看目录
```

**追问**

- 「inode 满了能扩容吗？」→ 不能。inode 数在 `mkfs` 时（`-i` 参数控制密度）就定了，只能**清文件**、或**迁移到新格式化的分区**（建的时候减小 bytes-per-inode，inode 更密）。这也是为什么大文件存储盘建议 inode 稀一点，小文件多的盘要密一点。  
  |  |  |  
  | --- | --- |
- 「df -h 有空但写不进去，也可能是别的原因吗？」→ 除了 inode，还有 ① 分区配额（quota）② 只读挂载（`mount | grep " ro,"`）③ SELinux 拒绝 ④ 磁盘硬件只读（`dmesg` 有 IO error 后 ext4 会 remount-ro）。这四个是"磁盘没满却写不进"的完整清单。

## S14 · 权限 755 和 644 分别是什么？chmod / chown 怎么用？

**30 秒版**：`r=4 w=2 x=1`，三组分别对应**属主 / 属组 / 其他人**。`755` = `rwxr-xr-x`（目录和可执行文件常用），`644` = `rw-r--r--`（普通文件）。`chmod` 改权限、`chown` 改属主属组、`chgrp` 只改组。

**展开**：

```bash
chmod 755 app.sh              # 数字法：rwxr-xr-x
chmod u+x app.sh              # 符号法：u/g/o/a + - = r/w/x
chmod -R 755 /var/www         # 递归（目录用，文件慎用）
chown www:www index.html      # 属主:属组
chown -R 999:999 /data/mysql  # ★容器场景必须写数字 UID（宿主机没有 mysql 用户）
chgrp dev app.log
chmod 1777 /tmp               # 粘滞位：谁建的谁才能删
```

**目录的 rwx 和文件的 rwx 含义不同（这是本题的真正考点）**：

| 位   | 对文件  | 对目录                   |
| --- | ---- | --------------------- |
| `r` | 能读内容 | 能 `ls` 列出文件名          |
| `w` | 能改内容 | 能**增删改**目录里的条目（改名/删除） |
| `x` | 能执行  | 能 `cd` 进去、能访问里面的文件    |

三条由此推出的结论，面试很爱追问：

1. **只有 `r` 没有 `x` 的目录**：能看文件名，但 `cd` 不进去、`cat` 不了里面的文件（`Permission denied`）。
2. **删除一个文件看的是"目录的 w"，不是文件自己的 w**——所以只读文件只要目录可写，照样能删（`rm -f` 不提示）。
3. Web 目录常见组合：目录 `755`（要能进）、文件 `644`（只读）、上传目录 `775` + 属组 www。

**追问**

- 「`777` 有什么问题？」→ 任何人可改可执行，Web 目录 777 等于给上传 webshell 开后门；排障时临时开要用完收回来，别写进部署脚本。
- 「权限对但还是 Permission denied？」→ 依次排查：① 上层目录缺 `x`（路径上任意一级没 `x` 都进不去）② SELinux（`ls -Z` 看上下文，`ausearch -m AVC`）③ `chattr +i` 不可变属性（`lsattr`）④ 挂载选项 `ro` / `noexec` ⑤ NFS 的 root_squash。这五条能背出来，这题就是满分。

---

## S15 · 看日志用什么命令？怎么从日志里定位问题？

**30 秒版**：小文件 `cat`，大文件 `less`，实时 `tail -f`（轮转场景用 `-F`），过滤 `grep`，按时间取区间 `sed -n '/起点/,/终点/p'`；systemd 服务统一 `journalctl -u 服务 -f`。

**展开**：

```bash
tail -f /var/log/nginx/access.log                 # 实时跟
tail -F app.log                                   # ★logrotate 改名后还能继续跟新文件
tail -n 200 app.log | grep -i "error"             # 最近 200 行里的报错
grep -c "500 " access.log                         # 统计次数
grep -n "Traceback" app.log                       # 带行号
less +G app.log                                   # 直接跳到末尾看（大文件不刷屏）
sed -n '/2026-11-08 10:00/,/2026-11-08 11:00/p' app.log   # 取时间段
awk '$9==500 {print $7}' access.log | sort | uniq -c | sort -rn | head   # 500 最多的 URL
zgrep "ERROR" app.log-20261107.gz                 # 直接搜压缩的历史日志
journalctl -u nginx -f --since "10 min ago"       # systemd 服务日志
journalctl -p err -b                              # 本次启动的所有 error 级别
```

日志位置速查：

| 文件                                  | 内容                                    |
| ----------------------------------- | ------------------------------------- |
| `/var/log/messages`                 | 系统综合日志（CentOS 系；Ubuntu 是 `syslog`）    |
| `/var/log/secure`                   | 登录认证（Ubuntu 是 `auth.log`），SSH 爆破都在这   |
| `/var/log/cron`                     | 定时任务执行记录（排查 cron 不跑必看）                |
| `/var/log/dmesg` / `dmesg -T`       | 内核日志：OOM、磁盘错误、网卡                      |
| `/var/log/nginx/{access,error}.log` | Web                                   |
| `journalctl`                        | systemd 统一日志（二进制，`-o json-pretty` 可转） |

**追问**

- 「日志太大把磁盘撑爆了怎么办？」→ `logrotate`（`/etc/logrotate.d/`）按天或按大小切、保留 N 份、切完 `reload` 服务重开文件句柄；应急先 `> xxx.log` 清空。
- 「怎么从 access.log 看接口慢？」→ 前提是日志格式里带了 `$request_time`（我们项目 lb.conf 自定义了 `up/ust/urt/rt` 四个变量），然后 `awk` 按 `rt` 排序取 TopN。
- 「前台没日志，去哪找？」→ 服务由 systemd 管的看 `journalctl -u`；容器看 `docker logs -f --tail 100`；`docker logs` 也没有就看 `docker inspect` 里的 `LogPath`。

---

## S16 · crontab 怎么写？写了不执行为什么？

**30 秒版**：五段 `分 时 日 月 周` 加命令。不执行三大坑：**① 脚本没有执行权限或含 Windows CRLF 换行 ② 环境变量不全（尤其 PATH，找不到 docker/mysqldump）③ 命令没写绝对路径 / 没重定向输出，出错也看不到**。

**展开**：

```bash
crontab -e                 # 编辑当前用户的
crontab -l                 # 查看
crontab -u www -l          # 看别人的（需 root）
```

```
分 时 日 月 周  命令
0  3  *  *  *  /opt/ops/scripts/mysql_backup.sh >> /opt/ops/logs/backup.log 2>&1
*/5 * * * *    curl -s -o /dev/null http://127.0.0.1/health
0  9  *  *  1  /opt/ops/scripts/weekly_report.sh
```

特殊写法：`@reboot`（开机执行一次）、`@daily`、`@hourly`；`*/n` 步长；`1-5` 范围；`1,15` 枚举。

**三坑详解（要说出"为什么"）**：

1. **CRLF / 缺执行权限**：Windows 编辑过的脚本第一行变成 `#!/bin/bash\r`，报 `/bin/bash^M: bad interpreter`。`chmod +x` + `dos2unix` 解决；或者 crontab 里直接写 `bash /path/x.sh` 绕过执行权限。
2. **环境变量**：cron 的环境极简（PATH 通常只有 `/usr/bin:/bin`），`docker`、`mysqldump`、自定义 `$JAVA_HOME` 都找不到。**解决：crontab 首行加 `PATH=/usr/local/bin:/usr/bin:/bin`，脚本里用绝对路径**。
3. **看不到错误**：cron 的输出默认当邮件发，邮件服务没配就等于扔了。**必须 `>> log 2>&1`**，再配合"任务成功也写一行日志"的心跳检查。

**追问**

|   |   |
| - | - |

|  |  |
| --- | --- |
- 「怎么确认 cron 到底跑了没？」→ `cat /var/log/cron | grep 脚本名` 看有没有触发；`systemctl status crond` 确认守护进程活着；脚本内部加 `date` 打点。**这是排查 cron 的标准三步**。
- 「任务跑到一半上一条还没完怎么办？」→ `flock -n /tmp/x.lock -c '脚本'`，防止重叠（备份脚本必备）。  
  |  |  |  
  | --- | --- |
- 「cron 和 at 的区别？」→ cron 周期性，at 一次性（`echo cmd | at now + 30 minutes`），at 依赖 `atd` 服务。
- 「cron 写在哪些位置？」→ 见 B18。

---

## S17 · 挂一块新盘，完整流程是什么？

**30 秒版**：**分区 ≠ 格式化 ≠ 挂载**，三步独立。认盘 `lsblk` → 分区 `fdisk`（>2T 用 `parted` GPT）→ `partprobe` 刷新 → `mkfs.xfs` 格式化 → `mkdir` 建挂载点 → `mount` 手动挂 + `df` 验证 → `blkid` 取 UUID 写 `/etc/fstab` → **`mount -a` 验证后再重启**。

**展开**：

```bash
lsblk                          # ① 认盘：多出 vdb（无数字后缀=整盘）
fdisk /dev/vdb                 # ② n→p→1→回车→回车→w（<2T）
#  parted /dev/vdb → mklabel gpt → mkpart primary xfs 0 100% → quit   （>2T 必须 GPT）
partprobe /dev/vdb             # ③ 让内核重读分区表（老系统必须，新版 fdisk 会自动通知）
mkfs.xfs /dev/vdb1             # ④ 格式化分区（不是整盘！XFS 只能扩不能缩）
mkdir -p /data                 # ⑤ 建挂载点（必须是已存在的空目录）
mount /dev/vdb1 /data          # ⑥ 手动挂
df -h /data                    #    验证容量对得上
blkid /dev/vdb1                # ⑦ 取 UUID
```

```conf
# /etc/fstab 六列
UUID=3f8a...  /data  xfs  defaults,noatime,nofail  0  0
# ①设备     ②挂载点 ③类型 ④选项              ⑤dump ⑥fsck顺序
```

```bash
umount /data && mount -a && df -h /data   # ⑧ 验证 fstab（有错现在报，别等重启）
```

**为什么必须用 UUID（必答）**：`/dev/vdb1` 是内核按发现顺序分配的编号，插拔硬盘、云盘卸载重挂、加新盘都可能让它变成 `vdc1`，fstab 就会挂错盘甚至起不来；**UUID 是文件系统自带、格式化时生成且不变的身份**。

**云盘为什么必须加 `nofail`**：云盘启动时如果没挂上（网络/控制台问题），系统会一直等它 → 卡在 emergency mode 进不去。`nofail` 让挂载失败也不阻塞启动；再配 `_netdev` 表示"等网络就绪再挂"。

**追问**

- 「fstab 写错导致进不去系统怎么办？」→ 救援/单用户模式 → `mount -o remount,rw /` → 改 fstab（或注释掉那行）→ 重启。
- 「`umount` 报 target is busy？」→ `lsof +D /data` 或 `fuser -mv /data` 找占用进程；不行用 `umount -l`（懒卸载）或 `-f`。
- 「格式化错了盘怎么办？」→ 立刻停手（别再写），ext4 有概率用 `extundelete` 捞，XFS 基本无解——所以**格式化前一定 `lsblk` 三确认**。

---

## S18 · systemctl 常用命令？restart 和 reload 区别？

**30 秒版**：`start/stop/restart/reload/status`、`enable/disable`（开机自启）、`daemon-reload`（改 unit 后必须）、`journalctl -u` 看日志。**`restart` 是停掉再起，会断连接；`reload` 只是重新读配置，进程不重启、不断连接**。


**展开**：

```bash
systemctl start|stop|restart nginx
systemctl reload nginx           # 重读配置（nginx -s reload 等价）
systemctl status nginx -l        # -l 显示完整行
systemctl enable --now nginx     # ★开机自启 + 立即启动（一条顶两条）
systemctl disable nginx
systemctl is-enabled nginx       # 查是否自启
systemctl list-units --type=service --state=running    # 现在跑着哪些服务
systemctl list-unit-files --state=enabled              # 哪些设了自启
systemctl daemon-reload          # 改了 .service 文件后必须执行
systemctl cat nginx              # 看 unit 内容（含 drop-in）
journalctl -u nginx --since today -f
```

**restart vs reload 的判断**：能不能 reload 看服务支持不支持 `ExecReload`（`systemctl cat` 里有就是支持）。Nginx、sshd、MySQL 都支持；改了**监听端口/用户身份**这类参数必须 restart。

**追问**

- 「`enable` 和 `start` 区别？」→ `enable` 只管"开机自启"（建软链接），当前不启动；`start` 只管"现在启动"，重启后不自动起。两个都要就 `enable --now`。
- 「服务起不来怎么查？」→ `systemctl status` 看最后几行 → `journalctl -u x -n 100` → 注意 `Result:` 和 `code=exited, status=203/EXEC`（路径不对/没执行权限）、`status=1`（程序自身报错）。
- 「怎么自己写一个 service？」→

```ini
# /etc/systemd/system/app.service
[Unit]
Description=My App
After=network.target
[Service]
User=app
ExecStart=/opt/app/start.sh
Restart=always
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
```

`daemon-reload && enable --now app`。

---

## S19 · 接手一台新服务器，第一步做什么？

**30 秒版**：按 **认机器 → 摸资源 → 看服务 → 看安全 → 看备份** 五步来，先建立完整画像再动手。收尾一句"**确认现状之前不改任何配置，所有变更先记录再执行**"。

**展开**：

```bash
# ① 认机器
hostname; cat /etc/os-release; uname -r; uptime; ip a
# ② 摸资源
nproc; free -h; df -h; df -i; lsblk
# ③ 看跑着什么
systemctl list-units --type=service --state=running
ss -tlnp
crontab -l; ls /etc/cron.d/
docker ps 2>/dev/null
# ④ 看安全
last | head; lastb | head            # 谁登过、谁在爆破
grep "Accepted" /var/log/secure | tail   # 近期成功登录的来源 IP
cat ~/.ssh/authorized_keys           # 有没有陌生公钥
firewall-cmd --list-all 2>/dev/null || iptables -L -n
# ⑤ 看兜底
ls /etc/cron.d/ | grep -i backup; systemctl list-timers
```

**为什么要这五步**：① 不知道是什么系统就会拿错命令 ② 不知道资源就容易"扩容解决一切" ③ 服务/端口清单是后续所有排查的基线 ④ 安全是技术支持岗的隐性职责 ⑤ **没有备份的机器上做任何变更都是赌博**。


**追问**

|   |   |
| - | - |

|  |  |
| --- | --- |
- 「发现有人正在爆破怎么办？」→ `lastb | head` 看来源 → `firewall-cmd` 封 IP 或 `fail2ban` 自动封 → 关密码登录只留密钥 → 改端口。**不要只封 IP**，那只是止血。
- 「发现机器被入侵了怎么办？」→ 先**断网但不断电**（保留内存现场），再备份日志证据，然后评估重装。**不要一边查一边继续跑业务**。

---

## S20 · top 输出里 VIRT / RES / %wa / %sy 都是什么？

**30 秒版**：`VIRT` 是申请的虚拟内存（虚大不可怕），`RES` 是**实际占的物理内存**（看谁吃内存就看它），`SHR` 是共享部分。CPU 拆解里 `us` 用户态、`sy` 内核态、`id` 空闲、**`wa` 等 IO**、`st` 被宿主机偷走。

**展开**：

```
top - 10:00:00 up 30 days, load average: 0.50, 0.60, 0.70
%Cpu(s): 10.3 us, 3.1 sy, 0.0 ni, 85.0 id, 1.2 wa, 0.0 hi, 0.4 si, 0.0 st
MiB Mem : 1979.0 total, 100.0 free, 1100.0 used, 800.0 buff/cache
  PID USER   VIRT   RES   SHR S %CPU %MEM  TIME+ COMMAND
 1234 mysql  3.2g  1.1g  200m S  5.0 55.0 100:20 mysqld
```

| 字段        | 含义                      | 怎么用                     |
| --------- | ----------------------- | ----------------------- |
| VIRT      | 虚拟地址空间总量（含 mmap、未使用的申请） | 大没关系，别拿它判断内存            |
| RES       | 常驻物理内存                  | **判断谁吃内存看这个**           |
| SHR       | 共享内存（动态库、共享页）           | 多进程共用时 RES 会虚高          |
| `us` 高    | 应用在算                    | 业务量/死循环/算法问题            |
| `sy` 高    | 内核在忙                    | 系统调用太频繁、上下文切换多          |
| `wa` 高    | 等磁盘                     | **IO 瓶颈**，配 `iostat` 确认 |
| `si/hi` 高 | 软/硬中断                   | 高流量网卡、中断不均（可开多队列）       |
| `st` 高    | 被 hypervisor 抢走         | 云主机超卖/邻居效应（见 C01）       |

交互键：`P` 按 CPU 排、`M` 按内存排、`1` 展开每个核、`c` 显示完整命令、`H` 显示线程、`k` 杀进程。

**追问**

- 「top 里 %CPU 超过 100% 怎么回事？」→ 多核并行，单进程多线程能吃满多个核，top 显示的是"占单核的百分比"，200% = 吃满两个核。`top` 再按 `1` 看每核使用率更清楚。
- 「top 和 ps 的 CPU 为什么不一样？」→ 统计口径不同：`ps aux` 的 `%CPU` 是**进程生命周期内平均**，`top` 是**采样周期内的瞬时**。看瞬间用 top，看累计用 ps。

---

## S21 · 网络不通，你按什么顺序排查？

**30 秒版**：分层来——**先 IP 层（`ping`）→ 再传输层（`nc -zv` / `ss`）→ 再应用层（`curl -v`）**；先本机（监听、防火墙）后远端（安全组、对端服务）。核心一句：**`ping` 不通 ≠ 服务不通**（很多机器禁 ICMP）。

**展开**：

```bash
ping -c 4 223.5.5.5          # ① 出网通不通（IP 层 + 路由）
ping 网关IP                   # ② 网关通不通（内网）
traceroute / mtr 223.5.5.5   # ③ 卡在哪一跳（mtr 能看每跳丢包率，更专业）
dig 域名 / nslookup 域名      # ④ IP 通但域名不通 = DNS 问题
ss -tlnp | grep :80          # ⑤ 本机服务监听没（还是监听在 127.0.0.1？）
nc -zv 1.2.3.4 80            # ⑥ 对端端口通不通（等价 telnet）
curl -v http://IP/           # ⑦ 端口通但没响应 = 应用层
tcpdump -i eth0 host 1.2.3.4 -nn port 80   # ⑧ 终极手段：包到底发没发、回没回
```

**判断口诀**：

- `ping` 通 + 端口通 + `curl` 有响应 = 网络没问题，服务问题。
- `curl` 卡在 `Connected` 之前 = 网络/防火墙问题；卡在等待响应 = 服务端慢。
- 域名不通但 `ping 223.5.5.5` 通 = DNS。

**追问**

- 「`ping` 不通但网页能打开？」→ 对端禁 ICMP（生产常规操作），用 `nc -zv` / `curl` 测端口才作数。**这句回答能立刻区分"只会 ping"和"真排查过"**。
- 「`traceroute` 中间一堆 `*`？」→ 中间设备禁 ICMP，只有**最后一跳**不通才是真故障；用 `mtr` 看丢包率更准。
- 「云上为什么本机 `curl` 通、外面访问不了？」→ 三道门：服务监听地址（`0.0.0.0` vs `127.0.0.1`）、系统防火墙（firewalld/iptables）、**云安全组**。安全组是云上最容易漏的一道。

---

## S22 · vim 三种模式和必会操作？

**30 秒版**：**普通模式**（默认，移动和操作）→ `i/a/o` 进**插入模式** → `Esc` 回普通 → `:` 进**命令行模式**保存退出。必会：`dd` 删行、`yy` 复制、`p` 粘贴、`u` 撤销、`gg/G` 首尾、`/关键字` 搜索、`:%s/旧/新/g` 全文替换、`:wq` 保存退出、`:q!` 不保存强退。

**展开**：

```vim
i      光标前插入        a  光标后插入        o  下一行新开       O  上一行新开
Esc    回普通模式        :  命令行模式
dd     删（剪切）当前行   ndd 删 n 行         yy 复制行  nyy 复制 n 行   p 粘贴
u      撤销              Ctrl+r 重做
gg     跳到文件头        G  文件尾            nG 第 n 行   0 行首   $ 行尾
/词    向下搜索，n 下一个  N 上一个    ?词 向上搜索
:%s/old/new/g    全文替换（g 是每行全部；不加 g 只换每行第一个）
:set nu          显示行号；:set paste 粘贴模式（防自动缩进错乱）；:noh 取消高亮
:wq / :x         保存退出；:q! 不保存强退；:w !sudo tee %  忘 sudo 时的救命写法
```

**为什么服务器必须会 vim**：任何精简系统/救援模式都自带 `vi`，网络设备、容器基础镜像里也只有它，**这是兜底技能**，不是偏好问题。

**追问**

- 「改配置文件改坏了怎么撤回？」→ `u` 逐步撤销，或 `:e!` 丢弃全部修改重新载入（前提是没保存）。
- 「粘贴代码缩进乱掉怎么办？」→ 先 `:set paste` 再粘贴，完了 `:set nopaste`。
- 「大文件 vim 打开很卡？」→ 换 `less`/`view`，或者 `vim -u NONE` 关插件。

---

## S23 · su 和 sudo 有什么区别？

**30 秒版**：`su` 是**切换身份**，要目标用户的密码，切过去就是那个人；`sudo` 是**以他人身份执行一条命令**（默认 root），输**自己的**密码，权限由 `/etc/sudoers` 白名单控制。生产上**用 sudo 不用共享 root 密码**，因为可审计、可细粒度授权。

**展开**：

```bash
su - root            # ★必须带 -（等价 -l），否则环境变量还是原用户的（经典坑）
su - www             # 切成服务账号
sudo systemctl restart nginx     # 以 root 执行一条
sudo -i              # 变成 root 的登录 shell（等价 su -）
sudo -u www whoami   # 以指定用户执行
sudo -l              # 看自己被授予了哪些命令
```

**`su` 不带 `-` 的坑**：环境变量（`PATH`、`HOME`）还是原用户的，`which java` 找到的是旧路径、写文件写到原用户家目录——"切了 root 却各种找不到命令"就是这个原因。

sudoers 配置：

```bash
visudo               # ★必须用 visudo，保存时做语法检查
# 直接编辑写错一个字符，可能导致所有人（包括 root）都无法 sudo
```

```conf
# /etc/sudoers.d/ops（推荐用 .d 目录，一个团队一个文件）
wangjiyun ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx, /usr/bin/journalctl
%devops   ALL=(ALL) ALL
```

**为什么推荐细粒度**：只授权 `systemctl restart nginx` 而不是 `ALL`，即使账号被盗也干不了别的；所有 sudo 操作都记在 `/var/log/secure`（`sudo` 关键字），可追责。

**追问**

- 「sudo 执行找不到命令？」→ `sudo` 用的是 `secure_path`（在 sudoers 里），和你自己的 PATH 不同；写绝对路径或改 `secure_path`。
- 「`su -` 和 `su` 的区别？」→ `-` 会重置环境并切到目标用户家目录，等于是"完整登录"；不带则继承当前环境，是"半切换"。

---

## S24 · `>`、`>>`、`2>`、`2>&1` 分别是什么？为什么 `2>&1` 顺序不能反？

|                                                                        |                                                                               |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| **30 秒版**：`>` 覆盖写、`>>` 追加、`2>` 重定向错误输出、`2>&1` 把错误**合并到标准输出当前指向的地方**、\` | ` 管道把前一个的输出给后一个。**顺序不能反**，因为重定向是**从左到右**生效的，`&1\` 复制的是"执行到它那一刻 stdout 指向的位置"。 |

**展开**：

```bash
cmd > out.log          # stdout 覆盖到文件，stderr 还在屏幕
cmd > out.log 2>&1     # ★ 两个都进文件（正确写法）
cmd 2>&1 > out.log     # ★ 错误：stderr 先指向屏幕(当时的stdout)，然后 stdout 才改到文件 → 错误还是上屏幕
cmd >> out.log 2>&1    # 追加（日志必备）
cmd &> out.log         # bash 简写，等价于 > out.log 2>&1
cmd > /dev/null 2>&1   # 全都丢掉（后台任务常用）
cmd 2>/dev/null        # 只丢错误，正常输出保留
cmd | tee out.log      # 同时写文件和屏幕
```

文件描述符：`0` stdin、`1` stdout、`2` stderr——**所以 `2>&1` 里的 `&1` 是"1 号 fd 当前指向的目标"**，不是"1 号 fd 本身"。这个概念懂了，这道题就再也不会答错。

**追问**

- 「为什么 crontab 里必须写 `>> log 2>&1`？」→ 不写的话错误输出被当邮件（多数机器没配邮件 = 直接丢失），出了事故完全没线索（S16 第三坑）。
- 「`cmd > file` 和 `cmd >> file` 在日志场景的区别？」→ `>` 每次覆盖，重启/重跑会丢历史；日志一律 `>>`。
- 「`tee` 有什么用？」→ 既要看输出又要留文件，`-a` 是追加。

---

## S25 · grep / sed / awk 三剑客的区别？怎么统计访问日志 IP TopN？

|                                                                                                                         |      |         |          |             |
| ----------------------------------------------------------------------------------------------------------------------- | ---- | ------- | -------- | ----------- |
| **30 秒版**：`grep` 按**行过滤**，`sed` 按**行编辑**（替换/删除/取区间），`awk` 按**列处理**（取字段、求和、条件判断）。TopN 万能公式：\`awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10\`。 |

**展开**：

```bash
# grep：找行
grep -rn --include="*.conf" "listen" /etc/nginx    # -r 递归 -n 行号
grep -v "^#" nginx.conf | grep -v "^$"             # 去掉注释和空行（看配置神器）
grep -c "ERROR" app.log                            # 计数
grep -i -A3 -B1 "exception" app.log                # 忽略大小写 + 前后文

# sed：改行 / 取行
sed -n '10,20p' file                # 取 10-20 行
sed -i 's/8080/9090/g' nginx.conf   # ★ -i 直接改文件（改前先备份！）
sed '/^#/d' file                    # 删注释行

# awk：算列
awk '{print $1}' access.log                        # 第 1 列
awk -F: '{print $1":"$3}' /etc/passwd              # -F 指定分隔符
awk '$9>=500 {print $7}' access.log | sort | uniq -c | sort -rn | head
awk '{sum+=$10} END {print sum}' access.log        # 求和
```

**TopN 三件套为什么必须这个顺序**：`sort` 把相同项排到相邻 → `uniq -c` 只能合并**相邻**重复（不 sort 直接 uniq 是无效的，这是最常考的一句）→ 再 `sort -rn` 按次数倒序。

**追问**

- 「`uniq` 为什么不生效？」→ 没先 `sort`。这是三剑客最经典的送分题。
- 「日志有 10G，awk 会不会很慢？」→ 单遍扫描还好；更省的做法是先 `grep` 缩小范围，或用 `parallel`/按天切分；线上分析建议先 `zgrep` 历史压缩日志。  
  |  |  |  |  
  | --- | --- | --- |
- 「统计 PV/UV 怎么算？」→ PV = 行数（`wc -l`）；UV = 唯一 IP 数（`awk '{print $1}' | sort -u | wc -l`）。

---

## S26 · 怎么加用户、加组、改密码？配置存在哪？

**30 秒版**：`useradd` 建用户、`passwd` 设密码、`usermod -aG 组 用户` 加附加组（**`-a` 不能漏**）、`userdel -r` 连家目录一起删。配置在 `/etc/passwd`（账号）、`/etc/shadow`（密码哈希）、`/etc/group`（组）、`/etc/sudoers`（提权）。

**展开**：

```bash
useradd -m -s /bin/bash wangjiyun     # -m 建家目录（默认可能不建） -s 指定 shell
passwd wangjiyun                      # 交互设密码
usermod -aG docker wangjiyun          # ★ -a 是 append，漏了就"覆盖"成只剩这个组
groups wangjiyun / id wangjiyun       # 验证
userdel -r wangjiyun                  # -r 连家目录和邮件一起删
groupadd devops; gpasswd -a user devops
chage -l wangjiyun                    # 密码有效期
```


**`/etc/passwd` 七段必须能背**：

```
wangjiyun:x:1000:1000:Wang Ji Yun:/home/wangjiyun:/bin/bash
 ①用户名 ②密码占位(x=在shadow) ③UID ④GID ⑤注释 ⑥家目录 ⑦登录Shell
```

- `x` 表示真实哈希在 `/etc/shadow`（权限 000/400，只有 root 能读）。
- **Shell 写成 `/sbin/nologin` 就是"禁止登录但能跑服务"**，这是服务账号的标准做法（mysql、nginx、www 都是）。

**追问**

- 「`usermod -G` 漏了 `-a` 会怎样？」→ 用户的附加组被**整体替换**成指定的那一个，原本的 docker/sudo 权限全没了——"加了个组结果 sudo 用不了"的经典事故。
- 「怎么给用户加 sudo 权限？」→ 写 `/etc/sudoers.d/用户名`（`visudo -f`），比直接改主配置文件安全。
- 「UID 1000 和 999 有区别吗？」→ 系统账号一般 < 1000（999 是 MySQL 容器的 mysql 用户），普通用户从 1000 起。**容器 bind mount 场景比对的是数字 UID，不是用户名**——这是我们 `chown 999:999` 的由来。

---

# 第二层 · A 级高频（30 题）

## A01 · Linux 启动流程是什么？runlevel / target 怎么对应？

**30 秒版**：加电 → BIOS/UEFI 自检（POST）→ 读引导程序 **GRUB2** → 加载内核 `vmlinuz` 和 `initramfs` → 内核启动第一个用户态进程 **systemd（PID 1）** → 按 `default.target` 并行拉起服务 → 登录。

**展开**：

```
BIOS/UEFI → POST 自检 → MBR/GPT 引导 → GRUB2 → kernel(vmlinuz) + initramfs
        → systemd(PID 1) → default.target → 各 unit 并行启动 → getty/登录
```

- `initramfs`：一个临时的内存根文件系统，作用是**加载真正的根文件系统所需的驱动**（磁盘控制器、LVM、加密）。驱动没打进去就会卡在 `dracut` 提示符，这是"改了内核参数进不去系统"的常见原因。
- systemd 用 **target** 取代了 SysV 的 runlevel，并且**并行启动**（老 init 是串行脚本），所以开机快。

| 老 runlevel | systemd target    | 含义                |
| ---------- | ----------------- | ----------------- |
| 0          | poweroff.target   | 关机                |
| 1 / S      | rescue.target     | 单用户救援             |
| 3          | multi-user.target | **多用户命令行（服务器默认）** |
| 5          | graphical.target  | 图形界面              |
| 6          | reboot.target     | 重启                |

```bash
systemctl get-default                    # 当前默认 target
systemctl set-default multi-user.target  # 改成命令行启动
systemctl isolate rescue.target          # 立即切换（危险，会停服务）
```

**追问**

- 「initramfs 里没有磁盘驱动会怎样？」→ 卡在 `dracut:/#` 或 `Warning: /dev/... does not exist`，需要重新生成 `dracut -f` 或在内核参数里补驱动。
- 「改了 fstab 起不来，怎么进的救援模式？」→ 系统检测到关键挂载失败会进 emergency mode，输入 root 密码 → `mount -o remount,rw /` → 修 fstab。

---

## A02 · 常用目录分别放什么？/proc 和 /dev 是什么？

**30 秒版**：`/etc` 配置、`/var/log` 日志、`/home` 用户家目录、`/root` root 家目录、`/usr` 程序、`/tmp` 临时、`/opt` 第三方软件、`/proc` 内核运行时虚拟文件、`/dev` 设备文件、`/mnt`/`/media` 挂载点。

**展开**：

| 目录      | 内容               | 备注                                           |
| ------- | ---------------- | -------------------------------------------- |
| `/etc`  | 全系统配置            | `nginx/`、`my.cnf`、`fstab`、`passwd`           |
| `/var`  | 会变大的数据           | **`/var/log` 最容易撑爆盘**、`/var/lib`（数据库、docker） |
| `/usr`  | 程序与库             | `/usr/bin` 命令、`/usr/local` 自己编译装的            |
| `/proc` | 内核和进程的**虚拟**文件系统 | 不占磁盘，重启即失                                    |
| `/sys`  | 内核设备/驱动模型（sysfs） | 调内核参数、看硬件                                    |
| `/dev`  | 设备文件             | 见 B13                                        |
| `/tmp`  | 临时文件             | 有的系统重启清空，**别放重要东西**                          |
| `/opt`  | 额外装的第三方软件        | 我的项目就放 `/opt/ops`                            |

`/proc` 里最常用的几个：

```bash
cat /proc/cpuinfo        # CPU 型号/核数
cat /proc/meminfo        # 内存明细（free 的数据源）
cat /proc/loadavg        # load（uptime 的数据源）
cat /proc/<pid>/status   # 进程状态、内存、线程数
ls /proc/<pid>/fd        # 进程打开了哪些 fd（见 A03）
cat /proc/<pid>/io       # 进程读写字节数
cat /proc/net/tcp        # 连接表（ss 的数据源）
```

**追问**

- 「/proc 里的文件能改吗？」→ 一部分能，改的是内核运行时参数，比如 `/proc/sys/net/ipv4/ip_forward`（等价 `sysctl -w`）；但**重启失效**，永久要写 `/etc/sysctl.d/`。
- 「为什么说'一切皆文件'？」→ 设备（`/dev/sda`）、进程信息（`/proc/1`）、内核参数（`/proc/sys/*`）、socket 都用统一的 open/read/write/close 接口访问，所以 `cat` 能看内存信息、`echo` 能改内核参数。


## A04 · 前台、后台、守护进程怎么管理？

**30 秒版**：命令后加 `&` 放后台、`Ctrl+Z` 挂起、`jobs` 看、`bg`/`fg` 切换；`nohup cmd &` 让进程**忽略 SIGHUP**，SSH 断了也不死。但**长期服务不该用 nohup，应该写成 systemd unit**。

**展开**：

```bash
cmd &            # 后台跑，但终端一关就收到 SIGHUP 被杀
Ctrl+Z           # 挂起到后台并暂停（SIGTSTP）
jobs -l          # 看后台任务和 PID
bg %1            # 让 1 号任务在后台继续跑
fg %1            # 拉回前台
kill %1          # 按任务号杀
nohup ./app.sh > app.log 2>&1 &      # 免疫挂断 + 输出重定向
disown -h %1     # 已经跑起来的任务，事后脱离终端
setsid ./app.sh &                    # 新会话运行，彻底脱离终端
```

**`nohup cmd > out.log 2>&1 &` 三段拆解**：

| 部分               | 作用                                   |
| ---------------- | ------------------------------------ |
| `&`              | 放后台，**但不免疫挂断**                       |
| `nohup`          | 忽略 SIGHUP（终端关闭时发的信号）                 |
| `> out.log 2>&1` | 不写就默认进 `nohup.out`，容易撑爆家目录；且错误也进同一文件 |

**追问**

- 「为什么长期服务推荐 systemd 而不是 nohup？」→ ① 崩溃能不能自动拉起（`Restart=always`）② 开机自启 ③ 日志统一进 journald ④ 资源限制（`MemoryMax`、`CPUQuota`）⑤ 依赖顺序（`After=network.target`）。nohup 这五样都没有。
- 「SSH 断了进程还是死，为什么？」→ 只加了 `&` 没加 `nohup`，收到 SIGHUP 就退出了；或者 shell 退出时给整个进程组发了 SIGHUP。

---

## A05 · 程序开机自启有哪几种方式？

**30 秒版**：**① systemd unit（首选）② `crontab @reboot` ③ `/etc/rc.local` ④ 容器用 `restart: always`**。生产一律 systemd，因为有自动重启、日志、资源限制、依赖顺序。

**展开**：

```ini
# ① /etc/systemd/system/app.service（标准做法）
[Unit]
Description=Ops App
After=network-online.target
Wants=network-online.target
[Service]
User=app
WorkingDirectory=/opt/app
ExecStart=/opt/app/start.sh
Restart=always
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload && systemctl enable --now app
```

```bash
# ② crontab（简单脚本，不做服务）
@reboot /opt/ops/scripts/start_agent.sh >> /tmp/agent.log 2>&1

# ③ rc.local（老方式，需 chmod +x /etc/rc.d/rc.local 且在 systemd 里 enable rc-local）
# ④ 容器
# docker-compose.yml 里 restart: always / unless-stopped
```

`restart: always` 和 `unless-stopped` 的区别：前者连手动 `docker stop` 的容器在 daemon 重启后也会拉起来；后者尊重你手动停的状态，**生产更推荐 `unless-stopped`**。

**追问**

- 「`rc.local` 为什么不执行？」→ 没执行权限（CentOS 7+ 默认 `rc.local` 没有 +x）、`rc-local.service` 没 enable、脚本里有交互式命令卡住。
- 「systemd 服务启动失败怎么排查？」→ `systemctl status` 看 `status=203/EXEC`（路径/权限错）、`status=1`（程序自身错）；`journalctl -u app -n 50` 看真实报错；注意 `Environment=` 里缺环境变量。

---

## A06 · 日志太大怎么切割？logrotate 原理？

**30 秒版**：`logrotate` 按**时间或大小**切割、压缩、保留 N 份。配置在 `/etc/logrotate.conf`（全局）和 `/etc/logrotate.d/*`（每个服务一个文件），由 cron/systemd timer 每天触发。

**展开**：

```conf
# /etc/logrotate.d/nginx
/var/log/nginx/*.log {
    daily                 # 每天切（也可 size 100M / hourly）
    rotate 14             # 保留 14 份
    compress              # gzip 旧文件
    delaycompress         # 延后一轮再压缩（避免压正在写的）
    missingok             # 文件不存在不报错
    notifempty            # 空文件不切
    create 0644 nginx nginx   # 新文件权限属主
    sharedscripts
    postrotate
        /usr/bin/systemctl reload nginx > /dev/null 2>&1
    endscript
}
```

```bash
logrotate -d /etc/logrotate.d/nginx    # -d 干跑，只看不执行（★改配置后先干跑）
logrotate -f /etc/logrotate.d/nginx    # 强制立即切一次
```

**核心原理（这是本题真正的考点）**：切割时把 `app.log` 改名成 `app.log-20261107`，然后需要让应用**重新打开新的 `app.log`**——所以有两条路：

- `postrotate` + `reload`：通知进程重开文件（nginx、rsyslog 这类支持）——**推荐**。
- `copytruncate`：先复制再清空原文件（`> app.log`），**不用重启应用**，但复制和清空之间的几毫秒日志会丢。

**追问**

|   |   |
| - | - |

|  |  |
| --- | --- |
- 「切完之后应用还在往老文件写怎么办？」→ 就是没 reload；`lsof | grep app.log` 会看到进程持有的是 `app.log-2026xxxx`（deleted 或改名后的），必须让进程重开。
- 「用 `copytruncate` 有什么坑？」→ 丢几毫秒日志；文件特别大时复制本身很慢很占 IO。
- 「journald 的日志怎么限制？」→ `/etc/systemd/journald.conf` 的 `SystemMaxUse=500M`，或 `journalctl --vacuum-size=200M` 手动清。

---

## A07 · 服务器时间不准有什么影响？怎么同步？

**30 秒版**：影响比命令重要——**① 日志时间错乱，排障对不上因果 ② cron 任务错点/重复跑 ③ HTTPS 证书校验失败、Kerberos/token 认证直接挂 ④ 数据库主从/分布式事务出错 ⑤ 计费对账出错**。同步用 `chronyd`（新系统标配），时区用 `timedatectl set-timezone Asia/Shanghai`。

**展开**：

```bash
timedatectl                          # 时区、时间、NTP 同步状态（看 System clock synchronized: yes）
timedatectl set-timezone Asia/Shanghai
timedatectl set-ntp true             # 开启 NTP 同步
chronyc sources -v                   # 看 NTP 源和偏差（^* 是当前同步的源）
chronyc tracking                     # 看系统时钟偏差多少毫秒
hwclock -w                           # 把系统时间写进硬件时钟（BIOS），重启不丢
ntpdate ntp.aliyun.com               # 老式一次性校时（服务运行时慎用，会时间跳变）
```

- **`chronyd` 是平滑调整**（慢慢把时间拉回来），`ntpdate` 是**直接跳变**——跳变会让依赖时间差的程序出错（比如 `sleep`、超时判断、数据库事务），所以生产用 chrony。
- 内网统一：所有机器指向同一台内网 NTP（或 `ntp.aliyun.com`），**时区必须一致**，否则日志跨机器对不上。

**追问**

- 「容器里时间不对怎么办？」→ 容器默认共享宿主机内核时钟，所以**容器时间不对 = 宿主机时间不对**；时区不对是镜像里没 `TZ=Asia/Shanghai` 或没装 tzdata。
- 「为什么证书会因时间失败？」→ TLS 校验证书的有效期（notBefore/notAfter），系统时间偏差太大会判定"证书还没生效/已过期"，报 `certificate is not yet valid`。这个具体报错能说出来很加分。

---

## A08 · 怎么查谁登录过服务器？被爆破怎么看？

**30 秒版**：`w`（当前在线 + 在干什么）、`who`、`last`（历史登录，读 `/var/log/wtmp`）、`lastb`（**失败**记录，读 `/var/log/btmp`）、`lastlog`（每人最后一次登录）、`grep sshd /var/log/secure` 看详细认证日志。

**展开**：

```bash
w                       # 在线用户 + 来源 IP + 正在执行的命令 + 负载
who                     # 简版
last | head -20         # 历史成功登录（-x 也显示关机记录）
lastb | head -20        # ★ 失败登录，爆破会刷屏（需 root）
lastlog                 # 每个用户最后一次登录时间/IP（Never logged in = 从没登过）
grep "Failed password" /var/log/secure | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head
grep "Accepted" /var/log/secure | tail    # 成功的来源 IP
```

**发现被爆破的处理顺序**：`lastb` 确认来源 IP 和频率 → **封 IP**（`firewall-cmd --add-rich-rule` 或 `fail2ban`）→ **关密码登录**（`PasswordAuthentication no`）→ 改端口 → 安装 fail2ban 自动封禁 → 检查有没有成功登录（`grep Accepted`）、有没有陌生公钥（`authorized_keys`）、有没有异常进程。

**追问**

- 「`lastb` 文件巨大把磁盘占了？」→ `/var/log/btmp` 会被爆破写爆，`> /var/log/btmp` 清空或加 logrotate；这本身就是"必须关密码登录"的理由。
- 「怎么查某个用户最近做了什么？」→ `history`（只对交互式 shell 有效，且在 `~/.bash_history`）、`last`、sudo 日志（`/var/log/secure` 里 grep sudo）、`journalctl _COMM=sudo`。
- 「`w` 第一行是什么？」→ 当前时间、开机时长、在线用户数、load average——**排查时先看这一行**。

---

## A09 · SSH 免密登录的原理？为什么配了却不生效？

**30 秒版**：本地 `ssh-keygen` 生成密钥对，把**公钥**追加到服务器 `~/.ssh/authorized_keys`（`ssh-copy-id` 一条搞定）。登录时服务器用公钥加密一段挑战，客户端用**私钥**解密应答——**私钥永不外传**。不生效 99% 是**权限问题**：`.ssh` 要 700、`authorized_keys` 要 600、家目录不能是 777。

**展开**：

```bash
ssh-keygen -t ed25519 -C "wangjiyun@laptop"     # 生成（比 rsa 更短更安全）
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@1.2.3.4
ssh -i ~/.ssh/id_ed25519 root@1.2.3.4
```

```bash
# 服务端权限（StrictModes 会检查，太松直接拒绝）
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~                       # 家目录不能 777 / 组可写
restorecon -Rv ~/.ssh             # SELinux 上下文不对也会失败
```

**原理一句话**：非对称加密——公钥能加密、私钥才能解；服务器只存公钥，所以即使服务器被读也不能冒充你登录。

**追问**

- 「免密配好还是提示输密码，怎么查？」→ `ssh -vvv user@host` 看详细过程，会明确写出 `Authentication refused: bad ownership or modes`；然后逐级 `ls -ld` 查权限，再查 SELinux（`ls -Z`、`ausearch -m AVC -ts recent`）。
- 「怎么加固 SSH？」→ 四件套：`PermitRootLogin no`、`PasswordAuthentication no`、改端口、`AllowUsers` 白名单；再配 fail2ban。
- 「多台机器怎么管密钥？」→ 一份私钥配多台（简单）或用 `~/.ssh/config` 起别名；更规范是每台独立密钥 + 集中跳板机，便于吊销。



---

## A10 · SSH 突然连不上云服务器，你怎么排查？

**30 秒版**：由外到内八步——**本地网络 → 控制台实例状态 → 安全组 22 端口 → ping → `ssh -v` 看卡在哪一步 → 认证细分（密码/密钥权限/sshd 配置）→ 进去看 sshd 日志和 fail2ban → 最后用控制台 VNC 兜底**。

**展开**：

```bash
ssh -v root@1.2.3.4        # ★ 关键：看卡在哪
```

| 卡住的位置                           | 含义                           | 下一步                              |
| ------------------------------- | ---------------------------- | -------------------------------- |
| `Connecting to ...` 无响应         | **网络层**：安全组/防火墙/主机挂了         | 查安全组、控制台状态、`ping`                |
| `Connection refused`            | 端口没开或 sshd 没起                | 查 sshd 服务、端口是否改过                 |
| `Connection timed out`          | 包被静默丢弃                       | 安全组、防火墙 DROP 规则                  |
| `Permission denied (publickey)` | **认证问题**                     | 密钥权限、authorized_keys、sshd_config |
| `Host key verification failed`  | 本地 known_hosts 有旧记录（重装系统后常见） | `ssh-keygen -R 1.2.3.4`          |

完整清单（由外到内）：

1. 换网络试（手机热点）——排除自己这边。
2. 控制台看实例：是否关机/欠费/CPU 100% 卡死。
3. **安全组 22 端口**：换过网络/换过出口 IP 后最常被拦。
4. `ping`（不通可能是禁 ICMP，不代表服务挂）。
5. `ssh -v` 定位层次（上表）。
6. 认证细分：密码错误、密钥权限（A09）、`PasswordAuthentication` 被关、`AllowUsers` 限制。
7. 能进就看 `systemctl status sshd`、`journalctl -u sshd`、`tail /var/log/secure`、`fail2ban-client status sshd`。
8. **VNC / 控制台远程连接兜底**——"VNC 永远可用"这句话是技术支持岗的底气。

**追问**

- 「改 sshd 配置把自己锁在外面怎么办？」→ 改之前**开两个会话**（一个不断开）、改完先 `sshd -t` 语法检查、再 `systemctl reload sshd` 而不是 restart；最坏情况 VNC 进去改回来。
- 「`WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED` 怎么办？」→ 服务端重装/换机器导致 host key 变了，`ssh-keygen -R <ip>` 清掉旧记录（确认变化合理再清，否则可能是中间人攻击）。

---

## A11 · 防火墙 firewalld 怎么配？有哪些坑？

**30 秒版**：`firewall-cmd --add-port=80/tcp --permanent` 加规则 → **`--reload` 才生效** → `--list-all` 验证。三个坑：**① 忘 `--permanent` 重启丢规则 ② 加了 permanent 忘 reload 没生效 ③ 把 SSH 也拦了把自己关在外面**。云上还要配**安全组**（两层防护）。

**展开**：

```bash
systemctl enable --now firewalld          # ★先 --add-service=ssh 再启动，或启动前确认 SSH 已放行
firewall-cmd --list-all                   # 当前 zone 的全部规则
firewall-cmd --add-service=ssh --permanent
firewall-cmd --add-service=http --add-service=https --permanent
firewall-cmd --add-port=8080/tcp --permanent
firewall-cmd --reload                     # ★ 必须
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" port port="3306" protocol="tcp" accept'
firewall-cmd --get-active-zones
firewall-cmd --change-interface=eth0 --zone=internal
```

**zone 概念**：`public`（默认，只放行显式加的）、`trusted`（全放行，慎用）、`internal`/`dmz`/`drop`。一块网卡只能属于一个 zone。

**云上必答的一句**：**系统防火墙 + 云安全组是两道独立的门，都要开**。只开 firewalld 没开安全组 → 外面还是不通；只开安全组没开 firewalld → 也不通。这是云上排查"端口开了却访问不了"的第一嫌疑。

**追问**

- 「跑 Docker 的机器能 `iptables -F` 吗？」→ **绝对不能**，`iptables -F` 会把 Docker 的 `DOCKER`/`DOCKER-USER` 链清掉，容器网络直接瘫。要清规则用 `firewall-cmd` 或先 `systemctl stop docker`。
- 「Docker 的 `-p` 映射绕过 firewalld 吗？」→ 绕过。Docker 直接往 nat 表插 DNAT 规则，firewalld 的 zone 管不到，所以**容器端口实际是对外开放的**。要限制就在绑定地址上写 `127.0.0.1:8080:80`，或用 `DOCKER-USER` 链限源。这条说出来是明显加分项。
- 「怎么临时放开所有流量应急？」→ `--panic-off` 关闭 panic 模式前先确认风险；应急开通建议精确到 IP 的 rich rule，不要 `--zone=trusted`。


## A13 · 内核参数（sysctl）怎么调？永久生效写哪？

**30 秒版**：临时 `sysctl -w 键=值`，**永久写 `/etc/sysctl.d/99-xxx.conf` 然后 `sysctl -p 文件`**（写到 `.d` 目录比直接改 `sysctl.conf` 好管理）。改前先记原值，不要整套照抄网上"高并发优化参数"。

**展开**：

```bash
sysctl net.ipv4.ip_forward          # 查
sysctl -a | grep somaxconn          # 全量查某项
sysctl -w net.ipv4.ip_forward=1     # 临时
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ops.conf
sysctl -p /etc/sysctl.d/99-ops.conf # 立即加载
sysctl --system                     # 加载全部 .d 文件（推荐）
```

常调参数（**要说得出为什么要调**）：

| 参数                             | 值          | 为什么                                 |
| ------------------------------ | ---------- | ----------------------------------- |
| `net.ipv4.ip_forward`          | 1          | Docker/容器网络、NAT 必须开                 |
| `net.core.somaxconn`           | 65535      | accept 队列上限，抗突发连接（配合 nginx backlog） |
| `net.ipv4.tcp_max_syn_backlog` | 65535      | 半连接队列，防 SYN Flood                   |
| `net.ipv4.tcp_tw_reuse`        | 1          | TIME_WAIT 复用（**只对主动发起方有效**）         |
| `net.ipv4.ip_local_port_range` | 1024 65000 | 扩大客户端可用端口                           |
| `vm.swappiness`                | 10         | 数据库机器尽量不用 swap                      |
| `fs.file-max`                  | 655350     | 系统级 fd 上限（配 A03）                    |
| `vm.overcommit_memory`         | 1          | Redis 场景（fork 时避免分配失败）              |

**追问**

- 「`tcp_tw_recycle` 能不能开？」→ **不能**，NAT 环境下会丢包（按源 IP 时间戳判断，多台机器共享一个出口 IP 时误杀），Linux 4.12 起已移除。
- 「调完没生效怎么查？」→ `sysctl 键名` 看当前值；注意**同名参数被后面的文件覆盖**（`.d` 里按文件名字典序加载，`99-` 是最后），`sysctl --system` 会打印加载顺序。
- 「有参数调错了把网络搞挂怎么办？」→ 云控制台 VNC 进去改文件，或重启（临时参数不持久，这是个安全网）。

---

## A14 · swap 是什么？怎么加？用多了说明什么？

**30 秒版**：swap 是磁盘上的一块空间，内存不够时把**不活跃的页**换出去。`swap` 用得多 = **物理内存紧张**，性能会明显下降（磁盘比内存慢几个数量级）。用文件方式加最方便，`vm.swappiness` 控制使用倾向。

**展开**：

```bash
free -h                                  # 看 swap 总量和已用
swapon --show                            # 当前生效的 swap
vmstat 1                                 # si/so 非 0 = 正在换入换出（颠簸）
fallocate -l 2G /swapfile                # ① 建 2G 文件
chmod 600 /swapfile                      # ② 权限 600（必须，否则 swapon 报错）
mkswap /swapfile                         # ③ 格式化成 swap
swapon /swapfile                         # ④ 启用
echo '/swapfile none swap defaults 0 0' >> /etc/fstab   # ⑤ 开机自动挂
swapoff /swapfile                        # 停用
```

**`vm.swappiness`（0-100，默认 60）**：值越大越积极用 swap。数据库/中间件机器建议调到 10（尽量留在内存里），桌面可以高一点。

**追问**

- 「swap 打满了怎么办？」→ 先查谁在吃内存（`ps aux --sort=-%mem`），不是急着加 swap——swap 打满时系统基本已经在颠簸，加 swap 只会更慢。要么扩容内存，要么限流/重启泄漏的进程。
- 「为什么数据库机器要关/调低 swap？」→ swap 换出换入会导致查询延迟从毫秒变成秒级；MySQL 的 buffer pool 被换出去等于缓存全失效。
- 「云主机默认有 swap 吗？」→ 通常没有（或很小），因为云盘做 swap 性能差且影响系统盘寿命；自己按上面的方式加文件 swap。

---

## A15 · LVM 是什么？怎么扩容？

**30 秒版**：LVM 把物理盘抽象成三层——**PV（物理卷）→ VG（卷组，空间池）→ LV（逻辑卷）**，价值是**跨盘汇池、在线扩容、快照**。扩容一条命令：`lvextend -L +10G -r /dev/vg/lv`（`-r` 连文件系统一起扩）。

**展开**：

```bash
# 建
pvcreate /dev/vdb /dev/vdc
vgcreate datavg /dev/vdb /dev/vdc
lvcreate -n datalv -L 100G datavg
mkfs.xfs /dev/datavg/datalv
mount /dev/datavg/datalv /data

# 扩（同 VG 有空间）
lvextend -L +20G -r /dev/datavg/datalv     # ★ -r = resize2fs/xfs_growfs 一起做
# VG 空间不够，加新盘
pvcreate /dev/vdd && vgextend datavg /dev/vdd
lvextend -L +50G -r /dev/datavg/datalv

# 看
pvs / vgs / lvs
df -h /data

# 快照（备份前冻结用）
lvcreate -s -n snap01 -L 5G /dev/datavg/datalv
```

**快照原理（高频追问）**：**写时复制 COW**——打快照后，原卷被修改的块会先复制到快照卷，没改的块仍共享。所以**快照卷不需要和原卷一样大**（只要装得下这期间的变更量）。用途：几秒钟冻结一个一致性视图，然后慢慢备份——解决"备份期间数据在变"的问题。

**追问**

- 「XFS 能缩容吗？」→ **不能**。XFS 只支持扩（`xfs_growfs`）；ext4 能缩但要先 `umount` → `e2fsck` → `resize2fs` → `lvreduce`，顺序错就毁数据。
- 「云上还用 LVM 吗？」→ 一般不用：云盘可以在控制台在线扩容（见 A18 云盘扩容），云盘本身三副本，LVM 的"跨盘汇池 + 硬件冗余替代"价值不大。物理机才常见 RAID + LVM 组合。
- 「LVM 元数据丢了能找回吗？」→ 元数据在 PV 头部有备份，`pvscan`、`vgchange -ay`、`vgcfgrestore` 可以尝试恢复；系统重装后挂旧盘通常 `vgchange -ay` 就能激活。

## A16 · RAID 有哪些级别？怎么选？

**30 秒版**：RAID 0 条带（快、无冗余）、RAID 1 镜像（可用容量一半、坏一块不影响）、RAID 5 单校验（n-1、坏一块、**写惩罚大**）、RAID 6 双校验（n-2、坏两块）、RAID 10 镜像+条带（50%、性能最好、**数据库首选**）。

**展开**：

| 级别 | 最少盘 | 可用容量 | 容错      | 特点 / 适用                         |
| -- | --- | ---- | ------- | ------------------------------- |
| 0  | 2   | 100% | 0       | 纯提速，坏一块全没；临时/缓存盘                |
| 1  | 2   | 50%  | 1 块     | 镜像，系统盘常用                        |
| 5  | 3   | n−1  | 1 块     | 性价比高，但**写惩罚**（读旧数据+读旧校验+计算+写两处） |
| 6  | 4   | n−2  | **2 块** | 大容量盘时代取代 5（重建时间长，双校验更安全）        |
| 10 | 4   | 50%  | 每组 1 块  | 镜像+条带，**IO 最均衡，数据库首选**          |

**RAID 5 什么时候最危险（必答）**：**重建期间**。大容量盘重建要几小时到一天，这期间如果再坏一块、或者扫到读错误（URE，不可恢复读错误），**整组数据全丢**。所以大容量场景用 RAID 6 或 RAID 10，不用 5。

**软 RAID 实操**：

```bash
mdadm --create /dev/md0 --level=5 --raid-devices=3 /dev/sd{b,c,d}
cat /proc/mdstat                # [UU_] 下划线=缺盘，[U_U] 中间坏
mdadm /dev/md0 --fail /dev/sdc --remove /dev/sdc --add /dev/sdd   # 换盘
mdadm --detail /dev/md0
```

**RAID 不是备份**（一句话收尾）：RAID 防的是**磁盘坏**，防不了误删、误格式化、勒索病毒、机房火灾——那些只能靠备份。

**追问**

- 「RAID 卡坏了怎么办？」→ 硬 RAID 卡是单点，要备同型号卡（配置存在卡上）；或者用 RAID 10 + 上层备份降低影响面。
- 「云上还用 RAID 吗？」→ 不用：云盘后端已经是三副本，RAID 的职责被平台接管了。这句话能直接体现你懂云（A15 同理）。

---

## A17 · MBR 和 GPT 有什么区别？fdisk 怎么操作？

**30 秒版**：MBR 最大支持 **2TB**、最多 4 个主分区、分区表只有一份；GPT 支持 9.4ZB、128 个分区、**头尾双份带 CRC 校验**，必须配 UEFI。大于 2T 的盘必须 GPT + `parted`。

**展开**：

|      | MBR           | GPT                             |
| ---- | ------------- | ------------------------------- |
| 最大磁盘 | **2TB**       | 9.4ZB（基本无限）                     |
| 分区数  | 4 主分区（靠扩展分区绕） | 128 个                           |
| 分区表  | 一份，坏了全丢       | **头尾两份 + CRC 校验**               |
| 引导   | BIOS + MBR    | UEFI + ESP 分区                   |
| 工具   | `fdisk`（老）    | `parted` / 新版 `fdisk` / `gdisk` |

```bash
lsblk                          # ① 先看盘（vdb 是整盘，vdb1 才是分区）
fdisk -l /dev/vdb              # ② 看分区表类型 Disklabel type: gpt / dos
fdisk /dev/vdb                 # ③ 交互：n 新建 → p 主分区 → 1 序号 → 起止扇区回车 → w 写入
parted /dev/vdb print          # ④ >2T 用 parted
#   parted /dev/vdb → mklabel gpt → mkpart primary xfs 0 100% → quit
partprobe /dev/vdb             # ⑤ 让内核重读分区表（不重启生效）
```

**追问**

- 「为什么 2T 是 MBR 的极限？」→ MBR 分区表用 32 位 LBA 记录扇区号，`2^32 × 512B = 2TB`。
- 「分完区 `lsblk` 看不到？」→ 忘了 `partprobe`；或者格式化/挂载的是 `vdb` 而不是 `vdb1`。
- 「GPT 分区表坏了能救吗？」→ 头份坏了有尾份备份，`gdisk /dev/vdb` 里用 `r` → `b` 从备份恢复，这是 GPT 相对 MBR 的实质优势。

---

## A18 · 云盘从 50G 扩到 100G，系统里还是 50G，怎么办？

**30 秒版**：**控制台扩容 ≠ 系统生效**，三步：`lsblk` 确认内核看到新容量 → `growpart /dev/vdb 1` 扩分区（**空格不是斜杠**）→ 扩文件系统：**XFS 用 `xfs_growfs /data`，ext4 用 `resize2fs /dev/vdb1`**。

**展开**：

```bash
lsblk                      # vdb 显示 100G 但 vdb1 还是 50G → 分区没扩
growpart /dev/vdb 1        # ★ 注意：盘和分区号之间是空格
lsblk                      # vdb1 变成 100G
df -h /data                # 文件系统还是 50G → 还没扩文件系统
xfs_growfs /data           # XFS 用挂载点（★不是设备名）
resize2fs /dev/vdb1        # ext4 用设备名
df -h /data                # 完成
```

**为什么 XFS 用挂载点、ext4 用设备名**：`xfs_growfs` 作用于"已挂载的 XFS 文件系统"，必须给挂载点；`resize2fs` 作用于块设备。这一点说错很常见。

**追问**

- 「能缩容吗？」→ XFS **不能**；ext4 能但要 `umount` → `e2fsck -f` → `resize2fs`（先缩文件系统）→ `lvreduce`（再缩 LV），顺序反了毁数据。云盘一般"扩容容易缩容难"，规划时留余量。
- 「扩容后应用要重启吗？」→ 不用，文件系统在线扩容。
- 「`growpart` 命令不存在？」→ 装 `cloud-utils-growpart`；也可以用 `fdisk` 删分区重建（起始扇区必须一致，风险高，不推荐）。

---

## A19 · 快照和备份是一回事吗？

**30 秒版**：不是。**快照是磁盘某时刻的块级影像（COW，秒级），用来"变更可回退"；备份是把数据导出成独立副本（mysqldump/tar），用来"数据可找回"**。快照通常和源盘在同一存储体系、只能整盘回滚；备份可异地、可精确到库表。


**展开**：

|    | 快照            | 备份           |
| -- | ------------- | ------------ |
| 本质 | 块级影像（COW）     | 数据的独立副本      |
| 速度 | 秒级            | 分钟到小时        |
| 粒度 | 整盘/整卷         | 库、表、目录、文件    |
| 存放 | 通常同存储体系       | 可异地/跨账号/可下载  |
| 恢复 | **整盘回滚，全部覆盖** | 可只恢复一个表/一个文件 |
| 用途 | 改配置前、升级前打一发   | 每日定时 + 异地容灾  |

**正确关系**：`快照解决"变更可回退"，备份解决"数据可找回"`，生产两个都要。  
**快照的隐藏用法（加分）**：不想整盘回滚时，**用快照创建一块新盘挂载到别的目录**，从里面单独捞文件——这是"快照只能整盘恢复"的正确破解法。

**追问**

- 「只做快照够不够？」→ 不够：源盘所在存储出问题、误删云盘、账号被封，快照可能一起没；而且快照不是"可离线带走的副本"。
- 「只做 mysqldump 够不够？」→ 不够：恢复慢（大库几小时）、只能恢复到备份点、系统配置和代码不在里面。要配合快照/镜像。

---

## A20 · 怎么设计"每日自动备份 + 异常告警"？

**30 秒版**：拆成**四个脚本 + crontab 错峰**：库备份（`mysqldump --single-transaction`）、代码备份（`git bundle` 或 `tar`）、失败告警（钉钉/飞书 webhook，兜底写本地日志）、**心跳检查**（检查最新备份文件年龄，超 26 小时告警）。再加三条可靠性：**校验非空/完整性、保留 N 天自动清、`flock` 防重叠**。

**展开**：

```bash
0  3 * * * /opt/ops/scripts/mysql_backup.sh    >> /opt/ops/logs/backup.log 2>&1
30 3 * * * /opt/ops/scripts/code_backup.sh     >> /opt/ops/logs/backup.log 2>&1
0  9 * * * /opt/ops/scripts/backup_heartbeat.sh >> /opt/ops/logs/heartbeat.log 2>&1
```

设计要点（每一条都能展开讲）：

| 要点       | 具体做法                                                           | 为什么                     |
| -------- | -------------------------------------------------------------- | ----------------------- |
| 一致性      | `mysqldump --single-transaction --quick --routines --triggers` | InnoDB 一致性快照、不锁表        |
| 完整性校验    | `[ -s "$file" ]` + `gzip -t "$file"`                           | 空文件/半截文件比没备份更危险         |
| 防重叠      | `flock -n /var/lock/backup.lock`                               | 大库跑不完，下一天又起一个           |
| 保留策略     | `find $dir -mtime +7 -delete`                                  | 不然备份把磁盘撑爆（反过来变成故障）      |
| 失败告警     | `curl` 钉钉/飞书 webhook，失败兜底写本地 `alarm.log`                       | 告警通道本身也会挂               |
| **心跳兜底** | 检查最新备份文件 mtime，超 26h 就告警                                       | 覆盖"cron 没跑/机器重启/脚本静默失败" |
| **恢复演练** | 定期 `restore_test.sh` 恢复到一个临时库并校验表数量                            | **备份不验证恢复 = 没备份**       |

**追问**

- 「为什么要有心跳？备份脚本不是已经会告警了吗？」→ 脚本告警只能覆盖"脚本跑了但失败"，**脚本根本没跑（cron 挂了、机器重启、被误删）时不会有人告警**。心跳是站在外部看"最新的备份有多旧"，这是唯一能兜住全链路失效的手段。**这个回答是本题的分水岭**。
- 「代码备份为什么用 `git bundle`？」→ 单文件包含完整历史和分支，`git clone xxx.bundle` 就能恢复；比 tar 打包 `.git` 更小更可靠。
- 「备份放本地同一块盘行不行？」→ 不行，盘挂了备份一起没。要异地（对象存储/另一台机），至少做到 `rsync` 到另一台。

---

## A21 · rpm 和 yum / dnf 有什么区别？Debian 系对应什么？

**30 秒版**：`rpm` 是**底层的包管理命令**（装 `.rpm` 文件，**不解决依赖**）；`yum`/`dnf` 是**上层**，从仓库在线装并**自动解决依赖**。Debian 系是 `dpkg`（底层）+ `apt`（上层），一一对应。

**展开**：

```bash
rpm -ivh pkg.rpm          # 安装（i=install v=verbose h=hash进度）
rpm -Uvh pkg.rpm          # 升级
rpm -e pkg                # 卸载（用包名不用文件名）
rpm -qa | grep nginx      # 列出已装
rpm -ql nginx             # 这个包装了哪些文件
rpm -qf /usr/sbin/nginx   # ★ 反查某个文件属于哪个包
rpm -qc nginx             # 只看配置文件
rpm -V nginx              # 校验文件是否被篡改
```

|    | rpm    | yum / dnf | dpkg     | apt      |
| -- | ------ | --------- | -------- | -------- |
| 系统 | RHEL 系 | RHEL 系    | Debian 系 | Debian 系 |
| 依赖 | **不管** | 自动        | 不管       | 自动       |
| 来源 | 本地文件   | 仓库（在线）    | 本地 .deb  | 仓库       |


**追问**

- 「内网没网怎么装？」→ 有网的机器 `yum install --downloadonly --downloaddir=/tmp/pkg 包` 下载全部依赖，拷进去 `yum localinstall *.rpm`（比裸 `rpm -ivh` 聪明，会解依赖）。
- 「怎么知道某个命令是哪个包提供的？」→ `rpm -qf $(which 命令)`；不知道文件路径时用 `yum provides "*/命令"`。
- 「CentOS 8 之后为什么用 dnf？」→ dnf 是 yum 的重写版，依赖解析更快、支持事务回滚和历史（`dnf history undo`）。命令基本兼容。

---

## A22 · yum 源是什么？怎么换源？EPEL 是什么？

**30 秒版**：yum 源就是**软件仓库地址清单**，放在 `/etc/yum.repos.d/*.repo`。国内换阿里/清华源提速：备份原文件 → 下载对应系统版本的 repo 覆盖 → `yum clean all && yum makecache`。**EPEL** 是官方源之外的社区扩展仓库，装 `htop`/`iotop`/`fail2ban` 常需要它。

**展开**：

```bash
yum repolist                    # 看有哪些源、多少包
yum makecache                   # 刷新元数据（换源后必做）
yum clean all                   # 清缓存
cat /etc/os-release             # ★ 换源前先确认版本，源必须和版本匹配

# 换阿里源（CentOS 7 示例）
cd /etc/yum.repos.d/
mkdir bak && mv *.repo bak/
curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
yum clean all && yum makecache

# EPEL
dnf install -y epel-release     # 或 yum install epel-release

# 离线
yum install --downloadonly --downloaddir=/tmp/pkg htop
```

**注意**：CentOS 7 已于 2024-06 EOL，官方源下线，需要换到 `vault.centos.org` 或直接迁 Rocky/Alma。**这条说出来说明你关注过真实的生产环境问题**。

**追问**

- 「`yum install` 报 404 / Cannot find a valid baseurl？」→ ① 版本 EOL 源没了 ② 网络/DNS 不通 ③ repo 文件里的 `$releasever` 没解析对。按这三条查。
- 「换源后会不会影响已装的软件？」→ 不会，只是改了下载地址；但**不同源的包版本可能不同**，生产换源要谨慎（同一台机器别混用多个源，容易出现依赖冲突）。

---

## A23 · 环境变量怎么用？PATH 是什么？`source` 和 `export` 区别？

**30 秒版**：`export VAR=x` 让变量**对子进程可见**；`source file`（等价 `. file`）在**当前 shell 执行**脚本，不开子进程，所以改完 `~/.bashrc` 要 `source` 才立即生效。`PATH` 是命令搜索路径，**从左到右找，先匹配先用**。

**展开**：

```bash
echo $PATH                     # /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin
export PATH=/opt/app/bin:$PATH # ★ 新路径放前面，优先匹配
env | grep PATH                # 看所有环境变量
VAR=1 bash -c 'echo $VAR'      # export 过才有值
unset VAR
```

配置文件加载顺序：

```
登录 shell：  /etc/profile → /etc/profile.d/*.sh → ~/.bash_profile → ~/.bashrc
非登录交互：  ~/.bashrc
```

所以"永久生效"写 `~/.bashrc`（个人）或 `/etc/profile.d/xx.sh`（全局），写完 `source` 一次。

**追问**

- 「装了新版本命令不生效，`which` 还是老的？」→ `which -a cmd` 看所有匹配；PATH 里旧路径在前，调整顺序或删掉旧版本；也可能是 `hash` 缓存（`hash -r` 清）。
- 「crontab 里跑脚本报 command not found？」→ cron 的 PATH 极简，脚本里用绝对路径或首行 `PATH=...`（S16）。
- 「`export` 之后新开终端为什么没了？」→ export 只影响当前 shell 及其子进程，不是永久的；永久写配置文件。

---

## A24 · 查找文件用哪些命令？find 怎么写？

**30 秒版**：`find` 实时遍历（最全最准）、`locate` 查数据库（秒出但要 `updatedb`）、`which` 找 PATH 里的命令、`whereis` 找命令和文档、`type` 区分内建/别名。

**展开**：

```bash
find /var -name "*.log" -mtime +7            # 7 天前的日志（+7=7天前，-1=24h内）
find /data -type f -size +100M               # 大于 100M 的文件（f 文件 d 目录 l 链接）
find /app -user www -perm 644 -name "*.php"  # 按属主+权限+名字
find /tmp -name "core*" -mtime +3 -delete    # 直接删（★先不带 -delete 跑一遍看清单）
find / -name "*.conf" -exec grep -l "8080" {} \;   # 对每个结果执行命令
find /data -type f -print0 | xargs -0 rm -f  # 文件名带空格时的正确写法
```

| 命令        | 找什么           | 速度 / 原理                                     |
| --------- | ------------- | ------------------------------------------- |
| `find`    | 任意条件下的文件      | 实时遍历磁盘，慢但准                                  |
| `locate`  | 按名字           | 查 `/var/lib/mlocate` 数据库，**快但需 `updatedb`** |
| `which`   | PATH 中的可执行命令  | 只搜 PATH                                     |
| `whereis` | 命令 + man + 源码 | 查数据库                                        |
| `type`    | 区分内建/别名/外部命令  | shell 内建                                    |

|                                                                                                                              |             |
| ---------------------------------------------------------------------------------------------------------------------------- | ----------- |
| **`-exec` 和 `xargs` 的区别（高频）**：`-exec` **每个结果调一次**命令（N 次进程创建）；`xargs` 把结果**攒成一批参数**一次执行（快）。但文件名含空格/换行时 xargs 会拆错，要用 \`-print0 | xargs -0\`。 |

**追问**

- 「找最近 10 分钟改过的文件？」→ `find /path -mmin -10`（分钟用 `-mmin`，天用 `-mtime`）。  
  |  |  |  |  
  | --- | --- | --- |
- 「大文件排在前面？」→ `find / -type f -size +500M -exec du -h {} \; 2>/dev/null | sort -rh | head`。
- 「find 报 Permission denied 一堆？」→ `2>/dev/null` 丢掉；用 root 跑就没有。

---

## A25 · 文本统计和压缩怎么用？tar 参数怎么记？

**30 秒版**：`cut` 取列、`sort` 排序、`uniq -c` **必须先 sort** 才有效、`wc -l` 数行。压缩看后缀：`.gz` 用 `tar -z`/`gzip`、`.bz2` 用 `-j`、`.xz` 用 `-J`、`.zip` 用 `unzip`。**tar 记法：压缩 c、解压 x、看清单 t，f 放最后**。

**展开**：

```bash
cut -d: -f1 /etc/passwd          # -d 分隔符 -f 第几列
wc -l access.log                 # 行数；-w 词数 -c 字节数
sort -t: -k3 -rn /etc/passwd     # -t 分隔符 -k 列 -n 数字 -r 倒序 -u 去重
sort ip.txt | uniq -c | sort -rn # TopN 三件套
head -n 20 / tail -n 50 / tail -n +2    # 前 20 / 后 50 / 从第 2 行开始
```

```bash
tar -zcvf all.tar.gz dir/        # 打包压缩：c 创建 z gzip v 过程 f 文件
tar -zxvf x.tar.gz -C /dst       # 解压到指定目录（x 解压）
tar -tf x.tar.gz                 # ★只看清单不解压（防覆盖、防解压炸弹）
tar -Jxf x.tar.xz                # J=xz，j=bzip2，不带字母是纯 tar
unzip x.zip -d /dst              # zip 只能用 unzip
gzip f.log                       # 生成 f.log.gz，★默认删原文件（-k 保留）
zcat f.log.gz                    # 不解压直接看
zgrep "ERROR" f.log.gz           # ★在压缩包里 grep（查历史日志神技）
```

**压缩三剑客**：`gzip` 快、`bzip2` 中等、`xz` 最省空间但最慢。日常日志用 gzip，长期归档用 xz。

**追问**

- 「`tar -zcvf` 的参数顺序？」→ 老式写法参数不能带 `-`（`tar czvf`），`f` 必须紧跟文件名且在最后；新式 `tar -zcvf` 可以，但 `f` 仍要放最后。
- 「解压前怎么确认安全？」→ 先 `tar -tf` 看清单，注意有没有 `../` 路径（解压炸弹/路径穿越）。  
  |  |  |  
  | --- | --- |
- 「日志里面全是压缩包，怎么一次搜？」→ `zgrep -r` 或 `zcat *.gz | grep`。

---

## A26 · 进程和线程有什么区别？

**30 秒版**：**进程是资源分配的基本单位**（独立地址空间、fd 表、信号处理），**线程是 CPU 调度的基本单位**（共享进程内存，只私有栈和寄存器）。线程切换轻、通信简单，但一个线程崩可能带崩整个进程；进程隔离好，但通信要走 IPC。

**展开**：

|      | 进程                | 线程            |
| ---- | ----------------- | ------------- |
| 资源   | 独立地址空间、独立 fd      | 共享进程的地址空间和 fd |
| 切换成本 | 高（换页表、刷 TLB）      | 低（同地址空间）      |
| 通信   | 管道、共享内存、socket、信号 | 直接读写共享变量（要加锁） |
| 隔离   | 一个崩不影响别的          | 一个崩整个进程挂      |
| 创建   | `fork`（写时复制）      | `clone`（共享更多） |

**Linux 的特殊之处（加分）**：Linux 不区分进程和线程，**都是用 `task_struct` 表示**，区别只是 `clone()` 时共享了哪些资源。所以 `ps -eLf` 能看到线程（LWP 列），`top -Hp` 看的是线程。

**为什么不同服务选不同模型**：

- Nginx：**多进程**（master + worker），worker 之间独立，一个崩了重启一个，稳定。
- PHP-FPM：**多进程**，每个请求一个进程，隔离好但内存开销大。
- Java 应用：**多线程**，线程池复用，切换轻但一个 OOM 全挂。
- Chrome：**多进程**，每个标签一个进程，一个页面崩不拖累其他。

**追问**

- 「僵尸进程是进程还是线程的问题？」→ 进程（父进程没 `wait` 回收子进程）；见 S10。
- 「线程数太多会怎样？」→ 上下文切换开销（`vmstat` 的 `cs` 飙高）、内存（每线程栈默认 8M 虚拟）、`pid_max` 打满。所以线程池要限制上限。

---

## A27 · 磁盘 IO 是瓶颈吗？iostat 看哪几个指标？

**30 秒版**：看 **`%util`（设备忙的比例，接近 100% 就是饱和）** 和 **`await`（平均等待时间，超过十几毫秒就慢）**，再配合 `r/s w/s`（IOPS）和 `rkB/s wkB/s`（吞吐）。`%util` 高 + `await` 高 = 磁盘扛不住。

**展开**：

```bash
iostat -x 1 3          # -x 扩展信息，每 1 秒一次共 3 次
```

| 指标              | 含义                  | 判断                          |
| --------------- | ------------------- | --------------------------- |
| `r/s` `w/s`     | 每秒读写次数（IOPS）        | 云盘普通盘约几百，SSD 几千到几万          |
| `rkB/s` `wkB/s` | 每秒读写吞吐              | 对比云盘带宽上限                    |
| `await`         | 平均每次 IO 等待（ms，含排队）  | **> 10ms 就值得关注，> 50ms 明显慢** |
| `%util`         | 设备至少有一个 IO 在处理的时间占比 | **接近 100% = 饱和**            |
| `aqu-sz`        | 平均队列长度              | 持续 > 1 说明在排队                |

配套工具：`vmstat 1`（`b` 阻塞进程数、`wa` CPU 等 IO 比例）、`iotop -o`（哪个进程在刷）、`pidstat -d 1`（每进程读写速率）。**判断链条：`wa`/`b` 高 → `iostat %util/await` 确认 → `iotop` 落到进程**。


**追问**

- 「`%util` 100% 但业务不慢，怎么回事？」→ SSD/云盘有并行能力，`%util` 只是"至少有一个 IO 在处理"，多队列设备会虚高；看 `await` 和实际业务延迟更准。这个反直觉点答出来很加分。
- 「顺序读写和随机读写差别多大？」→ 机械盘随机 IOPS 只有几百，顺序能到上百 MB/s，差几个数量级；所以数据库（随机）一定上 SSD。
- 「怎么给备份降 IO 优先级？」→ `ionice -c2 -n7 命令`（best-effort 最低优先级），或 `nice` 调 CPU 优先级配合。

---

## A28 · 新装一台服务器，你会做哪些安全加固？

**30 秒版**：**最小开放 + 身份收敛 + 补丁 + 审计 + 备份**。具体六件套：① 只开必要端口（安全组 + 防火墙两层）② SSH 加固（禁 root 直登、关密码只留密钥、改端口）③ 系统更新打补丁 ④ 装 fail2ban 防爆破 ⑤ 密钥/密码不进代码仓库 ⑥ 配好备份和告警。



**展开**：

```bash
# ① 端口收敛
ss -tlnp                          # 先看现在开了什么，不需要的停掉
firewall-cmd --list-all
# ② SSH 加固（/etc/ssh/sshd_config）
#   PermitRootLogin no
#   PasswordAuthentication no
#   Port 2222
#   AllowUsers ops
sshd -t && systemctl reload sshd   # ★改完先 -t 检查语法，用 reload 不用 restart
# ③ 补丁
dnf update -y --security           # 只打安全补丁（更可控）
# ④ 防爆破
dnf install -y fail2ban && systemctl enable --now fail2ban
# ⑤ 审计
auditd / journalctl 保留策略；登录日志 90 天
# ⑥ 时间同步 + 备份 + 监控告警
```

**还有几条容易漏的**：

- 关掉不需要的服务（`telnet`、`rsh`、无用的数据库端口）。
- `umask` 收紧、`/tmp` 加 `nodev,nosuid,noexec`。
- 数据库**不要监听 `0.0.0.0`**（我们项目 MySQL 用 `expose` 只在容器网络内可见，不映射到宿主机，这是正确的做法）。
- 应用不要用 root 跑（`User=app`）。

**追问**

- 「改完 SSH 把自己锁了怎么办？」→ 改之前开两个会话、`sshd -t` 先验证、用 reload、控制台 VNC 兜底（A10）。
- 「怎么发现机器已经被入侵？」→ 陌生公钥（`authorized_keys`）、异常 crontab、`/tmp` 下的可执行文件、异常外连（`ss -tnp`）、`lastb` 大量失败后突然有成功记录、文件被改（`rpm -Va`）。

---

## A29 · 服务器监控和告警你怎么做？

**30 秒版**：三层——**基础资源**（CPU/内存/磁盘/网络/负载）、**服务可用性**（端口/HTTP 状态码/进程数）、**业务指标**（QPS、错误率、慢查询）。工具上有 Zabbix/Prometheus + Grafana 就用现成的，没有就用 shell + curl + webhook 自建最小闭环。

**展开**：

- **采集**：`node_exporter`（Prometheus 生态）/ `zabbix_agentd`；没有 agent 就用脚本采 `top`/`free`/`df` 的数值。
- **判断**：不要只看瞬时值，**看持续时间和趋势**。例如"CPU > 80% 持续 5 分钟"比"CPU > 80%"可靠得多（避免毛刺告警）。
- **告警**：钉钉/飞书/邮件/短信，分级（P0 电话、P1 群消息、P2 日报）。**必须有兜底通道**（webhook 挂了要写本地日志 + 第二天巡检能看到）。
- **自建最小闭环**（我们项目的做法）：

```bash
# 采集 → 判断 → 推送
CPU=$(top -bn1 | awk '/Cpu\(s\)/{print 100-$8}')
[ "${CPU%.*}" -gt 80 ] && notify.sh "CPU ${CPU}%"
# HTTP 可用性
code=$(curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1/health)
[ "$code" != "200" ] && notify.sh "HTTP $code"
```

**追问**

- 「告警太多被屏蔽了怎么办？」→ 收敛：分级、聚合（相同告警 5 分钟内只发一次）、去掉无行动价值的告警（"磁盘 70%"这种先别报）。**告警疲劳比没有告警更危险**。
- 「怎么监控一个没有 exporter 的老服务？」→ 端口探活（`nc -z`）+ 日志关键字（`grep -c ERROR` 阈值）+ 进程数（`pgrep -c`）。
- 「监控和日志的区别？」→ 监控回答"现在好不好"（指标，时序），日志回答"为什么不好"（事件，明细）。两者要能互相跳转（告警里带日志链接）。

---

## A30 · 一次线上故障，你的处理流程是什么？

**30 秒版**：五步——**① 发现与确认（是不是真故障、影响面多大）② 止损（恢复服务优先，回滚/重启/切流）③ 定位根因（看日志、指标、变更记录）④ 根治（修复 + 防复发）⑤ 复盘（时间线、根因、改进项，落到人和时间）**。核心原则：**先止损再定位，不要在故障中追求完美答案**。

**展开**：

| 阶段   | 要做什么             | 关键动作                                         |
| ---- | ---------------- | -------------------------------------------- |
| ① 确认 | 分清是全局还是局部、影响多少用户 | 看监控大盘、`curl` 自测、问反馈来源                        |
| ② 止损 | **先让用户能用**       | 回滚上一次变更（最快）、重启、切流到备机、限流                      |
| ③ 定位 | 找证据链             | `变更记录`（80% 故障来自变更）→ 日志 → 指标 → 链路追踪           |
| ④ 根治 | 修代码/配置 + 防复发     | 加监控、加限制、加测试、加演练                              |
| ⑤ 复盘 | 输出文档             | 时间线（几点几分做了什么）、根因、改进项（**有 owner 有 deadline**） |

**"80% 的故障来自变更"这句话是核心洞察**：所以第一步先问"最近改了什么"——发布、配置、扩容、证书到期、上游变更。这也是为什么规范要求"变更前打快照、变更后验证"。

**追问**

- 「线上出问题，你先重启还是先查？」→ 看影响面：核心业务全挂、且有回滚手段 → **先止损（回滚/重启）**；影响可控 → 先留证据再动手。**用一句话表达"取舍"比给标准答案更好**。
- 「复盘会怎么开才不变成甩锅会？」→ 对事不对人：只讨论"系统为什么允许这个错误发生"，改进项必须是**机制**（加校验、加告警、加灰度）而不是"下次注意"。
- 「你处理过什么故障？」→ 用 STAR：现象（用户访问慢）→ 排查（`iostat` 看到 `%util` 100%）→ 根因（备份和业务抢 IO）→ 处理（错峰 + `ionice`）→ 改进（加磁盘 IO 告警）。**有真实数据就赢一半**。



---

# 第三层 · B 级常考（24 题）

## B01 · 什么是 Linux？发行版又是什么？

**30 秒版**：严格说 Linux 只是**内核**（管进程、内存、驱动、文件系统），配上 GNU 工具（bash、coreutils）和应用**打包发行**才叫操作系统，这套打包就是**发行版**。两大阵营：**Red Hat 系（rpm/yum）** 和 **Debian 系（deb/apt）**。

**展开**：

- **Red Hat 系**：RHEL（付费企业版）→ CentOS（曾免费克隆，2021 转向 Stream，2024-06 EOL）→ **Rocky / AlmaLinux**（接替者）、**OpenCloudOS**（腾讯开源）、openEuler、麒麟（信创）。
- **Debian 系**：Debian（社区鼻祖）→ **Ubuntu**（Canonical，桌面和云原生占优）。
- 查版本：`cat /etc/os-release`（推荐，通用）、`cat /etc/redhat-release`（RHEL 系）、`lsb_release -a`；内核版本 `uname -r`。

```bash
$ cat /etc/os-release
NAME="OpenCloudOS"
VERSION="9.0"
ID="opencloudos"
```

**追问**

- 「你用的什么系统？」→ 如实说"云上 OpenCloudOS 9，Red Hat 系，命令和 RHEL/CentOS 一致"，再补一句 CentOS 停更后大家往 Rocky/OpenCloudOS 迁的背景——比背列表真实。
- 「内核版本和发行版版本是一回事吗？」→ 不是。一个发行版可以跑多个内核版本（`yum update kernel`），`uname -r` 是内核，`os-release` 是发行版。


## B03 · 登录后的提示符 `[root@web01 ~]#` 怎么读？

**30 秒版**：`[用户@主机名 当前目录]提示符`。**`#` 是 root，`$` 是普通用户**；`~` 是当前用户家目录（不是根 `/`）。改主机名 `hostnamectl set-hostname`，提示符格式由 `PS1` 控制。

**展开**：

```
[root@web01 ~]#        # root，家目录是 /root
[wangjiyun@web01 /etc]$  # 普通用户，当前在 /etc
```

- **`#` vs `$` 是安全提示**：看到 `#` 就意味着这条命令有权限删库，多确认一次。误操作 root 是事故第一来源。
- `~` = `$HOME`（root 是 `/root`，普通用户 `/home/xxx`），**不是根目录**——这个送分题真有人答错。
- `PS1` 可改：`export PS1='[\u@\h \W]\$ '`（`\u` 用户、`\h` 短主机名、`\W` 当前目录、`\w` 全路径、`\$` 自动切 #/$）。

**追问**

- 「怎么区分 root 和 sudo 到 root？」→ 提示符都是 `#`；看 `$SUDO_USER` 或 `whoami`/`id` 才是准的。
- 「怎么让提示符显示 git 分支？」→ 改 `PS1` 调 `__git_ps1`，或直接用 `oh-my-bash`/`starship`；服务器上不建议折腾，保持简洁。

---

## B04 · 绝对路径和相对路径区别？为什么执行脚本要 `./x.sh`？

**30 秒版**：绝对路径从 `/` 写起（`/etc/hosts`），任何位置都有效；相对路径基于当前目录（`./x.sh`、`../log`）。`.` 当前、`..` 上级、`~` 家目录、`-` 上次所在目录。**要 `./x.sh` 是因为 PATH 里默认不含当前目录**——这是安全设计，防止当前目录里的假 `ls` 劫持你的命令。

**展开**：

```bash
/etc/nginx/nginx.conf      # 绝对路径：脚本、配置、cron 里一律用这个
./start.sh                 # 相对路径：明确"当前目录下的这个文件"
cd -                       # 回上一个目录
ls -a                      # 显示 . 开头的隐藏文件
```

**`./x.sh` 的三层解释（能说到第三层是加分）**：

1. `x.sh` 不带路径时，shell 只在 `PATH` 里找 → 找不到（当前目录不在 PATH）。
2. `./` 明确告诉 shell"在当前目录找"，于是能执行。
3. 为什么 PATH 不含 `.`：如果含，攻击者在 `/tmp` 放一个叫 `ls` 的恶意脚本，你 `cd /tmp` 后敲 `ls` 就执行了。**这是 30 年前就定下来的安全约定**。

**追问**

- 「怎么让脚本不带 `./` 也能跑？」→ 放进 PATH 里的目录（`/usr/local/bin`）并 `chmod +x`；不推荐把 `.` 加进 PATH。
- 「`sh x.sh` 和 `./x.sh` 有什么区别？」→ `sh x.sh` 用指定的解释器执行，**不需要执行权限**；`./x.sh` 用 shebang 指定的解释器，**需要 x 权限**。这个区别在 crontab 和权限排障里很实用。

---

## B05 · 查看文件内容用哪些命令？

**30 秒版**：**小文件 `cat`、大文件 `less`、实时 `tail -f`（轮转场景 `-F`）**；`head -n`/`tail -n` 取头尾；`grep` 过滤；`stat` 看元数据。

**展开**：

```bash
cat f.txt                  # 全部输出（小文件；大文件会刷屏卡终端）
less big.log               # 分页：空格翻页 /词 搜索 n下一个 q退出 G末尾
head -n 20 f               # 前 20 行
tail -n 50 f               # 后 50 行
tail -f app.log            # 实时跟踪（Ctrl+C 退出）
tail -F app.log            # ★文件被 logrotate 改名后继续跟新文件
less +F app.log            # 跟踪模式，Ctrl+C 退出跟踪后还能翻历史（比 tail -f 好用）
wc -l f                    # 行数
file f                     # 真实文件类型（不看扩展名）
stat f                     # inode、权限、三个时间戳
```

**三个时间戳（常被追问）**：

| 时间        | 含义      | 什么时候变                                |
| --------- | ------- | ------------------------------------ |
| atime     | 访问时间    | `cat`/读文件时（很多系统用 relatime 优化，不每次都更新） |
| **mtime** | 内容修改时间  | `echo >>` 写内容时（`ls -l` 默认显示这个）       |
| ctime     | 元数据变更时间 | `chmod`/`chown`/改名时（**改不了，也伪造不了**）   |

**追问**

- 「`tail -f` 和 `-F` 区别？」→ `-F` = `--follow=name --retry`，文件被轮转（改名+新建）后能自动跟到新文件；`-f` 跟的是 inode，改名后就跟丢了。**看长期日志用 `-F`**。
- 「怎么确认文件被谁改过？」→ `ctime` 是唯一无法篡改的时间戳，配合 `auditd` 或 `rpm -Va` 能查；`stat` 看三个时间是否合理。


## B07 · 怎么安全关机和重启？

**30 秒版**：`shutdown -h now` 关机、`shutdown -r +10 "公告"` 十分钟后重启（**生产姿势**，会广播通知）、`shutdown -c` 取消。**关机前先 sync 刷盘，绝不能直接断电**——写到一半的数据没落盘会导致文件系统损坏甚至数据库坏页。

**展开**：

```bash
shutdown -h now                    # 立即关机（halt）
shutdown -r +10 "10分钟后重启升级内存"   # 定时重启 + 广播给在线用户
shutdown -c                        # 取消
shutdown -r 23:00                  # 指定时间
reboot / init 6                    # 立即重启
poweroff / init 0                  # 立即关机
sync && sync                       # 手动刷盘（保险）
```

**为什么不能硬断电（必答）**：`shutdown` 会**正常停止服务 → 卸载文件系统 → 刷盘 → 断电**；硬断电等于跳过这三步，后果：① 文件系统元数据不一致（ext4 有 journal 能恢复，XFS 也要 `xfs_repair`）② 数据库未提交事务丢失/页损坏 ③ 正在写的文件变半截。

**云上的区别**：控制台"关机/重启"= 正常 ACPI 流程；**"强制重启"= 拔电**，只在系统完全卡死时用，用完要检查文件系统。

**追问**

- 「`shutdown`、`halt`、`poweroff`、`init 0` 有区别吗？」→ 现代 systemd 下基本等价（都走 `systemd-poweroff.service`），`halt` 只是停 CPU 不一定断电，`poweroff` 会发 ACPI 断电信号。
- 「重启后服务没起来怎么办？」→ `systemctl is-enabled` 查自启（A05）；`systemd-analyze blame` 看哪个服务拖慢启动；`journalctl -b -1` 看上次启动的日志。

---

## B08 · 用一句话概括 Linux 的核心特性？

**30 秒版**：**开源免费、多用户多任务、一切皆文件、稳定、命令行可脚本化**。再补两个常被忽视的：**严格区分大小写**、**扩展名无意义**（真实类型看 `file`）。

**展开**：

- **开源免费**：无授权费（云上成本优势），源码可审计可定制。
- **多用户多任务**：多账号并行，rwx + 属主属组 + SELinux 做隔离。
- **一切皆文件**：设备（`/dev/sda`）、进程信息（`/proc/1`）、内核参数（`/proc/sys/*`）都用统一的 read/write 接口。
- **稳定**：连续运行数年不重启很常见。
- **可组合**：小命令 + 管道 + shell 脚本 + systemd/Ansible 实现自动化，**这是运维效率的根源**。
- 两个细节：**大小写敏感**（`File.txt` 和 `file.txt` 是两个文件）；**扩展名只是给人看的**（`.txt` 也可以是可执行脚本，`file` 才是真相）。

**追问**

- 「这些特性对运维意味着什么？」→ 一切皆文件意味着"能用 cat 看的都能用脚本采"；可组合意味着"不用等厂商提供工具，自己拼一个"；这正是自动化监控/备份能做起来的前提。
- 「Linux 有什么缺点？」→ 硬件驱动生态弱于 Windows（新笔记本装 Linux 常缺驱动）、图形界面弱、专业软件少。诚实说缺点比全说优点可信。

---

## B09 · 身份和系统信息类命令，一口气说全？

**30 秒版**：`whoami`/`id`（我是谁）、`hostname`/`hostnamectl`、`uname -r`（内核）、`cat /etc/os-release`（发行版）、`uptime`（负载）、`date`、`nproc`/`lscpu`、`free -h`、`df -h`、`echo $?`（上条返回码）。

**展开**：

```bash
whoami                 # 当前用户
id                     # uid/gid/所属组（★权限问题第一步先 id）
hostname               # 主机名；hostnamectl set-hostname 改
uname -r               # 内核版本
uname -a               # 全部（内核/主机名/架构/时间）
cat /etc/os-release    # 发行版版本（最通用）
uptime                 # 开机时长 + 1/5/15 分钟 load
date +"%F %T"          # 2026-11-08 12:00:00（脚本打日志用）
date -d "yesterday" +%F  # 昨天（备份文件命名用）
lscpu / nproc          # CPU 详情 / 核数
free -h                # 内存
df -h                  # 磁盘
lsblk                  # 块设备树
echo $?                # 上条命令返回码：0 成功，非 0 失败
```

**`echo $?` 的实战价值**：脚本里所有失败判断都靠它——

```bash
mysqldump ... > /tmp/x.sql
if [ $? -ne 0 ]; then notify.sh "备份失败"; fi
```

返回值约定：`1` 通用错误、`2` 用法错误、`126` 无执行权限、`127` 命令找不到、`130` 被 Ctrl+C 中断、`137` 被 SIGKILL（容器 OOM 常见）、`143` 被 SIGTERM。

**追问**

- 「怎么知道机器是不是虚拟机/容器？」→ `systemd-detect-virt`（输出 kvm/docker/none）；容器里 `/proc/1/cgroup` 会有 docker 字样；`dmidecode -s system-product-name` 看厂商。
- 「`hostname` 改了为什么 `ssh` 提示符没变？」→ 要重新登录（提示符在登录时生成），或 `exec bash`。

---

## B10 · umask 是什么？

**30 秒版**：新建文件/目录的**默认权限掩码**，规则是"**从最大权限里减掉**"。默认 `umask 022` → 文件 `666-022=644`、目录 `777-022=755`。为什么文件起点是 666 不是 777：**新建文件默认不给执行权限**（安全）。

**展开**：

```bash
umask                  # 0022（第一位是特殊权限位，一般忽略）
umask -S               # 符号显示：u=rwx,g=rx,o=rx
umask 027              # 临时改：新文件 640、新目录 750（同组可读，其他人全无）
```

| umask | 新文件 | 新目录 | 适用          |
| ----- | --- | --- | ----------- |
| 022   | 644 | 755 | 默认，大多数场景    |
| 027   | 640 | 750 | 团队协作，其他人无权限 |
| 077   | 600 | 700 | 私密（密钥、个人数据） |

永久修改：`/etc/profile` 或 `~/.bashrc` 里 `umask 027`；服务进程的 umask 由 systemd 的 `UMask=` 控制。

**追问**

- 「为什么 root 的 umask 通常是 022 而普通用户是 002？」→ 有的发行版给普通用户 002（同组可写，方便协作），root 保持 022 更严格。
- 「SSH 密钥文件权限为什么必须是 600？」→ `ssh` 主动检查，权限太开（组/其他人可读）就拒绝使用（A09）；这也是 umask 077 常见于密钥目录的原因。

---

## B11 · SUID / SGID / Sticky Bit 是什么？

**30 秒版**：**SUID（4）** 执行时临时获得**文件属主**权限（`passwd` 就靠它让普通用户改 shadow）；**SGID（2）** 对目录是"新建文件继承目录属组"；**Sticky（1）** 目录下只有**属主才能删自己的文件**（`/tmp` 是 1777）。

**展开**：

```bash
ls -l /usr/bin/passwd      # -rwsr-xr-x  ← s 在小写位置=SUID 生效
ls -ld /tmp                # drwxrwxrwt  ← t = Sticky
chmod 4755 file            # 加 SUID
chmod 2770 dir             # 加 SGID（协作目录常用）
chmod 1777 /tmp            # Sticky
find / -perm -4000 -type f 2>/dev/null   # ★ 查所有 SUID 程序（安全审计必做）
```

| 位      | 数字 | 对文件     | 对目录                    |
| ------ | -- | ------- | ---------------------- |
| SUID   | 4  | 以属主身份执行 | 无意义                    |
| SGID   | 2  | 以属组身份执行 | **新建文件继承目录属组**（团队共享目录） |
| Sticky | 1  | 无意义     | **只有文件属主能删**（`/tmp`）   |

**安全视角（加分）**：SUID 是提权攻击的重点目标，`find / -perm -4000` 定期核对清单，出现来源不明的 SUID 程序就是入侵信号。这也是为什么 `nosuid` 挂载选项常配在 `/tmp` 上。

**追问**

- 「`passwd` 为什么要 SUID？」→ 普通用户改密码要写 `/etc/shadow`（只有 root 可写），靠 `passwd` 的 SUID 临时获得 root 权限，程序内部只允许改自己的密码。
- 「为什么 SGID 目录适合团队协作？」→ 任何人创建的文件都自动属于该目录的组，其他人（同组）就不会因为属组不对而读写不了。

---

## B12 · chattr 和 lsattr 是什么？（比 rwx 更高一层）

**30 秒版**：`chattr` 设置**文件系统级属性**，`+i` 不可修改（连 root 都不行）、`+a` 只能追加不能删改；`lsattr` 查看。它比 rwx 更底层，是防误删/防篡改的最后一道。

**展开**：

```bash
chattr +i /etc/passwd        # 不可变：不能改、不能删、不能改名
chattr +a /var/log/audit.log # 只允许追加（日志防篡改）
lsattr /etc/passwd           # ----i---------e----
chattr -i /etc/passwd        # 撤销
```

**经典排障题**：改密码报 `Authentication token manipulation error`、或者 `useradd` 失败——第一反应查 `lsattr /etc/passwd /etc/shadow`，是不是被 `+i` 锁了（很多安全加固脚本会这么干，接手别人的机器常踩）。

**追问**

- 「`chattr` 和 `chmod` 的区别？」→ `chmod` 是 DAC（自主访问控制，管"谁能读写"），`chattr` 是文件系统标志（管"这个文件能不能被改"），**后者连 root 也拦**。
- 「`+i` 对正在写的日志用会怎样？」→ 应用写不进去直接报错，所以日志用 `+a`（允许追加）而不是 `+i`。

---

## B13 · `/dev` 目录下都有什么？

**30 秒版**：**一切皆文件**——硬件设备在 `/dev` 里以文件形式出现，由 udev 动态生成。`ls -l` 第一列 `b` 是块设备（磁盘）、`c` 是字符设备（终端、串口）。

**展开**：

- **块设备**：`/dev/sda`（SATA/SCSI）、`/dev/nvme0n1`（NVMe SSD）、`/dev/vda`（virtio，**云主机最常见**）、`/dev/mapper/xxx`（LVM 逻辑卷）、`/dev/loop0`（回环设备，snap 镜像用）。
- **字符设备**：`/dev/tty`、`/dev/tty1`（本地终端）、`/dev/pts/0`（**每个 SSH 会话一个**）、`/dev/ttyS0`（串口）。
- **伪设备（考点）**：  
  | 设备 | 作用 |  
  |---|---|  
  | `/dev/null` | 黑洞，`cmd > /dev/null 2>&1` |  
  | `/dev/zero` | 无限输出 0 字节（`dd` 造文件） |  
  | `/dev/random` | 真随机，**熵不够会阻塞** |  
  | `/dev/urandom` | 伪随机，不阻塞（生成密钥用这个） |  
  | `/dev/full` | 模拟磁盘满（测试写失败） |  
  | `/dev/shm` | 共享内存（tmpfs，占内存） |  
  | `/dev/fd` | 指向 `/proc/self/fd` |

**主次设备号（加分）**：`ls -l` 里 `brw-rw---- 1 root disk 253, 0 /dev/vda` 的 `253, 0` 是主/次设备号——**主号对应驱动，次号对应具体设备**。`mknod` 就是手工造设备文件。

**追问**

- 「`/dev/shm` 占的是内存还是磁盘？」→ 内存（tmpfs），所以往里写大文件会吃内存，容器里默认限制 64M。
- 「为什么 SSH 会话对应 `/dev/pts/N`？」→ 伪终端，每个远程连接分配一个编号；`w`/`who` 里显示的 `pts/0` 就是这个。

---

## B14 · 磁盘设备命名有什么规律？

**30 秒版**：`sd*` = SATA/SCSI/USB（`sda` 第一块、`sdb` 第二块），`nvme*` = NVMe SSD（`nvme0n1` 第一块、`nvme0n1p1` 第一个分区），`vd*` = **虚拟磁盘（云主机）**，`loop*` = 回环设备，`/dev/mapper/*` = LVM。**分区在整盘名后加数字（`sdb1`）或 `p数字`（`nvme0n1p1`）**。

**展开**：

| 前缀                      | 类型              | 分区写法                   |
| ----------------------- | --------------- | ---------------------- |
| `sda`                   | SATA/SCSI/USB   | `sda1`、`sda2`          |
| `vda`                   | virtio（KVM/云主机） | `vda1`                 |
| `nvme0n1`               | NVMe SSD        | `nvme0n1p1`（**注意有 p**） |
| `xvda`                  | Xen 虚拟盘         | `xvda1`                |
| `mmcblk0`               | SD 卡            | `mmcblk0p1`            |
| `md0`                   | 软 RAID          | 直接当设备用                 |
| `dm-0` / `mapper/vg-lv` | LVM 逻辑卷         | 直接当设备用                 |

**为什么不能依赖盘符（重要）**：`sdb` 是**内核按发现顺序**分配的，插拔硬盘、换控制器、云盘挂载顺序变化都可能变——所以 `/etc/fstab` 必须用 **UUID**，`iscsi`/多路径要用 `/dev/disk/by-id/`。这是 S17 的核心理由。

```bash
ls -l /dev/disk/by-uuid/        # UUID → 设备 的映射
lsblk -f                        # 一次看全：设备、UUID、文件系统、挂载点
blkid                           # 同上
```

**追问**

- 「`lsblk` 显示 `vdb` 没分区，能直接格式化吗？」→ 可以（`mkfs.xfs /dev/vdb` 整盘用），云上很常见；但**有分区表的盘不能直接格式化整盘**，会覆盖分区表。
- 「怎么确认一块盘是 SSD 还是机械？」→ `lsblk -d -o name,rota`（`rota=1` 机械、`0` SSD）；云盘看不出来，只能看云控制台的盘类型。

---

## B15 · 进程优先级怎么调？nice 值范围？

**30 秒版**：`nice` 值 **-20（最高优先级）到 19（最低）**，默认 0。启动时 `nice -n 10 cmd`，运行中 `renice -n 5 -p PID`。**普通用户只能调高 nice 值（降优先级），只有 root 能设负值（提优先级）**。

**展开**：

```bash
nice -n 10 /opt/backup.sh        # 以低优先级启动（备份不抢业务 CPU）
renice -n 5 -p 1234              # 改运行中的进程
renice -n 5 -g 1234              # 改进程组
ps -eo pid,ni,cmd --sort=-ni | head   # 看谁优先级最高
top 里 NI 列
```

配套 IO 优先级：`ionice -c2 -n7 cmd`（`-c` 调度类，`-n` 0-7 优先级，7 最低）。**备份脚本 + `nice`/`ionice` 是防"备份拖垮业务"的标准组合**。

**追问**

- 「nice 值改了 CPU 占用会立刻降吗？」→ 不会。nice 只是**调度权重**，CPU 空闲时低优先级进程照样能用满；只有在争抢时才有意义。
- 「为什么备份要降优先级？」→ 备份是**可延迟**任务，业务是**不可延迟**的；用 `nice`/`ionice` 让内核在争抢时先满足业务。这是我们项目里"备份和业务抢 IO"的解法之一（另一个是错峰）。

---

## B16 · at 和 cron 怎么选？

|                                                            |                                                                  |
| ---------------------------------------------------------- | ---------------------------------------------------------------- |
| **30 秒版**：`cron` 管**周期性**任务，`at` 管**一次性**延时任务。\`echo "cmd" | at now + 30 minutes` 三十分钟后执行一次，`atq` 看队列，`atrm N`删除。依赖`atd\` 服务。 |

**展开**：

```bash
systemctl status atd                  # 先确认服务在
echo "/opt/app/restart.sh" | at now + 30 minutes
at 22:00                              # 交互式输入，Ctrl+D 提交
atq                                   # 待执行任务列表
atrm 3                                # 删除 3 号
at -l                                 # 同 atq
```

- at 的输出默认**当邮件发给用户**，脚本里要自己重定向（`>> log 2>&1`）。
- 权限控制：`/etc/at.allow`（白名单，优先）、`/etc/at.deny`。
- systemd 版：`systemd-run --on-active=10min /path/x.sh`（`--on-calendar` 指定时间），容器化环境更常用。

**追问**

- 「为什么 crontab 里不能写 `at`？」→ 可以写但不合理；一次性任务应该用 `at` 或 `systemd timer`，cron 是周期语义。
- 「`at` 任务没执行怎么查？」→ `systemctl status atd`、`journalctl -u atd`、`/var/log/cron`（部分系统记录 at）；还有时区问题（`date` 和 `timedatectl` 要一致）。

---

## B17 · 计划任务可以写在哪些地方？有什么区别？

**30 秒版**：**① `crontab -e`**（当前用户，五段无用户列）、**② `/etc/crontab`**（系统级，**多一个用户字段**）、**③ `/etc/cron.d/*`**（同 ②，一个任务一个文件，**推荐**）、**④ `/etc/cron.{hourly,daily,weekly,monthly}/`**（只放脚本，不写时间）。

**展开**：

| 位置                   | 格式               | 特点                                     |
| -------------------- | ---------------- | -------------------------------------- |
| `crontab -e`         | 五段 + 命令          | 每用户一份，存 `/var/spool/cron/用户名`          |
| `/etc/crontab`       | 五段 + **用户** + 命令 | 系统级，忘记写用户会把命令当用户名                      |
| `/etc/cron.d/xxx`    | 同 `/etc/crontab` | ★ 推荐：随包分发、可版本控制、单文件管理                  |
| `/etc/cron.daily/` 等 | 只丢脚本（要 +x）       | 由 `run-parts`/anacron 整目录执行，**没有时间字段** |

**最常见坑**：在 `/etc/cron.d/xxx` 里按用户 crontab 的五段格式写 → 少写用户列 → 报错或静默不执行。**判断方法**：看文件在哪，`/etc/cron.d` 和 `/etc/crontab` 必须有用户列。

**追问**

- 「anacron 有什么不同？」→ cron 假设机器一直开着，**关机期间错过的任务就不跑了**；anacron 会记录"上次执行时间"，开机后补跑（适合笔记本/不常开的机器）。`/etc/cron.daily` 在 CentOS 7+ 由 anacron 驱动。
- 「怎么验证 cron 真的跑了？」→ `/var/log/cron`（CentOS）或 `journalctl -u crond`；`systemctl status crond`；脚本里打 `date` 时间戳。

---

## B18 · 终端常用快捷键有哪些？

**30 秒版**：`Ctrl+C` 中断（SIGINT）、`Ctrl+Z` **挂起**（进程还在）、`Ctrl+D` **EOF/退出**、`Ctrl+L` 清屏、`Ctrl+R` **搜历史**、`Ctrl+A/E` 行首行尾、`Ctrl+U/K` 删前/删后。

**展开**：

| 键                   | 作用          | 说明                          |
| ------------------- | ----------- | --------------------------- |
| `Ctrl+C`            | 中断当前命令      | 发 SIGINT，进程被杀               |
| `Ctrl+Z`            | 挂起到后台       | 发 SIGTSTP，进程**还在**，`fg` 可恢复 |
| `Ctrl+D`            | 发送 EOF      | 空行时=退出登录；`cat > f` 时=结束输入   |
| `Ctrl+L`            | 清屏          | 等于 `clear`（内容还在滚动区）         |
| `Ctrl+R`            | 反向搜历史       | 输入关键字，再按继续往前找               |
| `Ctrl+A` / `Ctrl+E` | 行首 / 行尾     | 比按 Home/End 稳               |
| `Ctrl+U` / `Ctrl+K` | 删光标前 / 后    | `Ctrl+U` 清整行很常用             |
| `Ctrl+W`            | 删前一个词       |                             |
| `Ctrl+S` / `Ctrl+Q` | 冻结 / 解冻屏幕输出 | 误按 Ctrl+S 会"卡住"，按 Ctrl+Q 恢复 |

历史命令：

```bash
history            # 历史列表（默认退出时才写 ~/.bash_history）
!!                 # 上一条命令（忘 sudo：sudo !!）
!$                 # 上一条命令的最后一个参数（等价 Alt+.）
!ssh               # 最近一条以 ssh 开头的
history | grep backup
```

**追问**

- 「`Ctrl+C` 和 `Ctrl+Z` 的区别？」→ C 是**杀**，Z 是**挂起**（进程还在内存里，`jobs` 能看到，`fg` 能拉回来）。这是最高频的对比题。
- 「误按 `Ctrl+S` 终端像卡死了？」→ 流控冻结了输出，按 `Ctrl+Q` 恢复。
- 「history 能看到同事会话的命令吗？」→ 默认不能（各写自己的 `~/.bash_history`，且退出时才落盘，多个会话会互相覆盖）；要审计得靠 `auditd`/`journalctl`。

---

## B19 · `ls -l` 输出的每一列是什么？

**30 秒版**：`①权限 ②SELinux标记 ③链接数 ④属主 ⑤属组 ⑥大小 ⑦时间 ⑧文件名`。**目录的链接数 − 2 = 子目录数**；目录显示 4096 是目录本身占的元数据空间，不是内容总大小。

**展开**：

```
-rw-r--r--. 1 root root 1024 Oct 30 10:00 app.conf
①         ② ③ ④    ⑤   ⑥    ⑦           ⑧
```

- ① 10 位：第 1 位是类型（`-` 普通 `d` 目录 `l` 链接 `b` 块设备 `c` 字符设备 `s` socket `p` 管道），后 9 位是 rwx 三组。
- ② 位置上的 `.` = 有 SELinux 上下文；`+` = 有 ACL；什么都没有 = 两者都无。
- ③ **链接数**：文件是硬链接数；目录 = 自身 `.` + 父目录里的一条记录 + 每个子目录的一条 → **子目录数 = 链接数 − 2**。
- ⑥ 目录显示 4096：目录本身是"文件名 → inode"的映射表，4096 是这张表占的空间，**不是目录里文件的总大小**（要看 `du -sh`）。
- ⑦ 默认 **mtime**；`ls -l --time=atime` / `--time=ctime` 可切。

**追问**

|   |   |   |
| - | - | - |

|  |  |  |
| --- | --- | --- |
- 「怎么数一个目录下有几个子目录？」→ `ls -l | grep -c "^d"`，或 `find . -maxdepth 1 -type d | wc -l`，或看链接数减 2。
- 「文件名颜色代表什么？」→ 蓝=目录、绿=可执行、红=压缩包/失效链接、青=软链接；由 `LS_COLORS` 控制。
- 「`ls -l` 总大小和 `du` 为什么不一样？」→ `ls` 显示的是**文件大小（apparent size）**，`du` 是**实际占用的块**（稀疏文件、小文件块对齐差异）。

---

## B20 · 中文乱码怎么解决？Windows 文件在 Linux 里报错怎么办？

**30 秒版**：三处编码要一致——**系统 locale、文件本身编码、客户端终端编码**。`locale` 看当前，`export LANG=zh_CN.UTF-8` 临时改，`/etc/locale.conf` 永久。文件是 GBK 就 `iconv` 转。Windows 文件报 `^M` 是 **CRLF 换行符**，`dos2unix` 转。

**展开**：

```bash
locale                          # 看 LANG / LC_ALL
locale -a | grep -i zh          # 有没有中文 locale
localedef -i zh_CN -f UTF-8 zh_CN.UTF-8   # 没有就生成
file -i 文件名                   # 猜文件编码（charset=utf-8 / iso-8859-1）
iconv -f GBK -t UTF-8 old.txt -o new.txt  # 转码
dos2unix x.sh                   # CRLF → LF
sed -i 's/\r$//' x.sh           # 没装 dos2unix 时的替代
```

**CRLF 的典型报错**：`/bin/bash^M: bad interpreter: No such file or directory`——因为 `\r` 被当成了解释器名字的一部分。**这是 crontab 三坑之一**（S16）。

**追问**

- 「终端里显示乱码但文件本身没问题？」→ 是**客户端**（Xshell/SecureCRT/Windows Terminal）的编码不是 UTF-8，改会话编码即可——"乱码不在服务器，在客户端"是常见真相。
- 「数据库里的中文乱码？」→ 建库/表/连接三处字符集必须都是 `utf8mb4`（MySQL 的 `utf8` 存不了 emoji）；连接串要加 `charset=utf8mb4`。

---

## B21 · 误删 `rm -rf` 了，数据还能恢复吗？

**30 秒版**：**看文件系统**——ext4 有概率用 `extundelete`/`ext4magic` 捞，**XFS 基本没戏**；云盘最好的路是**快照回滚**。第一原则是**立刻停止一切写入**（最好关机或把盘挂到别的机器），因为删掉只是标记块空闲，**新数据覆盖就真没了**。

**展开**：

- 原理：`rm` 做的事是 **目录项删除 + inode 链接数减 1**，数据块内容还在，只是被标记为"可用"。一旦有新写入覆盖这些块，就永久丢失。
- 应急步骤：① 立刻停止写入（服务停掉、别 logrotate、别跑备份）② 用 live CD / 把盘挂到另一台机器 ③ `extundelete /dev/vdb1 --restore-all`（ext4）④ 云环境直接从快照创建新盘捞文件。
- **更重要的一半是预防**（这题真正考的是认知）：

```bash
alias rm='rm -i'                  # 交互确认
rm -rf "${dir:?}/"                # ★ :? 变量为空就报错退出
[ -n "$dir" ] || exit 1           # 脚本里先判空
# 危险操作走"移到回收站目录"而不是 rm
mv /data/x /data/.trash/$(date +%s)_x
```

**追问**

- 「为什么 `rm -rf $dir` 是灾难？」→ `$dir` 为空时命令变成 `rm -rf /`。所以生产脚本里删变量路径必须 `set -u` + `${dir:?}` 双保险。
- 「有回收站吗？」→ Linux 命令行没有；可以用 `trash-cli`、或规范里要求"删之前 mv 到回收目录，7 天后再清"。

---

## B22 · root 密码忘了怎么办？

**30 秒版**：**云服务器先用控制台 VNC / 重置密码功能**（最贴实际）。物理机走 GRUB：重启在菜单按 `e` → 内核行加 `rd.break` → `Ctrl+x` → `mount -o remount,rw /sysroot` → `chroot /sysroot` → `passwd root` → **`touch /.autorelabel`** → 重启。

**展开**：

```bash
# GRUB 菜单按 e，找到 linux 行末尾加：
rd.break
# Ctrl+X 启动，进入 switch_root 提示符后：
mount -o remount,rw /sysroot
chroot /sysroot
passwd root
touch /.autorelabel      # ★SELinux 开启时必须，否则改完密码登不上
exit
reboot
```

**为什么必须 `touch /.autorelabel`**：`passwd` 修改 `/etc/shadow` 后，SELinux 上下文可能不对；不重新打标签，登录时 PAM 读 shadow 被 SELinux 拒绝，表现就是"密码改了还是登不上"。**这个细节答出来就是加分项**。

**追问**

- 「`rd.break` 和 `init=/bin/bash` 区别？」→ `rd.break` 在 initramfs 阶段就断下来（`/sysroot` 还是只读，要 remount），更安全；`init=/bin/bash` 直接进 shell 但没有 systemd 环境，很多命令不可用。
- 「怎么防止别人用这招改密码？」→ 给 GRUB 设密码（`grub2-setpassword`）、BIOS 设开机密码、磁盘加密（LUKS）——物理接触的机器无法完全防，这是物理安全的边界。

---

## B23 · `ifconfig` 找不到？`ip` 命令怎么用？

**30 秒版**：新系统默认不装 `net-tools`，用 **`ip` 命令族**：`ip a`（地址）、`ip link`（网卡）、`ip r`（路由）、`ip neigh`（ARP）。配 IP 用 `nmcli`（RHEL 系）或 `netplan`（Ubuntu）。

**展开**：

```bash
ip a                       # = ip addr show，看所有网卡和地址
ip a show eth0
ip link set eth0 up/down   # 启停网卡
ip r                       # 路由表（default via 是默认网关）
ip route add default via 172.19.0.1
ip neigh                   # ARP 表
ip -s link                 # 网卡收发统计（丢包/错误）
```

| 老命令                | 新命令                   |
| ------------------ | --------------------- |
| `ifconfig`         | `ip a`                |
| `ifconfig eth0 up` | `ip link set eth0 up` |
| `route -n`         | `ip r`                |
| `arp -n`           | `ip neigh`            |
| `netstat -tlnp`    | `ss -tlnp`            |

配 IP（RHEL/CentOS 8+）：

```bash
nmcli con show
nmcli con mod eth0 ipv4.method manual ipv4.addresses 172.19.0.100/24 \
      ipv4.gateway 172.19.0.1 ipv4.dns "223.5.5.5 8.8.8.8"
nmcli con up eth0
```

老式 ifcfg 里 **`ONBOOT=yes` 不能漏**——漏了重启后网卡不激活，直接断网（经典事故）。

**追问**

- 「云服务器能自己改内网 IP 吗？」→ **不能**，内网 IP 是 VPC 分配的，改了和云平台对不上直接失联；公网 IP 是控制台映射（EIP），`ip a` 里根本看不到，这是正常的（见 C05）。
- 「改完 IP 怎么验证？」→ 三板斧：`ip a`（地址在）→ `ip r`（默认路由在）→ `ping 网关` → `ping 223.5.5.5` → `ping 域名`（验 DNS）。

---

## B24 · Linux 有哪几种文件类型？`file` 命令有什么用？

**30 秒版**：七种——`-` 普通文件、`d` 目录、`l` 软链接、`b` 块设备、`c` 字符设备、`s` socket、`p` 命名管道。**看类型用 `ls -l` 第一位或 `file`**，不看扩展名。

**展开**：

| 符号  | 类型           | 例子                        |
| --- | ------------ | ------------------------- |
| `-` | 普通文件（文本/二进制） | `/etc/hosts`、`/bin/ls`    |
| `d` | 目录           | `/etc`                    |
| `l` | 符号链接         | `/usr/bin/awk → gawk`     |
| `b` | 块设备          | `/dev/vda`                |
| `c` | 字符设备         | `/dev/tty`、`/dev/null`    |
| `s` | socket       | `/run/mysqld/mysqld.sock` |
| `p` | 命名管道 FIFO    | `mkfifo /tmp/f`           |

```bash
ls -l /etc/hosts          # 第一位 -
file /bin/ls              # ELF 64-bit LSB executable
file app.conf             # ASCII text
file noext                # 没有扩展名也能认出是 shell script
stat -c '%F' /etc         # 直接输出类型名 directory
```

**为什么扩展名不重要**：Linux 内核只看文件内容和权限位；`chmod +x script.txt` 之后它就能执行。**这是和 Windows 最大的理念差异之一**，也是"上传 `.jpg` 其实是 webshell"这类攻击能成立的原因（所以要查文件头/用 `file` 验类型）。

**追问**

- 「socket 文件是什么？」→ 进程间通信的端点（Unix domain socket），比如 `mysql.sock`——本地连 MySQL 走 socket 比 TCP 快，`mysql -S /run/mysqld/mysqld.sock`。
- 「怎么找出系统里所有 socket 文件？」→ `find / -type s 2>/dev/null`；占空间按大小找用 `find / -type f -size +1G`。

---

# 第四层 · C 级加分（16 题）

## C01 · 云主机资源不高却很卡？%st 是什么？

**30 秒版**：看 `top` 的 **`%st`（steal）**——hypervisor 把本该给你的 CPU 时间片"偷"给了同宿主机的其他虚拟机，是**云上超卖/邻居效应**的直接证据。持续 > 5% 就说明抢不到 CPU，要换规格或错峰。

**展开**：

- `%st` 是虚拟化层暴露的指标，物理机永远是 0。
- 两种典型：① 共享型实例邻居压力大 ② **突发性能实例（T 系列）CPU 积分耗尽**——后者表现也是"资源看着不高却卡死"，要去控制台看积分曲线。
- 处理：换独享型规格、错峰、或找云厂商。
- **加分答法**：云主机排查比物理机多一步——**先排除平台因素（steal、积分、宿主机迁移、云盘限流），再查系统内**。这一句直接体现云上经验。

**追问**

- 「`%st` 高能自己解决吗？」→ 系统内无解（不是你的进程问题），只能换规格/换可用区/联系厂商。

---

## C02 · IO 打满怎么定位到具体进程？

**30 秒版**：`iostat -x 1` 确认设备级饱和（`%util`、`await`）→ **`iotop -o`** 按进程看实时读写，一步定位 → 没装 iotop 用 `pidstat -d 1`。然后判断是业务正常、备份抢 IO，还是异常程序。

**展开**：

```bash
iostat -x 1              # 先确认设备级：%util≈100 饱和，await 高=响应慢
iotop -o                 # ★ 只显示正在 IO 的进程
iotop -oPa               # -P 按进程汇总 -a 累计
pidstat -d 1             # 每进程 kB_rd/s kB_wr/s（sysstat 包）
cat /proc/<pid>/io       # 单进程累计读写
lsof +D /data            # 哪个进程打开了这个目录（慢）
```

**典型结论**：**备份脚本和业务抢 IO**——凌晨 `mysqldump` + `gzip` 期间 `%util` 拉满、网站变慢；对策是错峰调度 + `ionice` 降优先级 + 备份先写到另一块盘。

**追问**

- 「`iotop` 装不上怎么办？」→ `pidstat -d 1`（`sysstat` 包）等价；或 `for p in /proc/[0-9]*; do cat $p/io; done` 手搓。
- 「除了读写还有什么值得看？」→ `fsync`（数据库落盘）、`bi/bo`（`vmstat`）、`await`（比 `%util` 更能反映真实延迟）。

---

## C03 · 带宽被占满 / 网速慢怎么定位？

**30 秒版**：`sar -n DEV 1` 看网卡总速率 → **`iftop`** 看是哪条连接在传 → **`nethogs`** 落到具体进程 → 判断是业务正常、日志/备份同步，还是异常外传（挖矿、被当跳板）。

**展开**：

```bash
sar -n DEV 1 3           # 每块网卡的 rxkB/s txkB/s（也能回看历史：sar -n DEV -f /var/log/sa/sa08）
iftop -nP                # 按连接看实时流量，显示端口
nethogs                  # ★ 按进程看流量（比 iftop 更直接）
ss -tn                   # 连接数视角
ethtool eth0             # 网卡协商速率（Speed: 1000Mb/s）
```

**单位换算（送分题）**：运营商说"100M 宽带"是 **100 Mbps**，除以 8 = **12.5 MB/s**。所以"下载只有 12.5MB/s 是不是被限速"——不是，这就是满速。

**追问**

- 「云主机带宽被限流怎么发现？」→ 云监控里带宽打满 + 系统里 `sar` 也打满，但 `iftop` 加起来不到预期 → 是**云平台带宽上限**（按量/固定带宽），不是系统问题。
- 「怎么快速找出谁在狂发数据？」→ `nethogs` 一眼看到进程 → `lsof -p` 看它连了谁 → 可疑就断网保留证据（C01/A28）。

---

## C04 · Shell 是什么？bash 和 sh 有什么区别？

**30 秒版**：Shell 是**用户和内核之间的命令解释器**——你敲的命令它翻译成系统调用。`bash` 是 Linux 默认（sh 的增强版，支持数组、`[[ ]]`）；`sh` 是 POSIX 标准子集；`zsh` 补全更强（macOS 默认）。脚本第一行 `#!/bin/bash`（shebang）指定解释器。

**展开**：

```bash
echo $SHELL              # 当前 shell
cat /etc/shells          # 系统可用的 shell
chsh -s /bin/bash        # 换默认 shell
#!/bin/bash              # shebang：指定解释器
#!/bin/sh                # POSIX 子集，写了 bash 特性会报错
```

**为什么要写 shebang（重要）**：不写的话，`./x.sh` 会用当前 shell 执行；**crontab 和 systemd 环境下可能用 `/bin/sh`（dash），数组、`[[ ]]`、`function` 全部报错**——"本地跑得好，cron 里就挂"经常是这个原因。

**追问**

- 「`source x.sh` 和 `bash x.sh` 区别？」→ `source` 在**当前 shell** 执行（变量、函数留在当前会话），`bash` 起**子进程**（变量不回流）。所以 `source` 能用来加载环境变量。
- 「脚本里 `set -e`、`set -u`、`set -o pipefail` 干什么？」→ `-e` 出错即停（但注意管道/条件语句的坑）、`-u` 用未定义变量报错（防 `rm -rf $dir` 惨案）、`pipefail` 管道中任一环失败即失败。**备份脚本里 `set -uo pipefail` 不带 `-e` 是有意的**——要自己处理错误才能发告警。

---

## C05 · 公网 IP、私网 IP、NAT 怎么区分？

**30 秒版**：私网段必背三段（RFC1918）——**`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`**，只在局域网有效；其余是公网。**NAT** 让多台内网机共享一个公网 IP 出网（改源 IP + 端口，回包改回来）。云上 `ip a` 看到的是私网 IP，**公网 IP 在控制台映射，网卡上看不到**。

**展开**：

- 云上对应关系：VPC 内互通用私网 IP；对外访问经 EIP（弹性公网 IP）DNAT 进来、SNAT 出去。
- `curl ifconfig.me` 看**出网公网 IP**（和 `ip a` 里的不一样是正常的）。
- **最佳实践**：同 VPC 的机器之间**走私网 IP**互通——不走公网、不花公网带宽、延迟更低。
- 容器的 IP（`172.17.0.0/16`）也是私网，宿主机做 NAT。

**追问**

- 「两台服务器互相 ping 公网 IP 不通？」→ 公网流量要绕出云平台再 DNAT 回来，可能被安全组/回环策略拦；**应该用私网 IP**。
- 「EIP 的好处？」→ 独立资源，可解绑/绑定到任意实例，换机器不换 IP（做 DNS 切换、故障迁移的关键）。
- 「怎么判断一个 IP 是不是私网？」→ 看前三段是否落在三段私网范围内；`ipcalc 172.19.0.5/24` 也能算。

---

## C06 · DNS 解析怎么查？`/etc/hosts` 和 `resolv.conf` 什么关系？

**30 秒版**：解析顺序是 **`/etc/hosts` 优先 → `/etc/resolv.conf` 里的 nameserver**。查用 `dig`/`nslookup`/`host`；`dig +trace` 能看到完整递归过程。改 DNS 就改 `resolv.conf`（但 NetworkManager 会覆盖，要改网卡配置或 `nmcli`）。

**展开**：

```bash
cat /etc/resolv.conf            # nameserver 223.5.5.5
cat /etc/nsswitch.conf | grep hosts   # hosts: files dns  ← 决定了 hosts 优先
dig example.com                 # 完整答案（含 TTL、A 记录）
dig +short example.com          # 只要 IP
dig @8.8.8.8 example.com        # 指定 DNS 服务器查（排除本地 DNS 问题）
dig +trace example.com          # 从根域开始逐级查（排查解析链路）
nslookup example.com
host example.com
getent hosts example.com        # ★按 nsswitch 顺序查（和程序实际行为一致）
```

**排查套路**：域名不通但 `ping 223.5.5.5` 通 → 就是 DNS。三步：`cat /etc/resolv.conf` 看有没有 nameserver → `dig @223.5.5.5 域名` 直连公共 DNS 试 → `dig @内网DNS 域名` 对比，定位是本地配置还是 DNS 服务器的问题。

**追问**

- 「为什么改了 `/etc/resolv.conf` 重启就丢？」→ NetworkManager/systemd-resolved 会重写它；要改 `/etc/sysconfig/network-scripts/ifcfg-*` 的 `DNS1=` 或 `nmcli con mod ... ipv4.dns`。
- 「容器里 DNS 怎么配？」→ Docker 默认把宿主机的 resolv.conf 拷进容器；自定义网络里的容器用内嵌 DNS（127.0.0.11）解析服务名。

---

## C07 · tcpdump 怎么用？什么时候需要抓包？

**30 秒版**：`tcpdump -i eth0 -nn port 80` 抓包，`-w` 存文件用 Wireshark 分析，`-r` 读文件。用&#x5728;**"三层都通但就是不对"**&#x7684;时候：包到底发没发出去、对方回没回、回的什么。

**展开**：

```bash
tcpdump -i eth0 -nn port 80                 # -nn 不解析主机名和端口名（快）
tcpdump -i any -nn host 1.2.3.4 and port 3306
tcpdump -i eth0 -nn -c 100 -w /tmp/x.pcap   # 抓 100 个包存文件
tcpdump -r /tmp/x.pcap -nn                  # 读文件
tcpdump -i eth0 -nn 'tcp[tcpflags] & tcp-syn != 0'   # 只看 SYN（判断握手到没到）
tcpdump -i eth0 -nn -A port 80              # -A 以 ASCII 显示内容（看 HTTP 明文）
```

**典型用途**：

- 有 SYN 无 SYN+ACK → 对端没监听或被拦（防火墙/安全组）。
- 有请求无响应 → 服务端卡住或回包被丢。
- 大量重传（`tcp retransmission`）→ 网络质量差/丢包。

**追问**

- 「生产上抓包要注意什么？」→ ① 加过滤条件（不然抓全量直接把磁盘和 CPU 打满）② `-c` 限制数量 ③ `-s 0` 抓完整包（默认会截断）④ 敏感数据（密码/token）会明文落在文件里，注意保管。
- 「容器里怎么抓？」→ `docker exec` 进容器抓，或在宿主机抓 `veth` 网卡 / `-i any`。

---

## C08 · curl 和 wget 有什么区别？

**30 秒版**：`curl` 主打**与 URL 交互/调 API**（支持各种 method、header、多种协议），`wget` 主打**下载文件**（递归下载、断点续传是强项）。**监控脚本判活一律用 `curl -w '%{http_code}'`**，因为 ping 通不代表 HTTP 活着。

**展开**：

```bash
# curl
curl -I https://x.com                       # 只看响应头（状态码/Server）——测服务通不通第一命令
curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" URL   # 静默 + 状态码 + 耗时（脚本用）
curl -X POST -H "Content-Type: application/json" -d '{"k":1}' http://x/api
curl -L URL                                 # 跟随重定向
curl -v URL                                 # 完整请求响应过程（排障）
curl -m 10 URL                              # 超时 10 秒（★脚本必须加，否则卡死）
curl --resolve x.com:443:1.2.3.4 https://x.com   # 不改 hosts 指定 IP（CDN 切换验证）

# wget
wget URL                                    # 下载到当前目录
wget -O name.tar.gz URL                     # 指定文件名
wget -c URL                                 # 断点续传
wget -q --spider URL                        # 只探测不下载
wget -r -np -k URL                          # 递归镜像整站
```

**挂项目的一句话**：监控脚本用 `curl -s -o /dev/null -w '%{http_code}' -m 5` 判非 200 就告警——比 `ping` 靠谱得多，因为 `ping` 只测到 IP 层。

**追问**

- 「`curl` 返回 `000` 什么意思？」→ **连接都没建立**（网络不通、DNS 失败、证书错误、超时），配 `-v` 看具体原因。
- 「`curl` 返回 200 但内容是错的？」→ 状态码只代表"服务回了一个正常响应"，业务对不对要看内容/关键字段；监控要做**内容探活**（grep 关键字）。

---

## C09 · 为什么服务器都用 Linux，而不是 Windows Server？

**30 秒版**：**免费开源（无授权费）、资源占用低（2G 内存能跑全套）、稳定（数年不重启）、命令行 + 脚本适合批量自动化、权限体系严格**。但 Windows 在 AD 域、.NET/SQL Server、桌面办公场景仍有优势——**问题不是谁好，是场景匹配**。

**展开**：

| 维度  | Linux                           | Windows Server        |
| --- | ------------------------------- | --------------------- |
| 成本  | 免费（开源）                          | 授权费（按核心/用户）           |
| 资源  | 无 GUI，占用低                       | GUI 占内存，2G 跑不动        |
| 稳定  | 数年不重启                           | 需要定期重启打补丁             |
| 自动化 | shell + 管道 + Ansible            | PowerShell（在进步，生态弱）   |
| 生态  | Nginx/MySQL/Redis/Docker/K8s 原生 | .NET、SQL Server、AD 域强 |
| 权限  | rwx + 属主 + SELinux              | ACL + 域账户             |

**技术支持岗的关键补充**：真实环境常是**Linux 服务器 + Windows 客户端**混合，AD 域、共享盘、打印机、Office 问题都得会一点——"两边都能排查"才是这个岗位的稀缺性。

**追问**

- 「Linux 有什么不如 Windows 的？」→ 硬件驱动生态（新笔记本缺驱动）、专业软件（Adobe/部分 CAD）、图形化管理工具。诚实说缺点比全说优点可信。
- 「你了解 AD 域吗？」→ 知道概念：集中管理用户和计算机、域控做认证、组策略下发；技术支持日常会遇到"加域/退域/密码策略/共享盘权限"问题（我们题库 `07` 里有 AD 相关条目）。

---

## C10 · ext4 和 XFS 有什么区别？怎么选？

**30 秒版**：**XFS 适合大文件、高并发、大容量，只能扩不能缩**（RHEL/CentOS 默认）；**ext4 通用、小文件友好、能缩容**（Debian/Ubuntu 默认）。云盘数据盘一般 XFS，需要灵活缩容的场景用 ext4。

**展开**：

|        | ext4          | XFS                           |
| ------ | ------------- | ----------------------------- |
| 默认系统   | Debian/Ubuntu | RHEL/CentOS/Rocky/OpenCloudOS |
| 大文件性能  | 一般            | **好**（B+树、延迟分配、并行分配组）         |
| 小文件    | 好             | 一般                            |
| 缩容     | 支持（要 umount）  | **不支持**                       |
| 扩容     | `resize2fs`   | `xfs_growfs`（在线）              |
| 元数据校验  | 有 journal     | 有（更依赖日志重放）                    |
| 修复     | `e2fsck`      | `xfs_repair`                  |
| 最大文件系统 | 1EB           | 8EB                           |

**追问**

- 「XFS 不能缩容，规划时怎么办？」→ 留余量 + 用 LVM（A15）把"缩"的灵活性放在 LV 层（`lvreduce` 前先缩文件系统，但 XFS 仍不能缩 → 所以需要缩容的场景一开始就选 ext4 或 LVM+ext4）。
- 「`df` 里 XFS 的可用空间为什么比 ext4 少一点？」→ 元数据/日志区预留不同；XFS 用 `xfs_info` 看真实 block 分布。

---

## C11 · 怎么看硬件信息？CPU / 内存 / 磁盘型号？

**30 秒版**：`lscpu`（CPU 型号核数）、`free -h`/`/proc/meminfo`（内存）、`lsblk`/`lsblk -d -o name,size,rota`（磁盘和是否 SSD）、`dmidecode -t system`（厂商型号，需 root）、`lspci`（PCI 设备）。

**展开**：

```bash
lscpu                     # 架构、核数、线程、主频、缓存
nproc                     # 逻辑核数（load 对标用这个）
cat /proc/cpuinfo | grep "model name" | head -1
free -h                   # 内存总量和可用
dmidecode -t memory | grep -E "Size|Speed"    # 内存条型号/频率（需 root）
lsblk -d -o name,size,rota,model              # rota=1 机械，0 SSD
df -h; df -i
lspci | grep -i -E "eth|raid|vga"             # 网卡/RAID 卡/显卡
dmidecode -s system-product-name              # 服务器型号
ip -br a                                      # 网卡和 IP 一行一个
ethtool eth0 | grep Speed                     # 网卡速率
```

**云主机的边界**：`dmidecode` 看到的常是虚拟化厂商信息（KVM/QEMU），**看不到真实物理硬件**；云盘的 SSD/HDD 也只能在控制台看。这句话体现你分得清物理机和云。

**追问**

|   |   |
| - | - |

|  |  |
| --- | --- |
- 「怎么判断 CPU 是否支持虚拟化？」→ `grep -E "vmx|svm" /proc/cpuinfo` 有输出就是支持（Intel=vmx，AMD=svm），还要 BIOS 里开启。
- 「load 高了先看几个核？」→ `nproc`（逻辑核数），不是 `lscpu` 里的"每核线程数"。

---

## C12 · 常见 HTTP 状态码，5xx 怎么区分？

**30 秒版**：**2xx 成功、3xx 重定向、4xx 客户端错、5xx 服务端错**。重点：`500` 后端代码异常、`502` 网关拿到无效响应（后端挂了/协议不对）、`503` 服务不可用（过载/维护）、`504` 网关超时（后端太慢）、`413` 请求体太大（上传限制）。

**展开**：

| 码         | 含义        | 常见原因                                      |
| --------- | --------- | ----------------------------------------- |
| 200       | 成功        | —                                         |
| 301/302   | 永久/临时重定向  | 域名跳转、HTTP→HTTPS                           |
| 304       | 未修改       | 协商缓存生效                                    |
| 400       | 请求语法错     | 参数格式不对                                    |
| 401 / 403 | 未认证 / 无权限 | 没登录 / 登录了但没权限（**别混**）                     |
| 404       | 找不到       | 路径错、路由没配                                  |
| **413**   | 请求体过大     | `client_max_body_size` 太小（上传失败高频原因）       |
| 429       | 限流        | `limit_req` 触发                            |
| **500**   | 服务端内部错误   | 代码异常（**应用日志里一定有**）                        |
| **502**   | 网关错误      | 后端进程挂了/端口错/协议不匹配（php-fpm 没起、监听 127.0.0.1） |
| **503**   | 服务不可用     | 过载、维护、后端全摘除                               |
| **504**   | 网关超时      | 后端处理超过 `proxy_read_timeout`               |

**排查口诀**：`502` 查后端活没活（`ss -tlnp`、`systemctl status php-fpm`）；`504` 查后端慢不慢（慢日志、`request_slowlog_timeout`）；`500` 直接看应用日志。

**追问**

- 「401 和 403 的区别？」→ 401 = 你是谁不知道（没认证）；403 = 知道你是谁但你没权限。
- 「502 和 504 都在 Nginx 上看到，怎么分清？」→ 502 是"连上了但拿到垃圾/连不上"，504 是"连上了但等太久"；看 Nginx `error.log` 的 `upstream` 描述最准。

---

## C13 · 磁盘性能怎么测？dd 和 fio 怎么用？

**30 秒版**：`dd` 简单测顺序读写（`oflag=direct` 绕过缓存），`fio` 测真实 IOPS/延迟（更专业）。**测之前一定要确认盘没在用**，否则会把业务拖死。

**展开**：

```bash
# 顺序写（1G，绕过 page cache，避免测到内存）
dd if=/dev/zero of=/data/testfile bs=1M count=1024 oflag=direct
# 顺序读
dd if=/data/testfile of=/dev/null bs=1M iflag=direct
# 清理
rm -f /data/testfile
```

```bash
# fio：随机读 IOPS + 延迟（更接近数据库场景）
fio -filename=/data/test -direct=1 -iodepth=16 -thread -rw=randread \
    -ioengine=libaio -bs=4k -size=1G -numjobs=4 -runtime=30 -group_reporting -name=test
```

**关键点（面试常追问）**：

- **必须 `direct=1`/`oflag=direct`**，否则测的是内存缓存（几十 GB/s 的假数据）。
- 顺序读写看带宽（MB/s），随机读写看 IOPS 和延迟（µs/ms）。
- `bs=4k` + `randread` 才是数据库的真实负载特征；`bs=1M` 顺序是备份/大文件场景。

**追问**

- 「云盘测出来比标称低？」→ 云盘有 **IOPS/带宽上限**（按规格），且受"积分/突发"机制影响；多测几次、看云监控更准。
- 「生产上能随便 dd 测吗？」→ 不能，会把磁盘 IO 打满影响业务；要测就在新盘/维护窗口做。

---

## C14 · 常用的性能观察命令有哪些？vmstat / sar 怎么看？

**30 秒版**：`top`（实时全局）、`vmstat 1`（CPU/内存/IO/上下文切换一屏看全）、`iostat -x 1`（磁盘）、`sar`（**历史回看**，故障过去了也能查）、`ss`（网络连接）。**`sar` 的独特价值是"事后复盘"**。

**展开**：

```bash
vmstat 1 5
```

```
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 1  2  30720  10240   8192 800000    0    0    12    88  500 1200  10  3 85  1  1
```

| 列       | 含义            | 异常信号               |
| ------- | ------------- | ------------------ |
| `r`     | 运行队列长度        | 持续 > 核数 = CPU 不够   |
| `b`     | 阻塞（D 状态）进程数   | **> 0 且在涨 = IO 卡** |
| `si/so` | 换入/换出         | 非 0 = 内存不足在颠簸      |
| `bi/bo` | 块设备读/写（块/s）   | 高 = IO 压力大         |
| `cs`    | 上下文切换         | 极高 = 线程太多/锁竞争      |
| `wa`    | 等 IO 的 CPU 比例 | 高 = IO 瓶颈          |

```bash
sar -u 1 5                 # CPU（历史：sar -u -f /var/log/sa/sa08）
sar -r 1 5                 # 内存
sar -n DEV 1 5             # 网络
sar -d 1 5                 # 磁盘
sar -q                     # load 和运行队列
```

**为什么 `sar` 重要**：`top` 只能看"现在"，故障过去就没了；`sar` 每 10 分钟采一次存到 `/var/log/sa/`，**能回看昨天下午三点到底发生了什么**——这是复盘的关键工具。要装 `sysstat` 并 `systemctl enable --now sysstat`。

**追问**

- 「机器刚重启，怎么知道重启前发生了什么？」→ `sar` 的历史数据（如果 `/var/log/sa` 没被清）、`journalctl -b -1`（上次启动的日志）、`/var/log/messages` 的历史。
- 「`vmstat` 的 `r` 和 `load` 什么关系？」→ `r` 是瞬时运行队列，load 是 1/5/15 分钟平均；load 包含 D 状态，`r` 只算可运行的。

---

## C15 · 容器里的排查和普通机器有什么不同？

**30 秒版**：容器共享宿主内核，所以 **`top`/`free` 看到的是宿主机的数据**（不是容器的）；容器内要限制视角得看 cgroup（`/sys/fs/cgroup/`）。进容器 `docker exec -it 容器 sh`，没 shell 的用 `nsenter` 或 `docker cp` 取证。

**展开**：

```bash
docker ps                                  # 容器在不在、状态、端口
docker stats --no-stream                   # ★容器的 CPU/内存/网络（这才是容器视角）
docker logs -f --tail 100 容器              # 日志
docker exec -it 容器 sh                    # 进去（镜像可能没有 bash）
docker inspect 容器                        # 全部元数据（IP、挂载、重启策略、LogPath）
docker top 容器                            # 容器内进程
cat /sys/fs/cgroup/.../memory.current      # cgroup v2 的真实用量
```

**容器里最常踩的三个坑**：

1. **`free`/`top` 显示的是宿主机数据**——容器内看内存要用 `docker stats` 或 cgroup 文件。
2. **没有 `ps`/`top`/`vi`**——精简镜像（alpine）默认没有，排障前先 `apk add`/`apt install`，或从宿主机 `docker cp` 工具进去。
3. **时区/编码不对**——镜像没 `TZ`/`LANG`，日志时间差 8 小时。
4. **`docker stop` 杀不干净** → 1 号进程没转发信号，10 秒后 SIGKILL，退出码 137（S11）。

**追问**

- 「容器退出码 137 / 143 分别是什么？」→ 137 = 128+9（SIGKILL，常见于 OOM 或超时强杀）；143 = 128+15（SIGTERM，正常优雅停止）。
- 「容器一直重启怎么查？」→ `docker ps -a` 看退出码 → `docker logs` 看最后输出 → `docker inspect` 的 `State.OOMKilled` → 是不是健康检查失败被重启。
- 「容器网络不通怎么查？」→ `docker network inspect` 看网段 → 容器内 `ip a`/`ping 网关` → 宿主机 `iptables -t nat -L -n` 看 DNAT 规则 → 注意 **`-p` 映射会绕过 firewalld**（A11）。

---

## C16 · 你平时怎么学 Linux？遇到不会的怎么办？

**30 秒版**：**动手优先**——遇到问题先 `man`/官方文档，然后自己在云服务器上复现一遍，把现象和解决过程写进笔记/仓库；长期靠"搭项目 + 排真实故障"积累，不靠背题。

**展开**（这题考的是学习能力和自驱，答案要具体、有证据）：

1. **有环境**：自己租一台 2C2G 云服务器，把 LNMP、Docker、监控、备份全跑一遍——纸上看十遍不如亲手踩一次坑。
2. **有文档**：每个坑都记录"现象 → 排查 → 根因 → 解法"，形成自己的知识库（我这个仓库的 `docs/08-踩坑与修复记录.md` 就是干这个的）。
3. **有方法**：`man` → 官方文档 → 搜索（带着报错原文搜）→ **自己起环境验证**，最后一步最关键，不然永远是"别人的答案"。
4. **有输出**：写成文档/笔记，能讲给别人听才算真懂（这也是我整理这些题库的原因）。

**追问**

- 「举个例子说明你自学解决过什么？」→ 用 STAR 讲一个真实坑：比如"php-fpm 监听 127.0.0.1:9000，容器里 nginx 连不上报 502 → `ss -tlnp` 发现监听地址不对 → 改 `zz-docker.conf` 为 0.0.0.0:9000 → 502 消失"。**有现象、有命令、有根因**，比说"我学习能力强"有力一百倍。
- 「最近在学什么？」→ 说一个真实的、能展开的方向（比如"在补 K8s 基础，目前只到会用 `kubectl` 看 Pod 状态，原理还在学"）——**主动交底边界比装懂安全**。

---

# 附录一 · 必背数字表

| 数字         | 含义                                    |
| ---------- | ------------------------------------- |
| 755 / 644  | 目录和可执行文件 / 普通文件的标准权限                  |
| 1777       | 粘滞位目录（`/tmp`）                         |
| 0 / 1 / 2  | stdin / stdout / stderr               |
| 1024       | 默认 fd 上限（太小，要高并发必调）                   |
| 65535      | 端口上限；nofile/somaxconn 常用目标值           |
| 20 / 19    | TCP、UDP 头部最小字节（UDP 固定 8）              |
| 2MSL ≈ 60s | TIME_WAIT 等待时长                        |
| 1024–65535 | 客户端可用端口范围                             |
| 2TB        | MBR 分区表上限                             |
| 128        | GPT 最大分区数                             |
| 666 / 777  | umask 计算的起点（文件 / 目录）                  |
| -20 ~ 19   | nice 值范围                              |
| 8          | bps ÷ 8 = B/s（100Mbps = 12.5MB/s）     |
| 137 / 143  | 128+9（SIGKILL）/ 128+15（SIGTERM）容器退出码  |
| 5 / 15     | 磁盘 `%util` 接近 100 饱和；load 看 1/5/15 分钟 |

# 附录二 · 场景 → 命令速查

| 场景       | 第一命令                    | 深入                                                                 |
| -------- | ----------------------- | ------------------------------------------------------------------ |
| 服务器卡     | `uptime; top`           | `free` → `iostat -x 1` → `ss -s` → `dmesg -T`                      |
| CPU 100% | `top` 按 P               | `top -Hp` → `/proc/pid/exe` → `strace -c`                          |
| 内存不足     | `free -h` 看 available   | `ps aux --sort=-%mem` → `dmesg \| grep -i kill`                    |
| 磁盘满      | `df -h`                 | `du -sh /* \| sort -rh` → `lsof +L1` → `df -i`                     |
| IO 高     | `iostat -x 1`           | `iotop -o` / `pidstat -d 1`                                        |
| 网络不通     | `ping`                  | `mtr` → `dig` → `ss -tlnp` → `nc -zv` → `tcpdump`                  |
| 带宽满      | `sar -n DEV 1`          | `iftop -nP` → `nethogs`                                            |
| 端口占用     | `ss -tlnp \| grep :端口`  | `lsof -i :端口` → `ps -fp PID`                                       |
| 服务起不来    | `systemctl status -l`   | `journalctl -u x -n 100` → 看 `status=203/EXEC`                     |
| 日志排查     | `tail -F`               | `grep -n` → `zgrep` 历史 → `journalctl --since`                      |
| 定时任务不跑   | `cat /var/log/cron`     | `systemctl status crond` → PATH/CRLF/权限三坑                          |
| 挂载新盘     | `lsblk`                 | `fdisk` → `partprobe` → `mkfs` → `mount` → fstab UUID → `mount -a` |
| 扩容       | `lsblk`                 | `growpart` → `xfs_growfs`/`resize2fs`                              |
| 权限异常     | `id`                    | `ls -l` 路径各级 → `namei -l` → `getenforce`/`ausearch` → `lsattr`     |
| SSH 连不上  | `ssh -v`                | 本地网络 → 安全组 → sshd 状态 → 密钥权限 → VNC                                  |
| 找大文件     | `du -sh /* \| sort -rh` | `find / -size +500M`                                               |
| 找老文件     | `find /path -mtime +7`  | `-delete` / `-exec` / `xargs`                                      |

# 附录三 · 成对概念对比（最容易混的 12 组）

| 对比                           | 一句话区分                  |
| ---------------------------- | ---------------------- |
| `kill -9` vs `-15`           | 强杀 vs 优雅退出             |
| `df` vs `du`                 | 文件系统视图 vs 目录累加         |
| 硬链接 vs 软链接                   | 同 inode vs 新 inode     |
| 僵尸 vs 孤儿                     | 死了没被回收 vs 爹没了被 init 收养 |
| `restart` vs `reload`        | 停再起（断连接） vs 重读配置（不断）   |
| `su` vs `sudo`               | 切身份 vs 借权限执行一条         |
| `>` vs `>>`                  | 覆盖 vs 追加               |
| 快照 vs 备份                     | 可回退 vs 可找回             |
| `raid` vs `备份`               | 防硬盘坏 vs 防误删/病毒         |
| TCP vs UDP                   | 可靠有序 vs 快但可能丢          |
| `iptables`（firewalld） vs 安全组 | 系统内 vs 云平台外，两层都要开      |
| `xfs_growfs` vs `resize2fs`  | XFS 给挂载点 vs ext4 给设备   |

# 自检清单（三天过完 96 题）

**第一天（S 级 26 题，2 小时）**

- [ ] 不看答案说出「卡」的五步排查链和判断矩阵
- [ ] 能画：三次握手/四次挥手，说出为什么三次、为什么 2MSL
- [ ] 能写：`ss -tlnp`、`kill -15`、`chmod 755`、`chown -R 999:999`
- [ ] 能讲清：inode 与文件名、软硬链接、链接数−2=子目录数
- [ ] 能背：挂盘八步、fstab 六列、为什么必须 UUID
- [ ] 能说：`2>&1` 为什么顺序不能反（`&1` 复制的是"那一刻"的位置）

**第二天（A 级 30 题，3 小时）**

- [ ] 能讲：启动流程 + target 对照表、`rd.break` + `.autorelabel`
- [ ] 能背：limits.conf 与 `LimitNOFILE` 的区别（systemd 为何不读 limits）
- [ ] 能讲：firewalld 三坑、SELinux 三模式 + AVC 查法
- [ ] 能算：RAID 容量与容错、`lvextend -r`、云盘扩容三步
- [ ] 能说：备份四件套 + 心跳为什么必要 + 恢复演练  
  |  |  |  |  
  | --- | --- | --- |
- [ ] 能讲：`find`/`xargs`、`sort|uniq -c|sort -rn`、tar 参数口诀

**第三天（B + C 级 40 题，2 小时）**

- [ ] 保底题不打磕巴：发行版两家族、CentOS vs Ubuntu、`#`/`$`、`~` 不是根
- [ ] 能读：`ls -l` 八列、`vmstat` 各列、`iostat` 四个关键指标
- [ ] 能说：`umask`、SUID/SGID/Sticky、`chattr +i`
- [ ] 能报：`/dev` 里的伪设备、磁盘命名规律（nvme 的 `p`）
- [ ] 能讲：`%st`、容器 `free` 为什么不准、退出码 137/143
- [ ] 能答软问题：怎么学 Linux + 一个真实的 STAR 案例

> **最后一条原则**：每道题都要能落到「我在自己机器上跑过，当时的现象是 XXX」。只有 L1（报命令）是及格，L3（讲现象和判断依据）才是录用线。

---

> **相关文档**：`01-Linux基础问答.md`（按知识点分章的 110 题详细版）、`06-运维八股.md`（105 条浓缩冲刺版）、`02-Linux场景与追问.md`（简历挖坑与追问链）、`12-基础保底题.md`（38 道一句话速记）。索引见 `README.md`。
