# fail2ban 一键部署

针对 Ubuntu / Debian 服务器的 SSH 暴力破解防护快速部署脚本。

## 适用场景

- Ubuntu / Debian 系统
- `/var/log/auth.log` 满屏 `Failed password`，正在被 SSH 暴力破解
- 想 5 分钟内搞定基础防护

## 快速使用

### 方式 1：curl 一行执行（最快）

```bash
curl -fsSL https://raw.githubusercontent.com/Somethingbear/firewalld/main/fail2ban/install-fail2ban.sh | sudo bash
```

### 方式 2：先下载再执行（推荐，可以先看一眼内容再跑）

```bash
curl -fsSL -o install-fail2ban.sh \
  https://raw.githubusercontent.com/<user>/<repo>/main/fail2ban/install-fail2ban.sh
less install-fail2ban.sh
sudo bash install-fail2ban.sh
```

### 方式 3：clone 仓库

```bash
git clone https://github.com/<user>/<repo>.git
cd <repo>/fail2ban
sudo bash install-fail2ban.sh
```

### 方式 4：批量部署多台机器

```bash
for h in host1 host2 host3; do
    scp install-fail2ban.sh "$h":/tmp/
    ssh "$h" "sudo bash /tmp/install-fail2ban.sh"
done
```

## 脚本做了什么

1. 通过 apt 安装 fail2ban
2. 备份原有 `/etc/fail2ban/jail.local`（如果存在）
3. 写入新的 `jail.local`：
   - 启用 sshd jail，使用 **aggressive 模式**（多抓端口扫描 / 协议探测 / KEX 失败等）
   - `banaction = iptables-allports`：与 SSH 端口解耦，不论 SSH 在 22 还是其他端口都能正确封禁
   - 升级式 bantime：第一次封 10 小时，重犯翻倍，上限 5 天
   - `dbpurgeage = 7d`：IP 历史保留 7 天，让 `bantime.increment` 真正生效
   - `bantime.rndtime = 30m`：解封时间错开，防解封瞬间出现重连尖峰
   - 10 分钟内失败 3 次触发封禁
4. 用 `fail2ban-client -d` 校验语法
5. 启用 + 重启 fail2ban（开机自启）

## 默认参数

| 参数              | 默认值 | 含义                                                |
| ----------------- | ------ | --------------------------------------------------- |
| `MAXRETRY`        | 3      | 触发封禁的失败次数                                  |
| `FINDTIME`        | 10m    | 失败计数窗口                                        |
| `BANTIME`         | 10h    | 初次封禁时长                                        |
| `BANTIME_FACTOR`  | 2      | 重犯封禁倍数                                        |
| `BANTIME_MAXTIME` | 5d     | 封禁时长上限                                        |
| `BANTIME_RNDTIME` | 30m    | 解封时间随机抖动，防扎堆                            |
| `DBPURGEAGE`      | 7d     | IP 历史保留时长（>= maxtime 才能让 increment 生效） |

如需调整，编辑脚本顶部 `# ---------- 可调参数 ----------` 一节即可。

## 验证

执行后看一眼状态：

```bash
sudo fail2ban-client status sshd
```

输出形如：

```
Status for the jail: sshd
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     0
|  `- Journal matches:  _SYSTEMD_UNIT=sshd.service + _COMM=sshd
`- Actions
   |- Currently banned: 0
   |- Total banned:     0
   `- Banned IP list:
```

跑 5–10 分钟后再看，如果有人在打你，`Total failed` 和 `Total banned` 数字会涨。

## 常用运维命令

```bash
# 查看 sshd jail 状态
sudo fail2ban-client status sshd

# 当前所有被封禁的 IP
sudo fail2ban-client banned

# 手动封禁一个 IP
sudo fail2ban-client set sshd banip 1.2.3.4

# 手动解封一个 IP
sudo fail2ban-client set sshd unbanip 1.2.3.4

# 实时看日志
sudo tail -f /var/log/fail2ban.log

# 重启 fail2ban
sudo systemctl restart fail2ban
```

## 卸载

```bash
sudo systemctl stop fail2ban
sudo apt remove --purge fail2ban -y
sudo rm -f /etc/fail2ban/jail.local
# 备份文件 (jail.local.bak.*) 如不需要也可一并删除
```

## 注意事项

- **白名单**：默认 `ignoreip = 127.0.0.1/8 ::1`，没有把任何外网 IP 加白名单。如果你担心被自己误封，部署后手动编辑 `/etc/fail2ban/jail.local`，在 `ignoreip` 行追加你的 IP，再执行 `sudo systemctl reload fail2ban`。
- **aggressive 模式**：sshd jail 启用了 aggressive filter，能多抓端口扫描、协议探测等场景。极少数情况下若内网监控/健康检查工具被误判，把对应 IP 加进 `ignoreip` 即可。
- **不动 sshd 配置**：脚本不会修改 SSH 端口、`PermitRootLogin` 等，sshd 的设置完全由你掌握。
- **不装 ipset**：当前用 `iptables-allports`，每个被封 IP 一条 iptables 规则。如果将来 `Currently banned` 长期超过 8000，再单独把 banaction 改成 `iptables-ipset-proto6-allports`（需先装 `ipset`）即可。
- **幂等**：脚本可以重复执行。已装的包会跳过，原 `jail.local` 会自动备份再覆盖。

## FAQ

**Q：我改了 SSH 端口（比如改成 59824），fail2ban 还能正常封禁吗？**
能。`banaction = iptables-allports` 是按源 IP 全端口封禁的，不依赖 SSH 端口设置。换端口、加新服务都不用改 fail2ban。

**Q：万一脚本把我自己 IP 封了怎么办？**
极小概率（你要先在 10 分钟内输错 3 次密码）。万一发生，从其他 IP 进去执行：

```bash
sudo fail2ban-client set sshd unbanip <你的 IP>
```

或临时停服务：`sudo systemctl stop fail2ban`。

**Q：能否同时启用其他 jail（如 nginx、postfix）？**
能。在 `/etc/fail2ban/jail.local` 末尾追加 `[nginx-http-auth]` 等段落，参考 `/etc/fail2ban/jail.conf` 里的预置 filter 名字，然后 `sudo systemctl reload fail2ban`。
