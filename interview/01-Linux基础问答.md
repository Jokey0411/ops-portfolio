# 01 · Linux 基础问答

> **定位**：通用高频概念 + 操作题（110 题），不看简历也可能问。
> **用法**：遮住答案先自己说一遍，卡住的标 ★，回服务器敲一遍再背。
> **环境**：OpenCloudOS / CentOS 系（systemd），MySQL 8.0。全部文档索引见 `README.md`。

---

## 一、系统基础

**1. Linux 系统启动流程？**
电源 → BIOS/UEFI 自检（POST）→ 加载引导程序 GRUB2 → 加载内核 `vmlinuz` 和 `initramfs` → 内核启动第一个用户态进程 `systemd`（PID 1）→ systemd 按 `default.target`（一般是 `multi-user.target` 或 `graphical.target`）并行拉起各服务 → 到达登录界面。
> 加分：能说出 systemd 取代了老 SysV init 的 `/etc/inittab` + 运行级别（runlevel）概念，靠 `target` 组织。

**2. 什么是运行级别 / target？**
| 老 runlevel | systemd target | 含义 |
|---|---|---|
| 0 | poweroff.target | 关机 |
| 1 / S | rescue.target | 单用户（救援） |
| 3 | multi-user.target | 多用户命令行（服务器常用） |
| 5 | graphical.target | 图形界面 |
| 6 | reboot.target | 重启 |

切换：`systemctl isolate multi-user.target`；设默认：`systemctl set-default multi-user.target`。

**3. Linux 目录结构要懂哪些？**
`/etc` 配置、`/var/log` 日志、`/home` 用户目录、`/root` root 家目录、`/usr` 软件、`/tmp` 临时、`/proc` 内核运行时虚拟文件、`/dev` 设备、`/opt` 第三方软件、`/mnt /media` 挂载点。

**4. /proc 是什么？**
虚拟文件系统，不占磁盘，内容是内核运行状态。`/proc/cpuinfo`（CPU）、`/proc/meminfo`（内存）、`/proc/<pid>/`（某进程详情）、`/proc/loadavg`（负载）。

---

## 二、文件与权限 ★★

**5. inode 是什么？**
文件系统的索引节点，存文件的**元数据**（权限、属主、大小、时间戳、数据块指针），**不存文件名**（文件名在目录里）。每个文件一个 inode，inode 用满即使磁盘没满也写不进新文件。查：`df -i`。

**6. 硬链接和软链接区别？★**
| | 硬链接 `ln a b` | 软链接 `ln -s a b` |
|---|---|---|
| inode | 与源文件**同一个** | **新 inode** |
| 删除源文件 | 链接仍可读（内容还在） | 链接失效（悬空） |
| 跨文件系统 | 不支持 | 支持 |
| 链接目录 | 不支持 | 支持 |

**7. 权限位 rwx 数字表示？**
r=4 w=2 x=1。`755` = rwxr-xr-x（属主全权、其他人读+执行），`644` = rw-r--r--。改：`chmod 755 file`、`chmod u+x file`。属主：`chown user:group file`、递归 `-R`。

**8. umask 是什么？**
新建文件/目录的默认权限「掩码」。默认 umask=022 → 文件 666-022=644、目录 777-022=755。

**9. SUID / SGID / Sticky Bit？**
- SUID（4）：执行时**临时获得文件属主权限**，如 `passwd`（普通用户也能改自己的 /etc/shadow）。
- SGID（2）：目录下新建文件继承目录属组。
- Sticky（1）：目录下只有属主能删自己文件，如 `/tmp`（权限 1777）。

**10. sudo 怎么配的？**
`/etc/sudoers`（用 `visudo` 编辑，有语法校验）。一行如 `wangjiyun ALL=(ALL) NOPASSWD: ALL`。

---

## 三、进程管理 ★★★

**11. 进程状态有哪些？**
R 运行、S 睡眠（可中断）、D 不可中断睡眠（等 IO，**高 D 说明 IO 卡**）、T 停止、**Z 僵尸**。

**12. 僵尸进程、孤儿进程是什么？★**
- **僵尸进程**：子进程退出但父进程没 `wait()` 回收，残留 PCB，PID 被占用。大量僵尸会耗光 PID。处理：杀父进程让 init 接管回收，或重启服务。
- **孤儿进程**：父进程先退出，子进程被 systemd/init（PID 1）收养，正常。

**13. 怎么查看和杀进程？**
`ps aux | grep xxx` / `ps -ef`；动态 `top`、`htop`；`top -Hp <pid>` 看线程；树形 `pstree`。
杀：`kill <pid>`（默认 15 优雅）、`kill -9 <pid>`（强杀最后手段）、`pkill -f 关键字`、`killall 进程名`。

**14. kill -9 和 kill -15 区别？★**
-15（SIGTERM）：通知进程**自己清理后退出**（可被捕获，能优雅收尾）。
-9（SIGKILL）：内核**直接强杀**，进程没机会清理（可能留临时文件/锁）。优先 15，无效再 9。

**15. 前台 / 后台 / 守护进程？**
命令后加 `&` 后台；`Ctrl+Z` 挂起、`jobs` 看、`bg` 后台继续、`fg %1` 拉回前台；`nohup cmd &` 或 `setsid` 让进程脱离终端，SSH 断开也不死。正规做法是写成 systemd 服务。

**16. nice / renice 调优先级？**
NI 值 -20(最高)~19(最低)。`nice -n 10 cmd`、运行中改 `renice -n 5 -p <pid>`。

---

## 四、内存 ★★

**17. free 各项怎么看？★★**
```
              total  used   free   shared  buff/cache  available
Mem:           2.0G  1.1G   100M     50M      800M        700M
```
重点看 **`available`**（真正可用的内存）而不是 `free`。Linux 会把空闲内存拿去做 buff/cache（加速），需要时回收，所以 `free` 小不代表内存不够。

**18. swap 是什么？用多了说明什么？**
磁盘上划的一块当「虚拟内存」，物理内存不够时把不活跃页换出去。swap 被大量使用 → **物理内存紧张**、性能会下降（磁盘比内存慢几个数量级）。查：`free -h`、`swapon -s`。

**19. OOM 是什么？**
内存耗尽时内核的 OOM Killer 按评分挑进程杀掉保系统。查日志：`dmesg | grep -i "killed process"` 或 `/var/log/messages`。对策：加内存、优化程序、调 `oom_score_adj` 保护关键进程。

**20. buffers 和 cache 区别？**
- buffers：块设备读写的缓冲（磁盘元数据）。
- cache：页缓存，文件内容缓存。
都是内核为提高 IO 效率占的空闲内存，可被回收。

---

## 五、磁盘与存储 ★★

**21. df 和 du 区别？★**
- `df -h`：**文件系统**层面看分区使用（快，含已删除但被占用空间）。
- `du -sh 目录`：**逐个文件**统计目录实际占用（慢，不含已删除文件）。
- 经典题：`df` 显示 100% 但 `du` 加不满 → 有**已删除但仍被进程占用的文件**，`lsof | grep deleted` 找出来，重启对应进程释放。

**22. inode 用满怎么办？**
`df -i` 看 IUse%。大量小文件（session、日志碎片）耗尽 inode。清理小文件，或重新格式化指定更大 inode 密度。

**23. 怎么挂载磁盘？**
`mkfs.xfs /dev/sdb1` 格式化 → `mount /dev/sdb1 /data` → 写 `/etc/fstab` 开机自动挂载（建议用 UUID，`blkid` 查）→ `mount -a` 测试。

**24. LVM 是什么？**
逻辑卷管理，把物理盘抽象成 PV → 卷组 VG → 逻辑卷 LV，可**在线扩容**。`pvcreate / vgcreate / lvcreate`，扩 `lvextend -L +10G` + `xfs_growfs`。

---

## 六、网络 ★★★

**25. 查端口占用 / 连通性？★★**
- `ss -tlnp | grep :80`（谁监听 80）、`ss -tn state established`（已建立连接）。
- `lsof -i :80`。测试对端通不通：`telnet ip port` 或 `nc -zv ip port`。
- 抓包：`tcpdump -i eth0 port 80 -nn`。

**26. TIME_WAIT 大量出现怎么回事？★**
主动关闭方进入 TIME_WAIT，等 2MSL（约 60s）。服务端高并发短连接时会堆积，占用端口资源。优化：用**长连接/连接池**（治本）、内核调 `tcp_tw_reuse`、`net.ipv4.ip_local_port_range` 扩大端口范围。

**27. 三次握手、四次挥手？**
握手：SYN → SYN+ACK → ACK（**为什么不能两次**：防止失效的历史连接请求突然到达）。
挥手：FIN → ACK → FIN → ACK（**为什么四次**：TCP 全双工，两端要各自关闭）。

**28. 防火墙怎么管？**
CentOS 系 `firewalld`：`firewall-cmd --add-port=80/tcp --permanent` + `--reload`、查 `--list-all`。底层是 iptables/nftables。

**29. DNS 解析怎么查？**
`/etc/resolv.conf` 配 DNS；`nslookup 域名`、`dig 域名`、`host 域名`；本地优先 `/etc/hosts`。

---

## 七、服务与定时任务

**30. systemd 常用命令？★**
`systemctl start|stop|restart|reload|status 服务`、`enable`（开机自启）`disable`、`daemon-reload`（改配置后）、`list-units --type=service`、看日志 `journalctl -u 服务`。

**31. restart 和 reload 区别？**
restart 停再起（**会断连接**）；reload 重新读配置（**不断连接**，进程不重启，如 nginx）。

**32. crontab 怎么写？★**
```
分 时 日 月 周
0 2 * * *  /path/backup.sh   # 每天凌晨2点
*/5 * * * * cmd              # 每5分钟
```
`crontab -e` 编辑、`-l` 查看。日志 `/var/log/cron`。
> 不执行三坑：脚本没执行权限或 Windows 换行符（CRLF）/ 环境变量 PATH 太短 / 没把输出重定向到日志。

---

## 八、日志

**33. 日志都放哪？**
`/var/log/messages`（系统）、`/var/log/secure`（登录认证）、`/var/log/cron`（定时任务）、`dmesg`（内核）、`journalctl`（systemd 统一管理）。

**34. 实时看日志 / 查关键字？**
`tail -f xxx.log`、`grep 'ERROR' xxx.log`、统计 `grep -c`、按时间 `sed -n '/10:00/,/11:00/p'`。

**35. 日志太多磁盘爆了怎么办？**
`logrotate` 按天/按大小切割并保留 N 份（配置 `/etc/logrotate.conf` 和 `/etc/logrotate.d/`）。

---

## 九、用户管理

**36. 增删用户、改密码？**
`useradd name`（`-m` 建家目录 `-s /bin/bash`）、`userdel -r name`、`passwd name`、加组 `usermod -aG group name`。

**37. /etc/passwd 每行什么意思？**
`用户名:密码占位x:UID:GID:注释:家目录:登录Shell`（真正的加密密码在 `/etc/shadow`）。

---

## 十、Shell 与脚本 ★

**38. 常用环境变量？**
`$PATH`（命令搜索路径）、`$HOME`、`$PWD`、上条命令返回值 `$?`（0 成功）。导出 `export VAR=xx`，永久写 `~/.bashrc`。

**39. 重定向和管道？**
`>` 覆盖写、`>>` 追加、`2>` 错误、`2>&1` 合并错误到输出、`cmd | cmd2` 前一个输出作后一个输入、`tee` 同时写文件和屏幕。

**40. 三剑客定位？**
- `grep`：按行**过滤**。
- `sed`：按行**编辑**（替换 `sed 's/旧/新/g'`、删行、取区间）。
- `awk`：按**列**处理（`awk '{print $1}'`，统计、求和）。
组合技：`awk '{print $1}' access.log | sort | uniq -c | sort -rn | head` 统计 IP TopN。

---

## 十一、包管理

**41. 装软件用什么？**
CentOS 系 `yum/dnf install 包`、`yum remove`、`yum list installed`、本地 `rpm -ivh xxx.rpm`、查 `rpm -qa | grep`。Debian/Ubuntu 用 `apt`。

---

## 十二、综合排查题（必考）★★★

**42. 服务器很卡怎么排查？（万金油五步走）**
1. `top` / `htop`：看 CPU、load、内存、谁占资源。
2. `free -h`：内存够不够（看 available）、swap 用了没。
3. `df -h` + `iostat -x 1`：磁盘满没满、IO `%util` 打没打满。
4. `ss -s` / `ss -tn`：连接数、TIME_WAIT 是否爆炸。
5. `dmesg | tail` / `/var/log/messages`：有没有 OOM、硬件报错。
> 口诀：**先 CPU → 内存 → 磁盘 IO → 网络连接 → 日志**。

**43. load average 高说明什么？**
`load average: 1.5, 2.0, 2.5`（1/5/15 分钟平均）= 处于运行或**不可中断等待**的任务数。一般 > CPU 核数说明有排队。高 load + 高 CPU → 算力不够；**高 load + 低 CPU + 高 %util → IO 瓶颈**（等磁盘）。

**44. 网站打不开怎么排？**
先 `curl -I 域名` 本地自测 → `ss -tlnp` 看服务监听没 → `systemctl status` 服务活着没 → 看日志 → 防火墙/安全组放行没 → DNS 解析对不对。

**45. 磁盘 100% 怎么快速定位大文件？**
`du -sh /* 2>/dev/null | sort -rh | head` 一层层下钻；`find / -type f -size +500M`；记得查 `lsof | grep deleted`（已删除未释放）。

---

## 十三、补充：设备文件 · 包管理 · 防火墙与内核调优

**46. /dev 目录下都有什么？**
「一切皆文件」——硬件设备在 `/dev` 以文件形式呈现，由 udev/devtmpfs **动态生成**。`ls -l` 开头 `b`=块设备、`c`=字符设备。
- **块设备**：`/dev/sda`（SATA/SCSI 盘）、`/dev/nvme0n1`（固态）、`/dev/vda`（virtio 虚拟盘，云主机常见）、`/dev/mapper/xxx`（LVM）、`/dev/loop0`（回环设备）。
- **字符设备**：`/dev/tty`、`/dev/tty1`（终端）、`/dev/pts/0`（伪终端，**每个 SSH 会话一个**）、`/dev/ttyS0`（串口）。
- **伪设备 ★**：`/dev/null`（黑洞，`cmd > /dev/null 2>&1`）、`/dev/zero`（无限吐 0）、`/dev/random`（真随机，熵不够阻塞）、`/dev/urandom`（伪随机，不阻塞）、`/dev/full`（模拟磁盘满）。
- **特殊**：`/dev/shm`（共享内存 tmpfs）、`/dev/fd`（→ /proc/self/fd）、`/dev/net/tun`（TUN/TAP 虚拟网卡）。
> 加分：每个设备文件有**主/次设备号**，主号对应驱动、次号对应具体设备；命名规律 `sd*`=SATA/SCSI、`nvme*`=固态、`vd*`=虚拟化、`tty`=终端、`pts`=远程会话。

**47. rpm 是什么？和 yum/dnf 什么区别？★**
RPM（RPM Package Manager）是 Red Hat 系（RHEL/CentOS/Rocky/Fedora/OpenCloudOS）的包管理系统，既是 `.rpm` 格式也是底层命令。**核心特点：不管依赖**，信息存在 `/var/lib/rpm` 数据库。
- 常用：`rpm -ivh`（装）、`-Uvh`（升级）、`-e`（卸）、`-qa`（列已装）、`-ql 包`（这个包装了哪些文件）、`-qf 文件`（**反查文件属于哪个包**）、`-qc`（配置文件）、`-V`（校验篡改）。
- **rpm vs yum/dnf**：rpm 是底层「手动挡」，只能装本地包、**不解决依赖**；yum/dnf 是上层「自动挡」，从仓库在线装并**自动装依赖**（CentOS 8+ 用 dnf）。
- 加分：Debian 系是 `.deb`：`dpkg`（底层）+ `apt`（上层），和 rpm/yum 一一对应；生产日常用 `dnf install`，内网离线才 `rpm -ivh`。

**48. 防火墙（firewalld）怎么配？★★**
原则：**最小开放 + 两层防护 + 先临时后永久**。云服务器除系统 `firewalld`，**云平台安全组也要配**（两层都配，否则端口不通或意外暴露）。
```bash
systemctl enable --now firewalld
firewall-cmd --list-all                  # 看当前规则
firewall-cmd --add-port=80/tcp --permanent
firewall-cmd --add-port=443/tcp --permanent
firewall-cmd --reload                    # ★ 加完必须 reload 才生效
firewall-cmd --add-service=https --permanent          # 用预定义服务更规范
# 数据库绝不对全网开，用 rich rule 限来源
firewall-cmd --permanent --add-rich-rule='
  rule family="ipv4" source address="10.0.0.0/8"
  port port="3306" protocol="tcp" accept'
```
- **zone**：`public`（默认，只放行显式加的）、`trusted`（全放行）、`internal`/`dmz`；`--change-interface=eth0 --zone=internal` 决定网卡用哪套规则。
- 加分：**跑 Docker 的机器别 `iptables -F`**，会把 Docker 链清掉导致容器网络瘫痪；Docker 的 `-p` 映射会绕过 firewalld，对外暴露要一起看。

**49. 内核参数（sysctl）怎么调？★★**
临时 `sysctl -w net.ipv4.ip_forward=1`；**永久**写 `/etc/sysctl.d/99-custom.conf`（推荐 .d 目录，好管理），再 `sysctl -p 文件` 生效。
```conf
net.ipv4.ip_forward = 1            # Docker/容器网络/NAT 需要
vm.swappiness = 10                 # 数据库机器少用 swap
net.ipv4.tcp_tw_reuse = 1          # TIME_WAIT 复用
net.ipv4.ip_local_port_range = 1024 65000
net.core.somaxconn = 65535         # 连接队列，抗突发
net.ipv4.tcp_max_syn_backlog = 65535
fs.file-max = 655350               # 系统级最大文件句柄
```
- **配套 ulimit**：`fs.file-max` 是系统级，进程级还要改 `/etc/security/limits.conf`（`* soft nofile 65535`）。
- 加分：**不要整套照抄"高并发优化参数"**，哪个指标真出问题再针对性调；改前先备份原值。

**50. 配防火墙 / 内核参数的三个坑？**
1. 加规则**忘 `--permanent`** → 重启后规则全丢。
2. 加了 permanent **忘 `--reload`** → 看着配了实际没生效。
3. 跑 Docker 的机器 `iptables -F` → Docker 链被清，容器网络瘫痪。
> 口诀：**最小开放、两层都配、先临时后永久、改前先备份**。

---

## 十四、备份与告警（实战综合题）

**51. 如何实现代码和数据库每日自动备份 + 异常告警？★★**
拆成四个脚本，crontab 错峰调度：
- **数据库**：`mysqldump --single-transaction --quick --routines --triggers` 全库 + 分库，`--single-transaction` 保证 InnoDB 一致性快照、不锁表。
- **代码**：有 `.git` 用 `git bundle --all`（单文件含完整历史，`git clone xxx.bundle` 即可恢复）；普通目录用 `tar` 排除 `node_modules/.git/日志`。
- **告警**：失败调 `notify.sh`（钉钉加签 / 飞书 / 邮件，兜底写本地 `alarm.log`）。
- **心跳**：`backup_heartbeat.sh` 每天查「最新备份文件年龄」，超 26h 告警——**兜底 cron 没跑/机器重启/静默失败**。

```bash
0  3 * * * mysql_backup.sh     >> ... 2>&1   # 库
30 3 * * * code_backup.sh      >> ... 2>&1   # 代码
0  9 * * * backup_heartbeat.sh >> ... 2>&1   # 心跳
```

**可靠性要点（必答）**：备份后校验 `[ -s 文件 ]` 非空 + `gzip -t` 完整；保留 7 天 `find -mtime +7 -delete`；`flock -n` 防重叠；crontab 首行加 `PATH`（否则找不到 docker/mysqldump）；**备份不验证恢复 = 没备份**，要定期 `restore_test.sh`。
> 一句话：**失败告警 + 心跳兜底 + 恢复演练，三样齐了才叫「备份系统」，只 `mysqldump` 一下那叫「拷数据」。**

---

## 十五、存储进阶：挂载 · 扩容 · LVM · RAID ★★

**52. 挂一块新盘的完整流程？（必考，要能背出顺序）★**
`lsblk` 确认设备 → `fdisk /dev/vdb` 分区（>2T 用 `parted` + GPT）→ `mkfs.xfs /dev/vdb1` 格式化 → `mkdir /data` → `mount /dev/vdb1 /data` 手动挂验证 → `blkid` 取 UUID → 写 `/etc/fstab` → **`mount -a` 验证再重启**。三步别混：**分区 ≠ 格式化 ≠ 挂载**，`df` 看不到说明缺了后两步。

**53. fstab 六列 + 为什么必须用 UUID？★★**
`UUID=xxx /data xfs defaults,noatime 0 0` = ①设备 ②挂载点 ③类型 ④选项 ⑤dump(0) ⑥fsck 顺序(根1/其他2/不查0)。**设备必须写 UUID**：`/dev/vdb1` 是内核按发现顺序分配的，插拔硬盘会变；UUID 是文件系统自带身份不变。云盘再加 `nofail,_netdev`，否则云盘没挂上时系统卡在启动。fstab 写错 = emergency mode，救援：`mount -o remount,rw /` 改回来。

**54. 云盘从 50G 扩到 100G，系统里还是 50G？★**
控制台扩容 ≠ 系统生效，三步：`lsblk` 确认内核看到新容量 → `growpart /dev/vdb 1` 扩分区（注意是空格不是斜杠）→ 扩文件系统：**XFS 用 `xfs_growfs /data`、ext4 用 `resize2fs /dev/vdb1`**。高频追问：**XFS 只能扩不能缩**；ext4 能缩但要先 umount → `e2fsck` → `resize2fs` → `lvreduce`，顺序反了毁数据。

**55. LVM 是什么？核心命令？★★**
PV（物理卷）→ VG（卷组，空间池）→ LV（逻辑卷），价值 = **跨盘汇池 + 在线扩容 + 快照**。
```bash
pvcreate /dev/vdb /dev/vdc && vgcreate datavg /dev/vdb /dev/vdc
lvcreate -n datalv -L 100G datavg && mkfs.xfs /dev/datavg/datalv && mount /dev/datavg/datalv /data
lvextend -L +20G -r /dev/datavg/datalv        # ★ -r 连文件系统一起扩，一条命令
pvcreate /dev/vdd && vgextend datavg /dev/vdd  # 池子不够，加新盘
```
快照：`lvcreate -s -n snap -L 5G datavg/datalv`，原理**写时复制 COW**——只记录打快照后被改的块，所以快照卷不用和原卷一样大；解决「备份期间数据在变」，几秒冻结即可做一致性备份。系统重装后 `pvscan` + `vgchange -ay` 能找回（元数据在盘头部）。

**56. RAID 各级别？★★**
| 级别 | 最少盘 | 可用容量 | 允许坏 | 特点 |
|---|---|---|---|---|
| 0 | 2 | 100% | 0 | 条带提速，坏一块全没 |
| 1 | 2 | 50% | 1 | 镜像，系统盘常用 |
| 5 | 3 | n-1 | 1 | 奇偶校验；**写惩罚大**（读旧数据+读旧校验+计算+写两处） |
| 6 | 4 | n-2 | **2** | 双校验，大容量时代在取代 RAID 5 |
| 10 | 4 | 50% | 每组镜像 1 块 | 镜像+条带，数据库首选 |
追问「RAID 5 什么时候最危险」→ **重建期间**：大容量盘重建几小时，期间再坏一块或遇到读错误（URE）数据全丢。软 RAID：`mdadm --create /dev/md0 --level=5 --raid-devices=3 /dev/sd{b,c,d}`，状态看 `cat /proc/mdstat`（`[UU_]` 的下划线=缺盘），换盘 `--fail --remove --add`。

**57. 云服务器上用 RAID / LVM 吗？（诚实交底，加分）**
**不用**。云盘后端本身三副本冗余（替代 RAID 的职责），云盘在线扩容（Q54）替代 LVM 的弹性。物理机上才是 RAID 在下 + LVM 在上组合。答出「云平台已替代这两层」比背命令高一档。

---

## 十六、必问基础补全（盲区清查）★★

**58. swap 是什么？怎么加？★★**
磁盘当内存用：内存不足时把不活跃页换出去。`free -h` 看，**swap 用得多 = 内存紧张**。加 2G swap 文件：
```bash
fallocate -l 2G /swapfile && chmod 600 /swapfile
mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap defaults 0 0' >> /etc/fstab && swapon -s
```
`vm.swappiness=10` 调低使用倾向（数据库机器建议）。swap 打满先查谁在吃内存，别急着加 swap。

**59. `nohup cmd > out.log 2>&1 &` 三个部分分别干嘛？★★**
- `&`：放后台，但**不免疫挂断**（终端一关就收到 SIGHUP）
- `nohup`：忽略 SIGHUP，免疫挂断
- 重定向：不写的话 nohup 默认输出到 `nohup.out`，容易撑爆家目录

管理：`jobs` 看后台、`fg %1` 调回前台、`bg %1` 继续、`kill %1`。长期服务不该用 nohup，用 **systemd**。

**60. `2>&1` 什么意思？为什么顺序不能反？★★★**
`0=stdin，1=stdout，2=stderr`。`cmd > f 2>&1`：stdout 先指向 f，然后 stderr **指向"stdout 当时的位置"**（f）→ 都进文件。反过来 `cmd 2>&1 > f`：stderr 先指向屏幕（当时 stdout 的位置），stdout 再改指 f → **stderr 还是上屏幕**。记法：**重定向从左到右生效，`&1` 复制的是"那一刻"的位置**。

**61. su 和 sudo 区别？★★**
`su - user`：**切换身份**，要目标用户的密码；`-` 必须带（不带则环境变量还是旧的，经典坑）。`sudo cmd`：**以 root 身份执行单条**，输自己的密码，白名单在 `/etc/sudoers`——**只能用 `visudo` 改**（保存时做语法检查，直接改写错会让所有人 sudo 不了）。`sudo -l` 看自己有哪些权限。安全上 sudo 可审计（有日志）、可细粒度授权，优于共享 root。

**62. scp 和 rsync 区别？★★**
- `scp file user@host:/path`：简单传输，全量
- `rsync -avzP --exclude='*.log' /data/ user@host:/backup/`：**增量**（只传变化块，校验和比对）、可断点续传（`-P`）、能排除目录、能删对端多余文件（`--delete`，慎用）
- 大批量/定期同步一律 rsync；末尾斜杠有讲究：`/data/` 传**内容**，`/data` 传**目录本身**

**63. tar 解压参数必背 ★**
```bash
tar -zxvf x.tar.gz -C /dst     # z=gzip x=解 v=过程 f=文件（f 必须最后放参数）
tar -zcvf x.tar.gz dir/        # 压缩 c=create
tar -tf x.tar.gz               # 只看内容不解压（★ 先看再解，防解压炸弹/覆盖）
tar -Jxf x.tar.xz              # J=xz；tar -jxf 对应 bzip2
unzip x.zip -d /dst
```
记法：**压缩 c 解压 x 看清单 t，格式字母（z/j/J）跟在后面**。

**64. 进程和线程的区别？★★**
**进程 = 资源分配的基本单位**（独立地址空间、fd 表），**线程 = CPU 调度的基本单位**（共享进程的内存，只私有自己的栈和寄存器）。线程切换轻、通信简单（共享内存）但一崩全崩；进程隔离好、通信要 IPC（管道/socket）。Linux 下线程就是共享资源的进程（`clone` 出来的，`ps` 里 `l` 修饰符）。浏览器多进程、Nginx 多进程 worker、PHP-FPM 多进程，Java 多线程——为什么选哪种，按「隔离 vs 切换成本」答。

**65. free 里 buffer 和 cache 区别？★★**
- **buffer**：块设备的写缓冲（元数据、块 IO 的中转）
- **cache**：文件内容的页缓存（读过的文件放内存，下次免磁盘）
两者都是**内核可回收**的，所以看内存别看 `free`，看 **`available`**。`echo 3 > /proc/sys/vm/drop_caches` 能手动清缓存，但**日常没必要**——缓存留着就是提升性能的，别学网上「优化脚本」清它。

**66. 程序开机自启有哪几种方式？★★**
① **systemd unit（首选）**：写 `/etc/systemd/system/app.service`（`[Unit]` 描述依赖、`[Service]` `ExecStart=`、`[Install]` `WantedBy=multi-user.target`），`systemctl daemon-reload && systemctl enable --now app`。好处：开机自启 + 崩了自动拉起（`Restart=always`）+ `journalctl -u` 看日志。
② `crontab @reboot`：简单任务。
③ `rc.local`（老方式，要先给执行权限）。容器项目用 `docker compose` 的 `restart: always`。

**67. chattr / lsattr 是什么？（加分）**
比 rwx 更高一层、**连 root 都拦**的文件属性：`chattr +i file` 不可修改（防误删/防篡改，**密码哈希写不进去时先看是不是 /etc/passwd 被 +i 了**——经典排障题）；`chattr +a log` 只能追加不能改删（日志防篡改）。`lsattr` 查看。别和权限位搞混：chmod 是 DAC，chattr 是文件系统级标志。

**68. SSH 免密原理和常见坑？★★**
原理：本地生成密钥对 `ssh-keygen -t ed25519`，把**公钥**追加到服务器的 `~/.ssh/authorized_keys`（`ssh-copy-id user@host` 一条搞定）。登录时服务器用公钥发起挑战，客户端用私钥应答——**私钥永远不离开本机**。
三个高频坑：
- `authorized_keys`/`~/.ssh` 权限不对（要 600/700），**权限太开免密失效**
- 家目录权限 777 也会被 sshd 拒绝（StrictModes）
- SELinux 上下文：`restorecon -Rv ~/.ssh`
加固三件套：禁 root 直登（`PermitRootLogin no`）、改默认端口、`PasswordAuthentication no` 只留密钥。

**69. 环境变量：export / source 与 . / 配置文件优先级？**
- `export VAR=x`：导出给**子进程**可见；不 export 只是当前 shell 的局部变量
- `source script.sh`（等价 `. script.sh`）：**在当前 shell 执行**，不开子进程——所以改完 `~/.bashrc` 要 `source` 才立即生效
- 加载顺序：`/etc/profile` → `~/.bash_profile` → `~/.bashrc`（交互非登录 shell 只读 bashrc）
- PATH 追加：`export PATH=/usr/local/bin:$PATH`（**新路径放前面**，同名校验先到先得——排查「装了新版本不生效」第一件事 `which -a cmd`）
- 永久生效写 `~/.bashrc`（个人）或 `/etc/profile.d/*.sh`（全局）

---

## 十七、基础命令实操与网络配置（对照精讲课 06–16）★★

**70. 文件和目录管理，必会命令有哪些？★★**
```bash
pwd                  # 当前绝对路径；cd - 回上一个目录；cd ~ 回家目录
ls -lh --time=ctime  # l=权限属主大小时间 h=人类可读 a=含隐藏(.开头)
mkdir -p a/b/c       # -p 一次建多级（不存在也不报错）
rmdir a              # 只能删空目录；删非空用 rm -rf
touch f1             # 存在则更新时间戳，不存在则创建空文件
cp -a /src/. /dst/   # -a=归档(保留权限属主时间戳，= -rd --preserve=all)
                     # -r 递归；cp 覆盖前想确认用 cp -i
mv old new           # 改名 / 移动，同分区 mv 是秒完成的"改名"不拷数据
rm -rf dir/          # 删目录及内容——★生产禁随手 rm -rf，先 ls 确认再删
file xxx             # 判断文件真实类型（不看扩展名看魔数）
stat f1              # 看 inode/权限/三个时间戳(atime访问 mtime内容改 ctime元数据改)
tree -L 2 /data      # 树状看两层结构；basename/dirname 取路径最后一段/前面部分
```
- **通配符**：`*` 任意多字符、`?` 单个、`[abc]` 集合、`{a,b}.conf` 花括号展开（`cp app.conf{,.bak}` 快速备份）。
- **rwx 对目录的含义**（高频追问）：目录的 `r`=能 `ls` 列文件名、`w`=能**增删改**目录下文件（重命名/删除），`x`=能 `cd` 进去并访问文件。**只有 r 没有 x 只能看名字不能进**；删除文件要的是**目录的 w**，不是文件自己的 w。
- 追问「cp 保留权限用哪个参数」→ `-a`；「mv 跨分区为什么慢」→ 跨文件系统等于"复制+删除"。

**71. find 怎么用？查找命令全家桶对比？★★**
```bash
# find 基本式：find 路径 [条件] [动作]
find /var -name "*.log" -mtime +7          # 7天前的日志（+7=7天前，-1=24h内）
find /data -type f -size +100M             # 大于100M的文件（f文件 d目录 l链接）
find /app -user www -name "*.tmp"          # 按属主+名字
find /etc -type f -perm 644                # 按权限
find /tmp -name "core*" -mtime +3 -delete  # 动作：直接删
find / -name "*.conf" -exec grep -l "8080" {} \;   # 动作：对结果逐个执行命令
```
- 必考组合：**`-mtime +7 -delete` 清老日志**（配合 `xargs` 或 `-exec`）；`-exec ... {} \;` 中 `{}` 占位结果、`\;` 结尾。
- **xargs 与 -exec 区别**：`-exec` 每个结果调一次命令；`xargs` 把结果攒成参数列表批量执行，快且省资源。文件名含空格时 `find -print0 | xargs -0`。
- **全家桶对比**：
| 命令 | 找什么 | 原理/速度 |
|---|---|---|
| `find` | 文件/目录，条件最全 | 实时遍历磁盘，慢但准 |
| `locate xxx` | 按名字秒查 | 查 `/var/lib/mlocate` 数据库，**快但要 `updatedb` 刷新** |
| `which cmd` | PATH 里找**可执行命令** | 只搜 PATH |
| `whereis cmd` | 命令+帮助文档+源码位置 | 数据库查 |
| `type cmd` | 区分内建/别名/外部命令 | shell 内建 |
| `alias`/`grep --color=auto` | 别名查 `alias`，解别名 `\ls` 或 `command ls` | — |

**72. 文本过滤、统计、压缩，工具箱怎么搭？★★**
```bash
cut -d: -f1 /etc/passwd          # 按冒号取第1列（-d分隔符 -f列号）
wc -l access.log                 # 行数；-w词数 -c字节数
sort -t: -k3 -rn /etc/passwd     # 按第3列数字倒序（-n数字 -r倒序 -u去重）
sort ip.txt | uniq -c | sort -rn # ★ 统计TopN三件套：排序→计数→再排
uniq ip.txt                      # 必须先sort！uniq只合并"相邻"重复
head -n 20 / tail -n +2          # 前20行 / 从第2行开始
grep -rn --include="*.conf" "8080" /etc   # -r递归 -n行号 -v反选 -i忽略大小写
xargs                            # 把stdin变成命令参数：cat id.txt | xargs rm -f
```
- **压缩全家桶**（后缀认字母）：
```bash
gzip f.log          # 生成 f.log.gz，★默认删除原文件；-k 保留
zcat f.log.gz       # 不解压直接看
zgrep "ERROR" f.log.gz   # 直接在压缩包里grep——★查历史日志神技
bzip2 / xz          # 压缩率更高、更慢；对应 bzcat / xzcat
zip -r bak.zip dir/ # zip 唯一要 -r 递归；unzip bak.zip -d /dst
tar -zcvf all.tar.gz dir/  # 打包+压缩一步，见 Q63
```
- 口诀：**gzip 快、bzip2 中、xz 最省空间最慢**；交换空间/大备份常用 xz；压缩比追问答 `gzip -9` 级别可调。
- 追问「uniq 为什么不生效」→ **没先 sort**，uniq 只看相邻行。

**73. 除了 crontab，一次性任务怎么排？at 是什么？★**
`at` 执行**一次性**延时任务，cron 管**周期性**任务：
```bash
echo "/app/cleanup.sh" | at now + 30 minutes   # 30分钟后执行一次
at 22:00                       # 交互式输入命令，Ctrl+D 提交
atq                            # 查看待执行队列
atrm 3                         # 删除3号任务
```
- 依赖 `atd` 服务（`systemctl status atd`）；输出会**邮件发给用户**，脚本里自己重定向日志。
- 追问「cron 和 at 怎么选」→ 每天凌晨跑选 cron；"十分钟以后重启一次服务"选 at。
- 加分：`systemd-run --on-active=10min` 是 systemd 版一次性定时器，容器化环境更常用；cron 每个用户任务还受 `at.deny/cron.deny` 控制。

**74. CPU 突然 100%，怎么定位并处理异常进程？（实操题）★★★**
```bash
top → P 按CPU排序            # 1. 找到最耗CPU的PID
top -Hp <pid>                # 2. 看该进程内哪个线程耗CPU
printf '%x\n' <线程tid>       # 3. 线程号转16进制（Java排查用，对应jstack里的nid）
cat /proc/<pid>/cmdline      # 4. 看进程完整启动命令，确认是谁
ls -l /proc/<pid>/exe        # 5. 可执行文件真实路径（防伪装名，挖矿病毒常改名）
lsof -p <pid>                # 6. 看它打开了哪些文件/网络连接（有无可疑外连）
strace -p <pid> -c -t 5      # 7. 追踪系统调用，看卡在哪类操作
```
处理顺序：**确认身份 → 评估能不能杀 → 先 kill -15 → 3 秒后还在再 kill -9**。杀完看服务是否自动拉起（systemd `Restart=always` / 容器 `restart: always`），再查根因：是业务峰值、死循环、还是挖矿木马（**查可疑 crontab `crontab -l`、`/tmp` 下可执行文件、异常外连 `ss -tnp`**）。
- 关联题：**异常进程关不掉**？→ D 状态（不可中断 IO）kill -9 没用，只能等 IO 返回或重启；Z 僵尸杀"僵尸本身"没用，要杀其父进程。
- 追问「kill -15 后进程还在」→ 进程忽略了 TERM 信号或卡在 D 状态；再查 `dmesg` 是否有 IO 故障。

**75. 分区：MBR 和 GPT 区别？fdisk 实操命令？★★**
| | MBR（老） | GPT（新，必选） |
|---|---|---|
| 最大盘 | **2TB** | 9.4ZB，无限制 |
| 主分区 | 最多 4 个（扩展+逻辑分区绕） | 128 个 |
| 分区表 | 一份，坏了全丢 | **头尾双份**带 CRC 校验 |
| 配套 | fdisk 老版、BIOS 引导 | `parted`/新版 fdisk、UEFI 引导 |

```bash
lsblk                      # 看盘和分区树（vda/vdb…），★第一步永远先lsblk
fdisk -l /dev/vdb          # 看分区表类型(Disklabel type: gpt/dos)
fdisk /dev/vdb             # 交互：n新建 → p主分区 → 序号 → 起止扇区(回车全给) → w写入
parted /dev/vdb print      # >2T 或 GPT 用 parted：mklabel gpt → mkpart
partprobe /dev/vdb         # ★让内核重读分区表（不重启生效）
```
- 追问「为什么云盘 >2T 要用 GPT」→ MBR 寻址只有 32 位 LBA，最大 2TB；`fdisk` 会警告改用 `parted`。
- 追问「分完区不认」→ 忘了 `partprobe`（或重读 `lsblk` 确认），另一个坑是盘符是 `vdb` 不是 `vdb1`——分区才有 `1`。

**76. 网络基础概念：IP、掩码、网关、路由分别是什么？★★**
- **IP 地址**：主机的网络身份标识，IPv4 32 位（点分十进制），`ip addr` 或 `ip a` 查看。
- **子网掩码**：划出"网络位 + 主机位"。`255.255.255.0`（/24）表示前 24 位是网络号 → 该网段 254 个可用主机。**同一网段直连，跨网段必须走网关**。
- **网关**：本网段的"出口路由器"，`ip route` 看 `default via 172.19.0.1 dev eth0`。出公网的包先送到网关。
- **路由**：内核决定"目的地址的包从哪个网卡、哪个下一跳发出"，`ip route` 查路由表，最长前缀匹配。
- **端口**：0–65535，0–1024 特权端口需 root（所以 nginx master 是 root、worker 降权）；`ss -tlnp` 看监听。
- 追问「ping 同网段通、ping 外网不通」→ 三查：网关配没配（`ip route` 有无 default）、网关通不通（`ping 网关IP`）、DNS 好没好（`ping 223.5.5.5` 通而域名不通 = DNS 问题）。
- 追问「ifconfig 命令找不到」→ 新系统默认没装 net-tools，改用 `ip` 命令族：`ip addr`（地址）、`ip link`（网卡）、`ip route`（路由）、`ip neigh`（ARP 表）——**面试答 ip 不答 ifconfig 更现代**。

**77. IP 地址怎么配置？改完怎么生效？★★**
```bash
# ① 临时（重启失效，应急用）
ip addr add 172.19.0.100/24 dev eth0
ip link set eth0 up / down
ip route add default via 172.19.0.1

# ② 永久（RHEL/CentOS 8+ 主推 nmcli）
nmcli con show                          # 看连接名
nmcli con mod eth0 ipv4.method manual \
    ipv4.addresses 172.19.0.100/24 \
    ipv4.gateway 172.19.0.1 \
    ipv4.dns "223.5.5.5 8.8.8.8"
nmcli con up eth0                       # 立即生效

# ③ 老式 ifcfg 文件（仍要认识）：/etc/sysconfig/network-scripts/ifcfg-eth0
BOOTPROTO=static      # dhcp 或 static
ONBOOT=yes            # ★不开机激活网卡=重启后断网，经典事故
IPADDR=172.19.0.100
NETMASK=255.255.255.0
GATEWAY=172.19.0.1
DNS1=223.5.5.5
```
- 改完验证三板斧：`ip a`（地址对不对）→ `ip route`（默认路由在不在）→ `ping 网关` → `ping 223.5.5.5`（分层验证）。
- **云服务器大坑**：内网 IP 是 VPC 分配的，**不要手改**，改了和云平台对不上直接失联；公网 IP 只出现在云控制台（EIP 映射），`ip a` 里看不到是正常的。
- 追问「DHCP 和静态怎么选」→ 服务器一律静态；DHCP 租约一换 IP，服务全断。

**78. 网络不通，测试命令按什么顺序用？★★★**
```bash
ping 223.5.5.5 -c 4          # ① 通=IP层和路由正常；不通=往下查网卡/网关
ping 网关IP                   # ② 网关都不通→本机配置或内网问题
traceroute 223.5.5.5         # ③ 看卡在哪一跳（逐跳TTL递增探测）
mtr 223.5.5.5                # ④ traceroute+ping合体，动态看每跳丢包率（更专业）
dig 域名 / nslookup 域名      # ⑤ IP通域名不通→DNS问题
ss -tlnp                     # ⑥ 本地服务监听没起来？端口对不对？
curl -v telnet://ip:port     # ⑦ 端口通不通（等价 telnet/nc -zv）
tcpdump -i eth0 host 1.2.3.4 -nn   # ⑧ 终极手段：抓包看包到底发没发、回没回
```
- 分层排查口诀：**先 IP 层（ping）→ 再传输层（端口）→ 再应用层（curl）**；先本机（监听）再远端（防火墙/安全组）。
- 追问「ping 不通但服务是好的」→ 可能对端禁 ICMP（很多生产机器禁 ping），**ping 不通 ≠ 服务不通，用 `nc -zv ip 端口` 测端口才作数**。
- 追问「traceroute 中间出现 *」→ 中间路由禁 ICMP 响应，只有**最后一跳**不通才是真故障。

**79. curl 和 wget 用法与区别？★★**
```bash
# curl：调试/接口测试之王
curl -I https://x.com            # 只看响应头（状态码/服务器）——★测服务通不通第一命令
curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" URL  # 静默+只输出状态码和耗时（脚本监控用）
curl -X POST -H "Content-Type: application/json" -d '{"k":1}' http://x/api
curl -L URL                      # 跟随重定向
curl -v URL                      # 看完整请求响应过程（排障）
curl --resolve x.com:443:1.2.3.4 https://x.com   # 不改hosts指定IP测（CDN切换验证）

# wget：下载文件为主
wget URL                         # 下载当前目录
wget -O custom.tar.gz URL        # 指定保存文件名
wget -c URL                      # 断点续传
wget -q --spider URL             # 只探测不下载（-q静默）
wget -r -np -k URL               # 递归整站镜像
```
- **区别一句话**：curl 主打**与 URL 交互/调 API**（协议多、可发各种 method），wget 主打**下载文件**（递归下载、断点续传是强项）。
- 面试挂项目：**监控脚本用 `curl -s -o /dev/null -w '%{http_code}'` 判状态码非 200 就告警**——自己的告警脚本就是这么写的，比 ping 检测靠谱（ping 通不代表 HTTP 活着）。
- 追问「curl 返回 000」→ 连接都没建立（网络不通/证书/超时），配合 `-v` 看；`-m 10` 加超时防止脚本卡死。

---

## 十八、基础盲区第二轮（基础但容易从没想过的问题）★★

**80. Shell 到底是什么？bash / sh / zsh 区别？★★**
Shell 是**用户和内核之间的命令解释器**——你敲的命令它翻译成系统调用交给内核。图形界面是另一类 Shell（GUI Shell）。脚本第一行 `#!/bin/bash`（shebang）就是指定用哪个解释器执行。
- `sh`：最老的 Bourne Shell，很多发行版把它软链到 bash，但功能少。
- `bash`：Linux 默认，sh 的增强版（历史命令、Tab 补全、`[[ ]]`）。
- `zsh`：macOS 默认，补全更强，服务器一般不折腾。
- 查/换：`cat /etc/shells`、`echo $SHELL`、`chsh -s /bin/bash`。
- 追问「bash 和 sh 脚本区别」→ `#!/bin/bash` 能用数组和 `[[ ]]`；`#!/bin/sh` 是 POSIX 子集，写了 bash 特性会报错——**脚本开头必须写对 shebang**，不然 crontab 里跑挂了都不知道为什么。

**81. vi/vim 三种模式和必会操作？（课程必考，题库此前没有）★★★**
**普通模式**（打开默认，hjkl 移动）→ 按 `i a o` 进**插入模式**（i 光标前 / a 光标后 / o 下行新开）→ `Esc` 回普通模式 → 输 `:` 进**命令行模式**执行保存退出。
```vim
:wq        # 保存退出（:q! 不保存强退，:wq! 只读文件强存）
dd / ndd   # 剪切(删)当前行 / n行；yy / nyy 复制；p 粘贴
u          # 撤销；Ctrl+r 重做
gg / G     # 跳文件头 / 文件尾；nG 跳第n行；0 行首 $ 行尾
/关键字     # 向下搜索，n 下一个 N 上一个；? 向上搜
:%s/旧/新/g       # 全文替换（等价 sed，改配置文件神器）
:set nu           # 显示行号（永久写 ~/.vimrc）
```
- 追问「为什么服务器用 vim 不是其他编辑器」→ **任何精简系统都自带 vi**，救援模式里只有它，是兜底技能。
- 追问「改配置改坏了想撤销」→ u 撤销 / `:e!` 放弃本次全部修改重新载入文件。

**82. top 里 VIRT / RES / %wa 都是什么意思？★★★**
```
%Cpu(s): 10.3 us,  3.1 sy,  0.0 ni, 85.0 id,  1.2 wa,  0.0 hi,  0.4 si
  PID USER  VIRT  RES  SHR S %CPU %MEM COMMAND
 1234 mysql  3.2g 1.1g 200m S  5.0 55.0 mysqld
```
- **VIRT**：申请的**虚拟内存总量**（含没真正用的、映射的文件），大不可怕。
- **RES**：**实际占用的物理内存**，判断"谁吃内存"看它，不看 VIRT。
- **SHR**：共享内存（动态库、共享页）。
- CPU 拆解：`us` 用户态、`sy` 内核态、`ni` nice 调过的、**`id` 空闲、`wa` 等 IO**。
- **`wa` 高 = CPU 在等磁盘**，配合 `iostat -x 1` 看 `%util`——「高 load + 低 CPU + 高 wa」就是 IO 瓶颈的铁证（Q43 的判断依据）。
- 追问「hi/si」→ 硬中断/软中断，si 持续高常见于高流量网卡（可开 RSS 多队列）。

**83. 什么是文件描述符？"Too many open files" 怎么解决？★★★**
fd 是内核给进程打开的"东西"（文件、socket、管道）发的编号，**一切打开的资源都占 fd**。0=stdin、1=stdout、2=stderr（所以重定向才写 2>&1，见 Q60）。`ls /proc/<pid>/fd | wc -l` 看某进程用了多少。
```bash
ulimit -n                     # 当前进程限制（默认常是1024，太小）
cat /proc/<pid>/limits        # 看运行中进程的实际限制
# 永久：/etc/security/limits.conf
*  soft  nofile  65535
*  hard  nofile  65535
# systemd 服务还要在 unit 里加：LimitNOFILE=65535（★limits.conf 管不到 systemd 拉起的服务）
```
- 典型报错：Nginx `worker_connections` + fd 超限 500、MySQL `too many open files`、Java `Too many open files`——**高并发服务上线前必调**。
- 关联：`fs.file-max` 是**系统全局**的（Q49），ulimit 是**进程级**的，两层都要够。

**84. 服务器时间不准有什么影响？怎么同步？★★**
```bash
timedatectl                          # 看时区/时间/NTP同步状态
timedatectl set-timezone Asia/Shanghai
chronyc sources -v                   # 看NTP源（chrony，新系统标配）
ntpdate ntp.aliyun.com               # 老式一次性校时（服务运行时慎用，会跳变）
hwclock -w                           # 把系统时间写进硬件时钟（BIOS）
```
- **时间不准的实际危害**（必答，答影响比答命令加分）：① 日志时间错乱 → 排障对不上事件顺序；② cron 任务晚点/重复跑（备份脚本重叠）；③ **HTTPS/TLS 证书校验失败、Kerberos/token 类认证直接挂**；④ 数据库主从复制错乱；⑤ 支付/订单对账出错。
- 原则：**所有机器统一时区 + 指同一个 NTP 源**；大跨度跳变用 ntpdate 危险，`chronyd` 是平滑缓调。

**85. 怎么审计谁登录过服务器？★★**
```bash
w          # 此刻在线用户+在干什么（第一条就是load）
who        # 简版在线列表
last       # 历史登录记录（读 /var/log/wtmp），含来源IP、时长
lastlog    # 每个用户最近一次登录
lastb      # ★登录**失败**记录（/var/log/btmp）——被爆破会刷屏
grep sshd /var/log/secure    # SSH 详细日志（CentOS系）
```
- 追问「被暴力破解怎么办」→ `lastb` 确认来源 → 防火墙封 IP / 改端口 / `fail2ban` 自动封禁 / 关密码登录只留密钥（Q68）。
- 关联 Q68 加固三件套：禁 root 直登、改端口、只留密钥。**lastb 记录巨大也是磁盘坑**（btmp 会被爆破写爆）。

**86. 接手一台新服务器，你第一步做什么？（开放题，必考）★★★**
按顺序五步，答「流程」不答单个命令：
1. **认清机器**：`hostname`、`cat /etc/os-release`、`ip a`、`uptime`——这是什么机器、跑多久了。
2. **摸清资源**：`nproc` / `free -h` / `df -h`（含 `df -i`）/ `lsblk`——多少核多少内存，磁盘几个挂载点、哪块快满。
3. **看跑着什么**：`systemctl list-units --type=service --state=running`、`ss -tlnp`、`crontab -l`（root + 各用户）、`docker ps`——**服务清单和端口清单**。
4. **看安全状况**：`last | head`、`lastb | head`、`grep Accepted /var/log/secure`（谁在登）、`authorized_keys` 有没有陌生公钥、防火墙规则。
5. **看备份和监控**：备份脚本/cron 在不在、告警通道通不通——**先确认兜底，再谈变更**。
> 收尾一句：「确认现状之前不动任何配置，所有变更先记录再执行」——这句话体现的是生产意识，比命令值钱。

**87. root 密码忘了怎么办？★★**
物理机/自己可控的机器：**GRUB 单用户模式重置**——重启在 GRUB 菜单按 `e` → 找到 `linux16/linux` 行行尾加 `rd.break`（CentOS7+）→ `Ctrl+x` 启动 → 执行：
```bash
mount -o remount,rw /sysroot
chroot /sysroot
passwd root
touch /.autorelabel     # ★SELinux开着必须做，否则改完密码登不上
exit && reboot
```
- **云服务器不用这招**：控制台有 **VNC/救援模式**直接登，或"重置密码"功能——面试先答 VNC 再补 GRUB 方法，更贴云环境。
- 追问「.autorelabel 是干嘛的」→ 强制全盘重新打 SELinux 标签（因为 /etc/shadow 被改了上下文），不然后续登录被 SELinux 拦。

**88. 误删 rm -rf 了，数据还能救吗？★★**
诚实答（这题考的是认知不是命令）：
- **ext4**：立刻停止一切写入（最好直接关机挂到别的机器），有概率用 `extundelete`/`ext4magic` 抢救，成功率看运气。
- **XFS**：几乎**没戏**，没有成熟恢复工具。
- **云盘**：数据盘卸下来挂到新实例尝试恢复；最稳的是**云盘快照**。
- 所以正确答案是三层预防：**①定期备份（兜底）②不拿 root 跑业务、最小权限 ③高危操作加固**：
```bash
alias rm='rm -i'                    # 家目录，防手滑
rm -rf "${dir}/"                    # 变量为空时=rm -rf / ！生产脚本必须先判空
[ -n "$dir" ] || exit 1             # ★先判空再删——脚本里 rm 用变量的铁律
```
- 追问「为什么删了还能恢复」→ rm 只是把 inode 的数据块标记为空闲、链接数清零，**数据块内容还在**，没被新数据覆盖前可恢复；所以"立刻停止写入"是第一原则。

**89. SSH 突然连不上云服务器了，怎么排查？（技术支持日常）★★★**
由外到内八步：
1. **本地网络**：换个网络试（手机热点）——排除自己这边。
2. **控制台看实例状态**：是不是卡死/CPU 100% 被打满、欠费停机。
3. **安全组 22 端口放行没**（换过网络/换 IP 后最常见被拦）。
4. `ping` 通不通（不通可能是禁 ICMP，不代表服务挂）。
5. `ssh -v user@ip` 看**卡在哪一步**：卡 `Connecting`=网络层；卡 `Connection refused`=sshd 没起或端口不对；到 `Permission denied`=认证问题。
6. **认证问题细分**：密码错 / `authorized_keys` 或家目录权限不对（Q68）/ `sshd_config` 改坏了。
7. **进得去的话**看 `systemctl status sshd`、`/var/log/secure`（被 fail2ban/拒绝原因都在这）。
8. **系统都进不去**：控制台 **VNC** 兜底登录——「VNC 是最后手段，永远可用」，这句是技术支持岗的核心底气。
> 面试点睛：按「本地 → 网络 → 安全组 → 服务 → 认证 → VNC 兜底」分层说，体现的是排查框架而不是会几个命令。

**90. 终端/日志里中文乱码怎么解决？★★**
三处编码要一致，逐个查：
```bash
locale                        # 系统locale，看 LANG 值
export LANG=zh_CN.UTF-8       # 临时改；永久写 /etc/locale.conf
locale -a | grep zh           # 有没有生成中文locale（没有就 localedef 生成）
file 文件名                    # 确认文件本身的编码（GBK 还是 UTF-8）
iconv -f GBK -t UTF-8 old.log -o new.log   # 文件是GBK就转码，别硬看
```
- 远程终端自己也要设成 UTF-8（XShell/secureCRT 的会话编码）——「乱码不在服务器，在客户端设置」是常见真相。
- 追问「Windows 记事本打开 Linux 文件全是单行」→ 换行符差异：Windows CRLF（`\r\n`）vs Linux LF（`\n`），`dos2unix` 转；反过来 Windows 文件拿到 Linux 跑脚本报错 `/bin/bash^M` 也是这个原因（crontab 三坑之一，Q32）。

**91. 为什么服务器都用 Linux？和 Windows Server 比优劣势？（开放题）★★**
- **免费开源**：无授权费，云上成本优势；源码可审计可定制。
- **资源占用**：无图形界面，2G 内存照样跑全套服务——同一台机器能塞更多业务。
- **稳定**：连续运行数年不重启很常见，不适合的才重启。
- **命令行 + 脚本**：一切皆文件、管道组合、shell/systemd/Ansible 自动化，**适合批量运维**——Windows 图形界面难脚本化（PowerShell 在补但生态差一截）。
- **权限体系严格**：rwx + 属主属组 + SELinux，多用户隔离好。
- 诚实交底（加分）：**Windows 也有强项**——AD 域、SQL Server、.NET 系、桌面办公场景仍是它；国内中小互联网后端基本都是 Linux，问题不在谁好，在**场景匹配**。
- 技术支持视角补一句：两个都要会一点，支持岗经常是「Linux 服务器 + Windows 客户端」混合环境，能两边排查才值钱。

---

## 十九、基础盲区第三轮（最后一批高频基础）★★

**92. TCP 和 UDP 区别？各用在什么场景？★★★**（此前题库只有握手，没问过这个本体题）
- **TCP 面向连接**：三次握手建连、确认重传、排序、流控拥塞控制——**可靠但慢、开销大**。
- **UDP 无连接**：发出去就完事，不确认不重传——**快但不可靠**，头部只有 8 字节。
- 场景分家：**TCP** → HTTP/HTTPS、SSH、MySQL、SMTP（要求一个字节都不能丢）；**UDP** → DNS 查询（小包快问快答，超时重发就行）、视频直播（丢一帧无所谓，重传来的早过时了）、DHCP、心跳、游戏。
- 追问「DNS 为什么用 UDP 也可以用 TCP」→ 常规查询 UDP 53 快；**响应超过 512 字节或区域传送用 TCP 53**。
- 追问「UDP 怎么做到可靠」→ 应用层自己做确认重传（QUIC/KCP 的思路），一句话点出 QUIC 即加分。
- 追问「视频会议为什么不用 TCP」→ 实时性 > 完整性：重传一个过期帧没意义，宁可丢帧也不卡顿。

**93. 公网 IP 和私网 IP 怎么区分？NAT 是什么？★★**
- **私网段必背**（RFC1918）：`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`——只在局域网内有效，**不可在公网路由**。其余基本都是公网。
- **NAT（网络地址转换）**：内网多台机器共享公网 IP 出网——出方向改源 IP+端口，回包改回来。家里路由器、云平台都是这个原理。
- **云上对应关系**（挂自己的 2C2G）：`ip a` 里看到的是**私网 IP**（VPC 内互通用）；**公网 IP 是控制台映射的，网卡上看不到**——`curl ifconfig.me` 才能看到出网公网 IP。别人访问你的公网 IP，云平台把 80/443 流量 DNAT 到你的实例。
- 追问「两台服务器 ping 不通对方公网 IP」→ 公网 IP 走外环回到云平台再 DNAT，**内网机器间应该走私网 IP 互通**（同 VPC 安全组放行内网段），这是云上最佳实践也省公网带宽费。
- 追问「EIP 是什么」→ 弹性公网 IP，独立申请可绑定/解绑到任意实例，换机器不用换 IP。

**94. `ls -l` 输出的每一列是什么意思？★★**
```
-rw-r--r--.  1 root root  1024 Oct 30 10:00 app.conf
①权限位 ②SELinux标记 ③链接数 ④属主 ⑤属组 ⑥字节 ⑦mtime ⑧文件名
```
- ① 10 位：第 1 位类型（`-`文件 `d`目录 `l`链接 `b/c`设备），后 9 位三组 rwx。
- ③ **链接数**：文件=硬链接数；**目录最少是 2**（自身 `.` + 父目录里那条记录），子目录数 = 链接数 − 2——「怎么数一个目录有几个子目录」就看这。
- ⑥ 目录显示 4096 是**目录这个"文件"（存文件名列表）本身的大小**，不是里面内容总大小——算目录占用用 `du -sh`。
- ⑦ 默认显示 mtime（内容修改时间）；`ls -l --time=atime/ctime` 切换（三个时间戳见 Q70）。
- 追问「`.` 结尾那个点」→ SELinux 上下文存在；`+` 表示有 ACL。

**95. 终端快捷键和历史命令技巧？（日常效率，也单独被考）★★**
```bash
Ctrl+C  中断当前命令（SIGINT）          Ctrl+Z 挂起到后台（配 fg/bg，Q15）
Ctrl+D  EOF/退出（相当于 exit）★       Ctrl+L 清屏（= clear）
Ctrl+R  搜历史命令（再按跳下一条）★     Ctrl+A/E 行首行尾；Ctrl+U/K 删前/后
history        # 历史（~/.bash_history，退出时才落盘）
!!             # 上一条命令（忘 sudo 时：sudo !!）
!$ / Alt+.     # 上一条命令的最后一个参数
!ssh           # 执行最近一条以 ssh 开头的
```
- 追问「Ctrl+C 和 Ctrl+Z 区别」→ C 是**杀掉**进程，Z 是**挂起**（进程还在，jobs 里能 fg 回来）——高频对比题。
- 追问「Ctrl+D 干嘛的」→ 发送 EOF：空行时=退出会话；写交互输入时=结束输入（`cat > f` 按 Ctrl+D 收尾）。
- 追问「history 什么时候能看到别的会话的命令」→ 默认退出才写入 `.bash_history`，多会话历史会互相覆盖；`HISTSIZE/HISTTIMEFORMAT` 可调条数和带时间。

**96. IO 打满怎么定位到具体进程？（比 iostat 再进一层）★★★**
Q43/Q82 判断出「高 load + 高 wa = IO 瓶颈」，追问就是**谁在刷 IO**：
```bash
iostat -x 1          # 先确认设备级：%util≈100 饱和，await 高=响应慢
iotop -o             # ★按进程看实时读写（-o 只显示有IO的）——一步定位
pidstat -d 1         # 每秒输出各进程 kB_rd/s kB_wr/s（无iotop时的替代）
lsof +D /data        # 看某个目录下正被哪些进程打开（+D 会递归，慢）
cat /proc/<pid>/io   # 单个进程累计读写量
```
- 典型结论要说出来：**备份脚本和业务抢 IO**（自己 2C2G 上的真实场景：凌晨 mysqldump 压缩期间 `%util` 拉满、网站变慢）→ 对策就是 Q51 的**错峰调度 + ionice 降备份 IO 优先级**。
- 追问「iotop 装不上/没有」→ `pidstat -d 1`（sysstat 包）效果等价。
- 追问「除了读写还有什么 IO」→ `bi/bo`（vmstat 块设备收发）、fsync 落盘；数据库机器关注 `await` 而不是只看 `%util`。

**97. 带宽吃满/网速慢怎么定位？（网络侧补齐"卡"家族）★★**
```bash
iftop -nP            # ★按连接看实时流量（谁和谁在传，走哪个端口）
nethogs              # ★按进程看流量（iftop是按连接，nethogs直接给进程）
sar -n DEV 1         # 每块网卡收发速率（sysstat，历史数据也能回看 sar -n DEV -f）
ss -tn               # 连接数视角，配合上面定位
ethtool eth0         # 网卡协商速率（Speed: 1000Mb/s）
```
- 排查链：`sar` 确认网卡打满 → `iftop` 看是哪条连接 → `nethogs` 落到进程 → 是业务还是异常（挖矿外传、日志狂推、被当跳板）。
- 经典场景：**日志同步打满带宽**（rsync 全量没排除大文件）、**容器里进程疯狂外连**——对应 Q74 挖矿排查。
- 追问「为什么下载只有 12.5 MB/s」→ 运营商说的 100M 是 **100 Mbps**，除以 8 = 12.5 MB/s，bps 和 B/s 差 8 倍，基础送分题。
- 至此「服务器很卡」四件套闭环：**CPU（top）→ 内存（free）→ 磁盘 IO（iostat/iotop）→ 网络（iftop/sar）**。

**98. 云主机明明资源不高却很卡？——CPU steal（%st）★**
`top` 里 `%st`（steal）：** hypervisor 把本该给你的 CPU 时间片偷给了同宿主机的其他虚拟机**——云上"超卖/邻居效应"的直接证据。
- `%st` 持续 >5% 说明抢不到 CPU：换规格（独享型 vs 共享型）、错峰、或联系云平台；2C2G 入门款尤其常见。
- 对照概念：突发性能实例（T 系列）的 **CPU 积分耗尽**也会"资源看着不高却卡死"——控制台看 CPU 积分曲线。
- 加分答法：「云主机排查比物理机多一步——先排除平台因素（steal、积分、宿主机迁移），再查系统内」，一句话体现云上经验。

**99. 快照和备份是一回事吗？★★**（云上天天用，概念不清容易露馅）
| | 快照 | 备份 |
|---|---|---|
| 本质 | 磁盘**某一时刻的块级影像**（COW，秒级生成） | 把数据**导出成独立副本**（mysqldump/tar） |
| 存放 | 通常和源盘在同一存储体系 | 可异地、可跨账号、可下载 |
| 粒度 | 整盘/整卷 | 可精确到库表、文件 |
| 恢复 | 整盘回滚（**全部覆盖回去**） | 可只恢复一个库、一张表、一个文件 |
| 典型 | 变更前打快照（改 fstab 前、升级前） | 每日定时备份 + 异地容灾 |

- 正确关系：**快照解决"变更可回退"，备份解决"数据可找回"**，生产两个都要。
- 追问「只做快照行不行」→ 不行：源盘所在存储故障/误删云盘，快照可能一起没；且**整盘回滚没法只捞一个文件**（其实可从快照创建新盘挂载捞文件，这是个正确姿势，可主动说）。
- 挂项目：自己的方案是「应用层备份（mysqldump+tar）+ 云盘定期快照」双保险。

**100. yum 源是什么？怎么换源？★★**（装软件必涉及，实操日常）
- yum 源 = 软件仓库的地址清单，在 `/etc/yum.repos.d/*.repo`；`baseurl` 或 `mirrorlist` 指向仓库，元数据缓存在 `/var/cache/yum`。
```bash
yum repolist                     # 看当前源和包数量
yum makecache                    # 刷新元数据
dnf config-manager --set-enabled PowerTools   # 启用附加仓库（CentOS8+/OpenCloudOS）
```
- **换阿里云源**（国内提速标准操作）：备份 `CentOS-Base.repo` → 下载对应版本的 `.repo` 覆盖（版本要和 `/etc/os-release` 匹配，Q 上文 os-release）→ `yum clean all && yum makecache`。
- **EPEL**：官方源之外的社区扩展包仓库，`dnf install epel-release`（htop、iotop、fail2ban 很多在这）。
- **离线场景**：`yum install --downloadonly --downloaddir=/tmp/pkg 包` 只下载不装，拷到内网 `yum localinstall *.rpm`（自动解依赖）——比裸 rpm 聪明，呼应 Q47。
- 追问「yum install 报 404/找不到」→ 系统版本 EOL（老 CentOS 7 源下线了）或仓库没启用，`yum repolist` 先看。

**101. 计划任务写在哪几个地方？区别是什么？★**
| 位置 | 格式 | 特点 |
|---|---|---|
| `crontab -e`（当前用户） | 五段 命令 | 每用户一份，存 `/var/spool/cron/`，**没有用户列** |
| `/etc/crontab` | 五段 **用户** 命令 | 系统级，**多一个用户字段**（写 root） |
| `/etc/cron.d/xxx` | 同 /etc/crontab | ★推荐系统任务用这里：一个任务一个文件，好管理、随包分发 |
| `/etc/cron.{hourly,daily,weekly,monthly}` | 只丢脚本 | 由 anacron/run-parts 定时整目录执行，不用写时间 |

- 常见坑：在 `/etc/crontab` 里用了用户 crontab 的五段格式 → 命令被当成用户名报错；反过来在 cron.d 忘写用户列同样挂。
- 验证：`cat /var/log/cron` 看有没有真正执行；`systemctl status crond` 确认守护进程活着。
- 追问「crontab 和脚本怎么配合」→ crontab 里只写一行 `bash /path/x.sh >> log 2>&1`，逻辑全在脚本里（可版本控制、可手工重跑），呼应 Q32 三坑和 Q51。

---

## 二十、最基础入门（第 0 层保底题）★

> 越基础越没人准备。这些题技术支持实习生面试**开口概率极高**，答不上比场景题挂了更伤。

**102. 什么是 Linux？发行版又是什么？★★**
- 严格说 Linux 只是**内核**（管进程/内存/驱动/文件系统），加上 GNU 工具（bash、coreutils）和各种软件**打包发行**，才是能用的操作系统——这套打包就叫**发行版（Distribution）**。
- 两大主流家族：
  - **Red Hat 系**（rpm/yum/dnf）：RHEL（付费企业版）→ CentOS（曾免费克隆，2020 转型）、**Rocky/AlmaLinux**（接替 CentOS）、**OpenCloudOS**（腾讯开源，自己项目用的）、openEuler、麒麟（信创国产）。
  - **Debian 系**（deb/apt）：Debian（社区鼻祖）→ **Ubuntu**（Canonical，桌面/云原生强）。
- 追问「你用的什么系统」→ 如实答「云上 OpenCloudOS，Red Hat 系，兼容 RHEL 生态」，再把 CentOS→Rocky 的来龙去脉说一句，比背表真实。
- 追问「内核版本怎么看」→ `uname -r`；发行版看 `cat /etc/os-release`（Q 上下文）。

**103. CentOS 和 Ubuntu 区别？★★**
| | CentOS/Rocky/OpenCloudOS | Ubuntu |
|---|---|---|
| 包管理 | rpm / **yum→dnf** | deb / **apt** |
| 发布节奏 | 跟随 RHEL，企业级稳健 | 半年一版，**LTS 每 2 年一版支持 5 年** |
| 默认日志 | /var/log/messages | /var/log/syslog |
| 防火墙 | firewalld | ufw（底层同 iptables） |
| 软件新度 | 偏保守 | 更激进，社区包全 |
| 典型场景 | 国内传统企业服务器主流 | 云原生/Docker 镜像、开发机、桌面 |

- 底层一致：都是 Linux 内核 + systemd，**命令 90% 通用**，换发行版主要是换包管理器。
- 追问「生产选哪个」→ 跟公司现有运维体系走；国内老系统 CentOS 居多，新项目很多直接上 Rocky 或 Ubuntu LTS；答「我项目用的 OpenCloudOS，和 RHEL 系命令一致」落地。

**104. 登录后的提示符 `[root@web01 ~]#` 怎么读？★**
- 格式：`[用户@主机名 当前目录]提示符`。**`#` 是 root，`$` 是普通用户**——看提示符先确认"我是谁"，误操作root是事故第一来源。
- `~` 是当前用户的家目录（root 是 `/root`，普通用户 `/home/xxx`），不是"根目录" `/`——**基础送分但真有人答错**。
- 改主机名：`hostnamectl set-hostname web01`（重开终端生效，配 `/etc/hosts` 本地解析）。
- 提示符样式由 `PS1` 控制（`echo $PS1`），配色和显示 git 分支都靠改它。

**105. 绝对路径和相对路径区别？★**
- **绝对路径**：从根 `/` 写起（`/etc/hosts`），任何位置都有效，写脚本/服务配置**一律绝对路径**（呼应 crontab PATH 坑）。
- **相对路径**：相对当前目录。`.` 当前、`..` 上一级、`~` 家目录、`-` 上一次所在目录（`cd -`）。
- 经典追问「执行脚本为什么要 `./xxx.sh`」→ **PATH 里默认不包含当前目录**（安全设计，防止伪造 `ls` 劫持命令），所以要显式指定相对路径 `./`，或者把脚本目录加进 PATH。
- 追问「`.` 开头的文件是什么」→ 隐藏文件，`ls -a` 才显示（`~/.bashrc` 就是一个）。

**106. 看文件内容用哪些命令？★**
```bash
cat f.txt        # 一次性全部输出——小文件用，大文件刷屏卡死终端
less big.log     # ★大文件分页：空格翻页 /关键字搜索 n下一个 q退出（必会）
head -n 20 f     # 前20行                 tail -n 50 f    # 后50行
tail -f app.log  # 实时追加跟踪（看日志标配，Ctrl+C 退出）
tail -f app.log | grep --line-buffered ERROR   # 实时过滤
```
- 口诀：**小 cat、大 less、实时 tail -f**。
- 追问「tail -f 和 tail -F 区别」→ `-F` 文件被轮转（logrotate 改名重建）后**继续跟踪新文件**，看日志长期挂着用 `-F` 更稳。
- 追问「cat 和 tac」→ tac 倒着输出（冷知识，一般没人用）。

**107. 命令不会用怎么办？怎么查帮助？★**（考的是自学能力）
```bash
man ls           # 完整手册：空格翻页、/搜索、q 退出
ls --help        # 快速参数速查（很多命令 -h 等价）
whatis ls        # 一句话说明（查 man 数据库）
man 5 passwd     # ★分节：1=用户命令、5=配置文件格式、8=管理命令
type cd          # 内建命令 man 查不到，用 help cd
```
- **`man 5 passwd` 经典题**：`man passwd` 看到的是命令，想看 `/etc/passwd` 文件格式得 `man 5 passwd`——答出分节就高于 90% 候选人。
- 追问「离线/查不到」→ 命令 `-h`、官方文档、以及「我会先 man，再搜索引擎+官方 wiki，最后自己起测试环境验证」的答题姿态。

**108. 怎么安全关机和重启？★**
```bash
shutdown -h now          # 立即关机（-h halt）
shutdown -r +10 "10分钟后重启做内存升级"   # 定时重启+通知在线用户 ★生产姿势
shutdown -c              # 取消刚才的 shutdown
reboot / init 6          # 重启
```
- 生产流程：**先通知（shutdown 自带广播）→ 先 sync 刷盘 → 再关机**；`shutdown` 会正常停止服务、卸载文件系统，和直接拔电是两回事。
- **为什么不能硬断电**：写到一半的数据没落盘 → 文件系统损坏（ext4 有日志能救，XFS 也要修复），数据库更可能直接坏页——所以云控制台的「强制重启」永远是最后手段。
- 云上补充：控制台「重启」= 正常 shutdown 流程；「强制重启」= 等于拔电，仅卡死时用。

**109. 用一句话概括 Linux 的核心特性？（开放题保底）★★**
- **开源免费**：可审计可定制；**多用户多任务**：多账号并行、权限隔离（rwx+属主属组）；
- **一切皆文件**：设备、进程信息（/proc）、socket 都用文件接口统一访问；
- **稳定**：服务器连续跑数年；**命令行+管道可组合**：小命令拼成自动化脚本。
- 两个常被忽视的小特性：**严格区分大小写**（`File.txt` 和 `file.txt` 是两个文件）；**扩展名无意义**（`.txt` 也能是脚本，真实类型看 `file 命令`）——Linux 靠权限位和内容识别文件，不靠后缀。

**110. 身份/系统信息类小命令，一口气说全？★**
```bash
whoami / id        # 我是谁 / UID+GID+所属组（权限问题第一步先 id）
hostname           # 主机名；hostnamectl 系列改
uname -r / -a      # 内核版本 / 全部信息
uptime             # 开机时长 + load（Q43）
date               # 系统时间；date +%F_%T 出日志时间戳
lscpu / nproc      # CPU 详情 / 核数（load 对标核数用）
clear / echo $?    # 清屏 / 上条命令返回码（0成功，脚本判断靠它）
```
- 追问「`echo $?` 什么时候用」→ 脚本里判断上一步成败：`if [ $? -ne 0 ]; then 告警; fi`——链接 Q51 备份脚本的失败告警。

---

## 自检清单

- [ ] 不看答案说清：inode、软硬链接、僵尸进程、load 高怎么办
- [ ] 默写：`ss -tlnp`、`kill -9/-15` 区别、`crontab` 五段、free 看 available
- [ ] 白板画出：启动流程、三次握手、磁盘 df/du 不一致的排查
- [ ] 能跑：找大文件、看端口占用、统计日志 IP TopN
- [ ] 能说清：`/dev` 块/字符设备、rpm vs yum、firewalld 配端口、sysctl 永久生效、三个坑
- [ ] 能说清：备份四件套（库/代码/告警/心跳）、crontab 错峰、恢复演练
- [ ] 能背：挂盘八步、fstab 六列、LVM 三层、RAID 级别表、云盘扩容三步
- [ ] 能解释：`2>&1` 顺序、su/sudo、rsync 增量、free 的 available、swap 添加、SSH 免密坑
- [ ] 能背：cp -a、find -mtime +7 -delete、`sort|uniq -c|sort -rn`、zgrep、压缩三剑客区别
- [ ] 能实操：CPU 100% 排查七步、MBR/GPT 区别、partprobe、nmcli 配静态 IP
- [ ] 能分层：网络不通先 ping 再端口再 curl；ping 不通 ≠ 服务不通
- [ ] 能说：curl vs wget、at vs cron、目录 rwx 含义、xargs vs -exec、uniq 先 sort
- [ ] 能盲打：vim 三模式、dd/yy/p/:%s、/搜索、:wq 与 :q!
- [ ] 能读：top 的 VIRT/RES/wa、ulimit -n 与 systemd LimitNOFILE、locale 排乱码
- [ ] 能排：chrony 时区、last/lastb 登录审计、SSH 连不上八步、VNC 兜底
- [ ] 能答：接管新服务器五步、root 密码重置（GRUB + .autorelabel）、rm -rf 恢复认知
- [ ] 能说：Shell 是解释器、shebang 作用、为什么服务器用 Linux、CRLF 坑
- [ ] 能对比：TCP vs UDP + 场景、快照 vs 备份、Ctrl+C vs Ctrl+Z、私网三段
- [ ] 能读：ls -l 八列、链接数-2=子目录数、%st steal、bps÷8=字节
- [ ] 能定位：iotop/pidstat 找 IO 进程、iftop/nethogs 找流量进程
- [ ] 会操作：换 yum 源+EPEL、cron.d 格式（多用户列）、Ctrl+R 搜历史
- [ ] 保底题不打磕巴：发行版两家族、CentOS vs Ubuntu、# 和 $、绝对/相对路径
- [ ] 保底题不打磕巴：cat/less/tail -F、man 5 passwd、shutdown -h now、大小写敏感
