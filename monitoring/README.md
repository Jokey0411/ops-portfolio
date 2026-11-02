# Zabbix 7.0 LTS —— 项目一的监控告警

给 `project1-cluster` 配一个**外部观察者**：它不依赖被监控对象自证，
而是从外面看「服务还在不在、数据还在不在、备份还来不来」。

---

## 为什么单独一个 compose，不并进项目一

| 理由 | 说明 |
|------|------|
| **生命周期不同** | 监控要比业务活得久。`project1-cluster` down 掉时，监控必须还在，才能看见「目标消失了」 |
| **依赖方向单一** | 监控 → 项目一，单向。混在一起会让 `depends_on` 形成环，compose 起不来 |
| **可单独撤离** | 2G 机器内存吃紧时，`docker compose stop` 本目录，业务零影响 |

**它只做一件事：往上依赖项目一的 `cluster-p1_front` 网络。** 项目一对它一无所知。

---

## 内存预算（2G 机器的生死线）

| 组件 | 上限 | 实测 |
|------|------|------|
| postgres | 256M | ~90M |
| zabbix-server | 400M | ~200M |
| zabbix-web | 256M | ~150M |
| zabbix-agent2 | 64M | ~30M |
| **合计** | **976M** | **~470M** |

```
系统 250M + 项目一 1100M + Zabbix 470M ≈ 1.8G
```

**所以项目二必须 down。** 三个项目 + Zabbix 同时跑会直接 OOM，
最先被内核杀掉的通常是 `node1-db`（内存大户），表现是「主从突然断了」——
到那时你会去查 SQL，而真正的原因是内存。

---

## 端口

| 宿主机 | 容器 | 用途 | 安全组 |
|--------|------|------|--------|
| 8080 | zabbix-web:8080 | Web 界面 | 要放通（或只放行你家的 IP） |
| 10051 | zabbix-server | Server 监听 / 主动模式 | 内网够用，公网可不放 |
| 10050 | zabbix-agent2 | Server 拉取数据 | 同上 |

80 已被项目一的 `lb` 占用，所以 Web 走 8080。

---

## 启动顺序（有依赖，别跳）

```bash
# ① 项目一必须在跑，且 cluster-p1_front 网络已存在
docker network ls | grep cluster-p1_front

# ② 项目二必须停（省 400M）
cd /opt/ops/project2-lnmp && docker compose down && cd -

# ③ 起监控
cd /opt/ops/monitoring
docker compose up -d

# ④ 等数据库初始化 + server 建表，约 60~90 秒
docker compose ps
docker logs -f zbx-server      # 看到 "server #0 started" 即可 Ctrl-C
```

**`docker compose down` 不要加 `-v`**，加了会删掉 `zbx-pgdata`，所有监控数据和配置归零。

---

## 首次登录

```
http://<公网IP>:8080
用户名 Admin
密码   zabbix
```

进去第一件事改密码（Administration → Users → Admin → Change password）。
默认密码是全网扫描器每天都会试的那个。

---

## 七个必踩的坑

### ① 主机接口填 `zabbix-agent2`，不能填 `127.0.0.1`

Zabbix Server 跑在容器里，`127.0.0.1` 指的是它自己那个容器，
不是宿主机。填了会一直显示 `ZBX_TCP_READ_ERROR` / connection refused。

正确填法（Data collection → Hosts → 你的主机 → Interfaces）：

```
Agent  →  DNS name: zabbix-agent2     Port: 10050
```

因为 server 和 agent 同在 `monitoring_zbx` 这个 bridge 网络里，
容器名就是可解析的 DNS。

### ② `pid: host` 不能省

省掉之后，内置的 `Linux by Zabbix agent` 模板采到的 CPU/内存
是 **agent2 容器自己的**，不是宿主机的——数字看着「合理」所以极难发现。
判断方法：容器内存 limit 是 64M，如果报的内存总量是 64M 左右，就是采错了。

### ③ 挂载整个 `plugins.d` 目录 → agent2 启动即退出

**症状**：`zbx-agent2` 不停重启（`restarts` 几十次），`docker exec` 报
`is restarting, wait until the container is running`，日志只有一行：

```
[error]: Missing configuration file:
         /etc/zabbix/zabbix_agent2.d/plugins.d/mongodb.conf
```

`exit=1`、`oom=false` —— **不是内存，是配置文件缺了**。

**根因：bind mount 是「覆盖」不是「合并」。**

镜像自带的 `/etc/zabbix/zabbix_agent2.d/plugins.d/` 里有 7 个文件：

```
docker.conf  memcached.conf  mongodb.conf  mysql.conf
oracle.conf  postgresql.conf  redis.conf
```

而 `zabbix_agent2.conf` 里是**逐个文件显式 Include** 的，不是通配符：

```nginx
Include=/etc/zabbix/zabbix_agent2.d/plugins.d/mongodb.conf
Include=/etc/zabbix/zabbix_agent2.d/plugins.d/mysql.conf
...
```

所以一旦这样挂：

```yaml
- ./zbx-agent/plugins.d:/etc/zabbix/zabbix_agent2.d/plugins.d:ro   # ❌
```

容器里那个目录**只剩你自己的文件**，其余 5 个消失 → 显式 Include 找不到 →
agent2 判定配置不完整 → `exit 1` → `restart: unless-stopped` 无限重来。

**正确写法（二选一）**

① 只挂单个文件，绝不挂目录：

```yaml
- ./zbx-agent/userparams.conf:/etc/zabbix/zabbix_agent2.d/userparams.conf:ro   # ✅
```

② **本项目最终采用：一个都不挂。**

业务指标改走宿主机 push（见「采集架构」一节），agent2 里不再需要任何自定义配置，
所以 `zabbix_agent2.d/` 下的东西全部保持镜像原样，从根上消除了这个风险。

**而且 `docker.conf` 根本不需要自己提供** —— 镜像自带的就是：

```nginx
Plugins.Docker.Endpoint=unix:///var/run/docker.sock
Plugins.Docker.Timeout=3
```

只要 `/var/run/docker.sock` 挂着，Docker 插件的采集能力一点不减。
「为了显式可读」而挂载整个目录，代价是 agent2 起不来。

**判断口径**：

| 现象 | 结论 |
|------|------|
| `exit=1` + `Missing configuration file` | 挂载盖掉了镜像自带配置 |
| `exit=137` + `oom=true` | 内存不足，看 `mem_limit` |
| `exit=1` + `cannot parse` / `unknown parameter` | 自己的 conf 有语法错误 |

> 这一条和第 8 坑（`COPY` 快照 vs bind mount 通道）同源：
> **挂载能给你东西，也能拿走东西。挂目录之前先想清楚那里面原来有什么。**

### ④ 一堆 item 变 `not supported`（不是故障，但必须清）

首次起来后日志会刷这类行：

```
item "Zabbix server:zabbix[vmware,buffer,pused]" became not supported:
    No "vmware collector" processes started.
item "Zabbix server:zabbix[process,report writer,avg,busy]" became not supported:
    No "report writer" processes started.
item "Zabbix server:zabbix[process,report manager,avg,busy]" became not supported:
    No "report manager" processes started.
```

**能打出这些行，说明 server 是好的** —— 它读到了 PG 里的 item 配置、执行了检查、写下了日志。真挂了会一条都没有。

根因：`Zabbix server health` 模板的覆盖面**大于**我们精简后的进程集。
模板通过 LLD（`zabbix[process,,,]`）枚举**二进制里编译进去的所有进程类型**，
不管你有没有 `ZBX_START*` 启动它。没启动的进程，`avg,busy` 自然取不到值。

我们只启了 pollers / pingers / discoverers / httppollers / trappers，
而这三类默认是 0：

| item | 需要的进程 | 我们的值 | 启动它的代价 |
|------|-----------|---------|-------------|
| `zabbix[process,report writer,...]` | report writer | 0 | +10~20MB，且要先建额外表 |
| `zabbix[process,report manager,...]` | report manager | 0 | +5MB，只为定时报表 |
| `zabbix[vmware,buffer,pused]` | vmware collector | 0 | +5MB，本项目没有 vCenter |

三个都是「7.0 新增的报表/虚拟化能力」，**2 核 2G 上不值得开**。

**处理：在界面里批量禁用（不是删除）**

1. `Data collection` → `Hosts` → 点 `Zabbix server` → `Items`
2. 右上 Filter 里 **State** 选 `Not supported` → `Apply`
3. 勾选表头复选框（全选）→ 底部按钮 `Disable`

> 选 **Disable 而不是 Delete**：LLD 下次重新发现会把删掉的 item 再建回来，
> 而 `disabled` 状态会被保留。这是 Zabbix 的 lost-resource 规则。

**为什么必须清掉**：not supported 的 item 每 **10 分钟**重试一次，
一天就是 400+ 行噪音。而这些噪音会**盖住真正要紧的错误**——
和第 15 坑（diagnostic 被关）、第 16 坑（tar 报错被重定向）是同一类错误：
**信号被自己的噪音淹掉**。

**随时查全部 not supported 项**（换主机、换模板后都用得上）：

```bash
docker exec -e PGPASSWORD='ZbxPg@2026' zbx-postgres psql -U zabbix -d zabbix -c "
SELECT h.host, i.name, i.key_
FROM items i JOIN hosts h ON h.hostid = i.hostid
WHERE i.state = 1 AND i.status = 0 AND h.status = 0
ORDER BY h.host, i.key_ LIMIT 40;"
```

> `status` 是启用/禁用（0/1），`state` 是正常/不支持（0/1）。两个字段常被搞混：
> 查「报错但还开着」用 `state=1 AND status=0`。

### ⑤ 数据库不会自动建表（首次）

如果 `zbx-server` 起来后又反复重启，日志里有
`relation "config" does not exist`，说明 schema 没导入。手动补：

```bash
docker run --rm zabbix/zabbix-server-pgsql:alpine-7.0-latest \
  cat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz > /tmp/server.sql.gz

zcat /tmp/server.sql.gz | docker exec -i zbx-postgres psql -U zabbix -d zabbix

docker restart zbx-server
```

### ⑥ alpine 容器里跑不了宿主机的 docker 二进制

**症状**：`docker exec zbx-agent2 /usr/bin/docker --version` 返回

```
exec /usr/bin/docker: no such file or directory
```

但 `ls -l /usr/bin/docker` 在宿主机上明明有，`-v` 挂载也写了。

**原因：缺的不是文件，是 ELF 装载器。**

glibc 编译的动态链接程序，头部 `PT_INTERP` 段指向
`/lib64/ld-linux-x86-64.so.2`。alpine 用 musl，只有
`/lib/ld-musl-x86_64.so.1`，没有 glibc 那个装载器。
内核 `execve()` 找不到解释器 → 直接 `ENOENT` → shell 报「文件不存在」。

两种报错要分清：

| 报错 | 含义 |
|------|------|
| `error while loading shared libraries: libc.so.6` | 装载器找到了，但它要的**库**没有 |
| `no such file or directory`（文件确实存在） | **装载器本身**就没有，加载还没开始 |

**为什么不下载静态 docker 二进制绕过去**：能行，但要 70MB+
（`download.docker.com` 拉，国内还慢），而且以后每次升级 docker 都要同步换这个
二进制，是个长期负担。**只为了跑一条 `docker exec`，不值得。**

**本项目采用的解法**：把需要 docker CLI 的采集整体移到**宿主机**执行，
用 `zabbix_sender` 把结果推给 server（见「采集架构」）。宿主机上 docker CLI 原生可用，
没有任何兼容问题。

> 这条和第 17 坑（`bash: scripts/xxx.sh: No such file`）症状几乎一样、根因完全不同：
> 那次是**路径写错**，这次是**依赖链断了**。看到「文件不存在」先别急着 `ls`，
> 先问一句：**它是在哪里执行这个文件的？**

### ⑦ 告警级别是位掩码，少勾一格等于关掉一整档

**症状**：触发器正常、Action 启用、Operation 有、收件人有、媒介启用，
但手机**一条消息都没有**，`Action log` **一片空白**，`alerts` 表也**没有新记录**。

**原因：`media.severity` 是位掩码，不是「最低级别」。**

| 级别 | 位值 |
|---|---|
| Not classified | 1 |
| Information | 2 |
| Warning | 4 |
| **Average** | **8** |
| High | 16 |
| Disaster | 32 |

`severity = 7` 意味着 `1+2+4`，**只覆盖 Warning 及以下**。
如果触发器是 Average（位值 8），`7 & 8 = 0` → 这条 media 被过滤 →
收件人集合为空 → Zabbix **静默丢弃**，连 `status=2` 的失败记录都不写。

```
mediaid | mediatypeid | active | severity |     period
--------+-------------+--------+----------+-----------------
      1 |          72 |      0 |        7 | 1-7,00:00-24:00
                                      ↑ 这里，平均值不包含
```

**修法**：`Users → Users → Admin → Media` → 点那条 media →
`Use if severity` 里**逐格全部勾上**（包括 `Not classified`）→ 保存两次（弹窗 Update + 页面底部 Update）。
之后 `severity` 应变成 `63`。

**这条最阴的地方是方向反了**：`severity=7` 的监控**只通知轻问题，严重问题全部静默**
——越严重越收不到。而界面上你看不出任何异常。

**排查口诀**：`alerts` 表有没有记录，一次就能分三种情况。

| alerts 表 | 含义 | 查什么 |
|---|---|---|
| 有，`status=1` | 发出去了 | 钉钉侧（发错群 / 限流） |
| 有，`status=2` | 发了但失败 | `error` 列写原因 |
| **没有** | **算出空收件人，根本没发** | action / operation / 收件人关联 / media |

两个容易上当的**假线索**：

- 前端红字 `At least one user or user group must be selected` → Zabbix 7.0 校验缺陷，数据库里配置是好的
- `Test` 按钮通过 → 它只测 media type 本身，**绕过用户配置、绕过 severity、绕过 action 匹配**

完整排障过程见 `docs/08` 第 20 坑。

---

## 采集架构：两条链路，一条 pull 一条 push

这不是「两套监控」，是**同一个人做两件不同性质的事**。区别在于
「谁能拿到数据」——agent2 在容器里，有些东西它天生看不到。

```
链路 A（pull，agent2 主动上报）
  zabbix-server ──10050──> zbx-agent2 ──docker.sock──> dockerd
                                  │
                                  └─ pid:host ──> 宿主机的 /proc
  采集：CPU / 内存 / 磁盘 / 网络 / 7 个容器的存活与资源

链路 B（push，宿主机脚本推送）
  宿主机 cron ──> scripts/host_checks.sh
                    ├─ docker exec node2-db mysql  → 主从延迟、复制状态
                    ├─ stat 最新备份文件           → 备份年龄
                    └─ docker run zabbix_sender ──10051──> zabbix-server
  采集：shop.repl.lag / shop.repl.running / shop.backup.age
```

**为什么业务指标必须走 B，不能走 A**：读主从状态要 `docker exec`，
而 agent2 是 alpine(musl)，宿主机的 docker 是 glibc 动态链接的，
挂进容器后执行直接报：

```
exec /usr/bin/docker: no such file or directory
```

这个报错极具误导性——文件在宿主机上明明在。真实原因是 **ELF 装载器**
`/lib64/ld-linux-x86-64.so.2` 在 alpine 里不存在，内核 `execve()` 返回 ENOENT。
**缺的不是文件，是它的依赖链。**

**为什么不用「脚本写文件 + agent 用 `vfs.file.contents` 读」**：
那条路能跑通、零依赖，但有个致命缺陷——cron 挂了以后，agent 会
**一直返回文件里的旧值**。监控图一切正常，实际早就没人采集了。
push 模式下 cron 一挂就没数据，item 立刻 stale，触发器能抓到。
**不要让数据骗你**，这是本项目反复出现的主题（第 15、18 坑都是同一个道理）。

| 指标 | 链路 | item 类型 | key |
|------|------|-----------|-----|
| CPU / 内存 / 磁盘 / 网络 | A | Zabbix agent | 模板内置 |
| 7 个容器的存活与资源 | A | Zabbix agent | `docker.container_info[...]` |
| MySQL 主从延迟 | B | **Zabbix trapper** | `shop.repl.lag` / `shop.repl.running` |
| 备份文件年龄 | B | **Zabbix trapper** | `shop.backup.age` |
| LB 健康与连接数 | A | HTTP agent（server 在 front 网络） | `http://lb/lb-health` |
| 告警出口 | — | Media type: Webhook（钉钉） | — |

> **建 item 时最容易错的一步**：走 B 的三个 item，Type 必须选
> **`Zabbix trapper`**，不能选 `Zabbix agent`。选错的话 item 会一直是
> "No data" —— 因为它在等 agent 主动回答，而数据其实是从 10051 推过来的。

---

## 文件说明

```
monitoring/
├── docker-compose.yml          # 4 个服务 + 内存上限 + 网络
├── scripts/
│   └── host_checks.sh          # ★ 在「宿主机」执行，不在容器里
│                               #   采主从状态 + 备份年龄，用 zabbix_sender 推送
└── README.md
```

> `zbx-agent/` 目录已删除。它曾经放 `userparams.conf`（UserParameter 定义），
> 但业务指标改走 push 之后不再需要 —— agent2 里没有自定义 item 了。
> 顺带解决了坑③：不再挂载任何 `zabbix_agent2.d/` 下的东西，
> 镜像自带的 `plugins.d/*.conf` 完好无损。

**`host_checks.sh` 必须在宿主机上跑**（cron），不要拷进容器。
它依赖宿主机的 `docker` 命令，而容器里没有能用的 docker CLI。
打包自 Windows 时**不保留可执行位**，部署后要 `chmod +x`。
