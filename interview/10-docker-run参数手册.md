# docker run 参数手册（速查）

> 结构：`docker run [选项] 镜像名 [命令] [参数]`
> 选项写在镜像**前面**，命令写在镜像**后面**——命令会覆盖镜像的默认 `CMD`（但不覆盖 `ENTRYPOINT`）。
> 所有例子都来自本项目真实用过的命令。

---

## 一、容器生命周期基础

| 参数 | 作用 | 说明 |
|---|---|---|
| `-d` | 后台运行 | detached，不占当前终端 |
| `-it` | 交互式终端 | `-i` 保持 stdin，`-t` 分配伪终端，连用进容器调试 |
| `--name xxx` | 指定容器名 | 不指定则随机生成；名字唯一，冲突报错 |
| `--rm` | 退出即删 | 一次性容器必加，不留垃圾（调试/压测用） |
| `--restart` | 重启策略 | `no`（默认）/ `always` / `unless-stopped` / `on-failure:N` |

**`always` 与 `unless-stopped` 的区别**（面试常问）：
- `always`：Docker 启动时**无条件**拉起，哪怕你之前手动 `docker stop` 过
- `unless-stopped`：手动停过的**不会**被拉起，其余情况同 always
- 项目二四个服务用的都是 `unless-stopped`

## 二、端口与网络

| 参数 | 作用 | 例子 |
|---|---|---|
| `-p 宿主:容器` | 端口映射 | `-p 8080:80` 宿主 8080 → 容器 80 |
| `-p 宿主IP:宿主:容器` | 绑定指定 IP | `-p 127.0.0.1:3306:3306` 只允许本机连 |
| `-P` | 随机映射所有 EXPOSE 端口 | 配合 `docker port` 查看 |
| `--network xxx` | 加入指定网络 | `--network lnmp-p2_default` |
| `--ip` | 静态 IP | 需要自定义网络才可用 |
| `--link` | 容器互联 | **已过时**，用自定义网络代替，面试提一句即可 |

**要点**：不映射端口的容器，同一网络内的其他容器仍可通过**容器 IP / 容器名**访问——项目二 mysql 没写 `-p`（只 `expose`），就是让 3306 不暴露到公网，只有 php 能连。

## 三、存储

| 参数 | 作用 | 例子 |
|---|---|---|
| `-v 宿主:容器` | bind mount（目录/文件） | `-v ./www:/var/www/html` |
| `-v 卷名:容器` | named volume（Docker 管理） | `-v mysql_data:/var/lib/mysql` |
| `-v 容器路径` | 匿名卷 | 少用，难管理 |
| `:ro` / `:rw` | 挂载读写权限 | `-v ./conf.d:/etc/nginx/conf.d:ro` |
| `--tmpfs /tmp:size=512m` | 内存文件系统 | 数据放内存，不落盘（压测内存上限用过） |

**bind mount vs named volume**（高频追问）：
- bind mount：路径直观、好排查，但依赖宿主机目录结构，权限容易踩坑（nginx 属主 101 那个坑就是它）
- named volume：Docker 统一管理、迁移方便，数据库数据用它（项目二 mysql 数据就是 volume，所以容器随便重建数据不丢）

## 四、环境变量与配置

| 参数 | 作用 | 例子 |
|---|---|---|
| `-e KEY=value` | 设置环境变量 | `-e MYSQL_ROOT_PASSWORD=xxx` |
| `--env-file x.env` | 从文件批量读 | 密码不进命令历史，更安全 |
| `-w /app` | 指定工作目录 | 相当于先 cd 再跑命令 |
| `-u user` | 指定运行用户 | `-u 0` 是 root，`-u 101:101` 普通用户 |
| `-h hostname` | 容器主机名 | `docker exec` 里 `hostname` 可见 |

**`-e` 的实战教训**：`docker exec -e MYSQL_PWD=xxx 容器 mysql -uroot` —— 给**进程**传环境变量；`docker run -e` 是给**容器**注入。mysql 镜像的 entrypoint 靠 `MYSQL_ROOT_PASSWORD` 初始化密码，变量名拼错不会有任何报错，密码就是空的。

## 五、资源限制（2G 小机器的关键参数）

| 参数 | 作用 | 项目二的值 |
|---|---|---|
| `--memory` / `-m` | 内存上限 | mysql 768m / php 384m / nginx 128m / redis 96m |
| `--memory-swap` | 内存+swap 总上限 | 默认 = memory × 2；设成和 memory 相等即禁 swap |
| `--cpus` | CPU 核数上限 | `--cpus=0.5` 半个核 |
| `--cpu-shares` | CPU 权重（相对值） | 默认 1024，竞争时按比例分 |
| `--pids-limit` | 进程数上限 | 防 fork 炸弹 |

**验证方法**（你在 D2 做过的）：
```bash
docker inspect --format '{{.HostConfig.Memory}}' 容器名   # 字节数，0=未限制
docker stats --no-stream                                  # LIMIT 列直接看
```

**超限后果**：内存超限 → cgroup OOM Killer 杀容器内进程，退出码 **137**（128+SIGKILL 9）。

## 六、日志驱动

```bash
docker run -d --log-driver json-file \
  --log-opt max-size=10m --log-opt max-file=3 \
  nginx:1.27-alpine
```

- **日志配置在容器创建时固定**，之后改 `daemon.json` 不影响已有容器（第 25 坑）
- 项目二用 compose 的 `x-logging` 锚点统一 10m×3，等价于上面两行

## 七、覆盖入口（调试神器）

| 参数 | 作用 |
|---|---|
| `--entrypoint sh` | 覆盖镜像入口，用于镜像起不来时进 shell 排查 |
| 镜像后直接跟命令 | 覆盖 CMD：`docker run -it mysql:8.0 bash` |

```bash
# 镜像的 entrypoint 脚本报错退不出来时：
docker run -it --entrypoint sh mysql:8.0
# 进去后手动跑 /usr/local/bin/docker-entrypoint.sh mysqld 看哪一步炸
```

## 八、健康检查

```bash
docker run -d --name mysql \
  --health-cmd "mysqladmin ping -uroot -p\$$MYSQL_ROOT_PASSWORD --silent" \
  --health-interval 10s \
  --health-timeout 5s \
  --health-retries 5 \
  --health-start-period 60s \
  mysql:8.0
```

| 参数 | 含义 |
|---|---|
| `--health-cmd` | 健康检查命令，退出码 0=健康 1=不健康 |
| `--health-interval` | 检查间隔 |
| `--health-start-period` | 启动宽限期（mysql 初始化要几十秒，期间失败不计入 retries） |
| `--health-retries` | 连续失败几次才标记 unhealthy |

**关联坑**（第 24 坑）：`mysqladmin ping` 认证失败也返回 0——健康检查命令必须选「能验证业务层」的，`SELECT 1` 比 `ping` 可靠。

## 九、一条真实命令的完整拆解

项目二恢复演练脚本里的（简化）：

```bash
docker run -d \
  --name restore-test-$$ \          # $$ 是当前 shell 的 PID，保证名字不重复
  --memory 512m \                   # 限内存：防止把生产库挤到 OOM
  -e MYSQL_ROOT_PASSWORD=xxx \
  mysql:8.0 \
  --innodb-buffer-pool-size=64M     # ← 镜像后面的都是 mysqld 的参数
```

**关键区分**：
- `mysql:8.0` **之前**的 → docker 的参数
- `mysql:8.0` **之后**的 → 传给容器内进程（mysqld）的参数
- 这个分界线是「镜像名」，看懂一条 docker run 命令先找镜像名在哪

## 十、高频面试题速答

| 问题 | 答案要点 |
|---|---|
| run 和 create/start 的区别 | `run` = create + start |
| 容器退出码 137 是什么 | 128+9，SIGKILL，通常是 OOM 或 docker stop 超时强杀 |
| 容器和虚拟机的区别 | 容器共享宿主内核， namespace 隔离视图 + cgroup 限资源；VM 有独立内核 |
| -v 挂载后容器删了数据还在吗 | bind mount/named volume 在，匿名卷看 `--rm` 与删除方式 |
| 怎么看容器占多少资源 | `docker stats --no-stream`，上限用 `docker inspect .HostConfig` |
| 重启后容器自己起来靠什么 | `--restart` 策略（我们验证过 reboot 自愈） |
