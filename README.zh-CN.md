# claude-egress-guard（中文说明）

[![ci](https://github.com/yinyues2/claude-egress-guard/actions/workflows/ci.yml/badge.svg)](https://github.com/yinyues2/claude-egress-guard/actions/workflows/ci.yml)

**一站式 skill + 一键安装：在 Linux 上安全地部署和运行 Claude Code——从裸机到可用、
可审计的客户端，以及出问题时知道怎么处置。**

在 VPS 上跑 Claude Code，最容易出问题的不是安装，而是**出口泄漏**：写在
`/etc/profile.d` 里的 `claude()` 函数只覆盖交互式 shell，Python、`sh -c`、
cron、systemd 和任何直接调用 `/usr/bin/claude` 的路径都会绕过去；代理中途挂掉时，
客户端还会悄悄从机房 IP 直连出去。

所以项目分成四块，只有一个是强制核心：

| 部分 | 覆盖什么 | 入口 |
| --- | --- | --- |
| **部署** | 资格判断、主机基线、代理先稳定、装客户端但不启动、首次登录走闸门 | `preflight`、[`zero-to-deployed.md`](skills/claude-egress-guard/references/zero-to-deployed.md) |
| **出口** | 固定出口、注入代理、内核白名单、更新自愈、失败不回落 | `install`、`verify --deep`、`drill`、`set-exit` |
| **运行** | 凭据、客户端设置、密钥卫生、影响范围、备份、监控 | [`safe-operation.md`](skills/claude-egress-guard/references/safe-operation.md) |
| **处置** | 出口变化、被要求验证、凭据泄漏、怀疑绕过 | [`safe-operation.md`](skills/claude-egress-guard/references/safe-operation.md) §6 |

强制核心仍然是二进制闸门：`claude` 命令本身核验代理的真实出口地址、注入代理变量，
可选地把整个进程树关进内核级 IP 白名单。任何异常都拒绝启动，没有回落。另外三块存在
的意义，是让这道闸门**按正确顺序装上**，并且在第一周之后仍然有意义。

---

## 给 agent：从这里开始

这个仓库是给 agent（Hermes、Codex、Claude Code 或任何支持 skill 的运行器）消费的，
不只是给人读的 README。

```bash
# 把 skill 装进 agent 的 skills 目录（不需要 root，不改主机）
curl -fsSL https://raw.githubusercontent.com/yinyues2/claude-egress-guard/main/install.sh \
  | bash -s -- --skill-only --dest ~/.hermes/skills
```

然后对 agent 说：

> 用 `claude-egress-guard` 这个 skill：先问我代理入口、预期出口地址、国家、额外网段，
> 然后安装、跑 `verify --deep`、做一次故障演练，最后把 PASS/FAIL 行贴给我。

skill 里写清的约束（[`SKILL.md`](skills/claude-egress-guard/SKILL.md)）：

- **只问 4 个事实**——代理入口、预期出口地址、国家、额外白名单；其余从主机自己读，不重复追问；
- **三档授权**——只读诊断直接做；安装/验证/演练/卸载整计划批一次；可能切断操作者自身访问的操作当场确认；
- **证据而非形容词**——每条结论都要贴对应的 PASS 行，演练结果要记录，没输出不算通过；
- **硬性禁止**——不停 ssh/tailscale/docker 单元，不把 `ALLOW_IPS` 放大到 `0.0.0.0/0`，不为通过检查而关闭某一层，不碰账号/付款/身份核验。

配套文件：[`AGENTS.md`](AGENTS.md)（机器入口）、
[`references/agent-playbook.md`](skills/claude-egress-guard/references/agent-playbook.md)
（带判断点的分步手册）、[`llms.txt`](llms.txt)（给 LLM 工具用的链接索引）、
[`references/troubleshooting.md`](skills/claude-egress-guard/references/troubleshooting.md)。

---

## 从零开始：新机器、还没注册过

下面的内容默认 Claude Code 已经装好并登录过。如果是从零开始，**顺序**决定第一次
部署安不安全：[`references/zero-to-deployed.md`](skills/claude-egress-guard/references/zero-to-deployed.md)
给了九个阶段，并标明每一阶段由谁执行。

```
0  资格与环境判断：一人一号、一个固定出口            操作者
1  主机基线：时钟、时区、磁盘、IPv6 决策              agent
2  先把代理跑通并确认稳定，再谈注册                   agent
3  安装 Claude Code，装完不要启动                     agent
4  装闸门，verify --deep + drill                      agent
5  第一次登录：走闸门，在你自己的浏览器完成           操作者
6  首次设置：客户端里不要再单独设代理                 操作者 + agent
7  留证：记录证据、打开拒绝日志                        agent
8  日常：升级后 verify，出口漂移用 set-exit           agent
```

```bash
claude-egress-guard preflight --proxy http://127.0.0.1:1080 --exit-ip 203.0.113.10 --country JP
```

`preflight` 只读：检查平台、systemd、bash、时钟、时区、IPv6、磁盘、Node、
Claude Code，给了代理还会实测出口，最后输出 PASS/WARN/FAIL 和阻塞项数量。
出现 FAIL 就不要继续。

注册账号、付款、身份核验**故意不做自动化**：skill 明确禁止 agent 代办，runbook 会
告诉操作者在什么情况下应当停下来，而不是硬凑材料。

---

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/yinyues2/claude-egress-guard/main/install.sh \
  | sudo bash -s -- --proxy http://127.0.0.1:1080 --exit-ip 203.0.113.10 --country JP
```

这条命令会下载固定版本的发布包、打印安装计划、安装闸门、备份被替换的文件，最后自动跑
`verify --deep`。任何一层失败就停下并指出是哪一层，不会把装了一半的闸门当成功。

| 参数 | 含义 |
| --- | --- |
| `--proxy URL` | 本地 HTTP/mixed 代理入口（必填） |
| `--exit-ip ADDR` | 代理出口的公网 IPv4（必填） |
| `--country CC` | 要强制的两位国家码（可选） |
| `--allow LIST` | 内核白名单里额外放行的网段，逗号分隔 |
| `--strict-net on\|off` | 是否给进程树加内核白名单（默认 on） |
| `--dry-run` | 只打印计划，不写任何东西 |
| `--yes` | 跳过确认提示（自动化用） |
| `--ref REF` | 指定 tag 或分支（默认固定 tag） |
| `--uninstall` | 移除闸门并从备份恢复 |
| `--skill-only` | 只把 skill 复制到 skills 目录 |

`203.0.113.10` 是文档专用地址（RFC 5737），请换成你代理实际报告的地址。回环和主机
IPv4 DNS 解析器会自动放行；代理上游、Tailscale 网段、内网 API 用 `--allow` 显式加。

**给 root 之前先读一遍。** `install.sh` 是不混淆的纯 shell 脚本，下载的是固定 tag 的
压缩包，不是移动的分支。也可以先 clone 再 `sudo ./install.sh ...`。

卸载走同一条通道：

```bash
curl -fsSL https://raw.githubusercontent.com/yinyues2/claude-egress-guard/main/install.sh \
  | sudo bash -s -- --uninstall
```

---

## 装好之后是什么样

```
$ sudo claude-egress-guard verify --deep
PASS   config present: /etc/claude-egress-guard.conf
PASS   real binary executable
PASS   gate installed: /usr/local/bin/claude
PASS   gate mirrored: /usr/bin/claude
PASS   egress check: ok exit=203.0.113.10 country=JP
PASS   kernel jail enabled, allow list: 127.0.0.0/8 ::1/128 192.0.2.53/32
PASS   systemd-run available
PASS   IPv6 disabled system-wide
PASS   jail blocks direct egress
PASS   jail still allows the proxy path
---- 0 check(s) failed
```

每一行都是实测观察，不是「配置里写了」：最后两行是真的在白名单里发请求验证的。

```
claude（任意入口：shell、Python、cron、systemd、绝对路径）
  └─ /usr/local/bin/claude          闸门：核验出口 -> 注入代理 -> 内核白名单
       ├─ /usr/bin/claude           同一份闸门（npm 更新会改回符号链接，闸门自愈）
       └─ /opt/claude-real/claude   真身（符号链接，跟随包更新）
            └─ 你的代理          127.0.0.1:1080 -> 预期出口地址
```

每次启动的顺序：

1. 读 `/etc/claude-egress-guard.conf`，缺失或不可读 → 拒绝（77）；
2. 如果包更新把 `/usr/bin/claude` 改回符号链接，先补回闸门；
3. 问代理要真实出口地址和国家，不符/超时/HTTP 错误 → 拒绝（77），不重试、不回落直连；
4. 把 `ALL_PROXY`/`http_proxy`/`https_proxy`（大小写）导出给客户端和所有子进程，`NO_PROXY` 只留回环；
5. `STRICT_NET=1` 时，在临时 systemd scope 里以 `IPAddressDeny=any` + 白名单 exec，
   子进程继承的是内核级限制，不是口头承诺。

诊断路径不碰网络：`--version`、`--help`、`--ceg-check` 在探测之前就短路返回。

---

## 保证什么

| 层 | 行为 |
| --- | --- |
| 出口核验 | 每次启动前核验地址和国家；不符、超时、报错一律退出码 77 |
| 代理环境 | 六个代理变量导出给客户端和全部子进程 |
| 内核白名单 | 整个进程树 `IPAddressDeny=any`，只放行回环、白名单和显式允许的网段 |
| 入口覆盖 | `/usr/local/bin/claude` 和 `/usr/bin/claude` 都是闸门，真身放在 `/opt/claude-real` |
| 自愈 | 包自更新改写的 `/usr/bin/claude` 会在下一次调用时补回 |
| fail-closed | 配置缺失、检查器缺失、代理不通、出口不符、国家不符、没有 `systemd-run`、非 root 且 `STRICT_NET=1`：全部拒绝 |
| 审计线索 | `LOG_REFUSALS=1` 时每次拒绝写入 journald，tag `claude-egress-guard` |
| 可回滚 | 被替换的文件都在 `/var/lib/claude-egress-guard/backup/<时间戳>/`，`uninstall` 恢复 |

---

## 环境要求与兼容性

| 项目 | 要求 |
| --- | --- |
| 系统 | Linux + systemd 235+（`IPAddressDeny=` 需要） |
| Shell | bash 4.3+ |
| 工具 | `curl`、`install`、`readlink`、`mktemp`、`awk`、`sed` |
| 权限 | 正式安装要 root；`--prefix` 可做无特权沙箱 |
| Claude Code | 已安装，npm 全局或官方安装器均可 |
| 代理 | 本地 HTTP 或 mixed 入口（只有 SOCKS 的话，客户端代理变量用不了） |

已实测：Debian 13 / systemd 257 / Claude Code 2.1.296（npm 全局），代理在回环上的
住宅 HTTP 入口。CI 在 Ubuntu 24.04 上跑全套。

未验证、不支持：macOS/BSD、WSL、systemd 235 以下、非 root 用户 scope 下开
`STRICT_NET=1`、容器内的 Claude。

**每次启动成本**：一次经代理的 HTTPS 往返（视距离约 100-400 ms）；`--version`/`--help` 不探测。

---

## 命令

| 命令 | 用途 |
| --- | --- |
| `preflight [--proxy URL --exit-ip ADDR --country CC]` | 新机器只读体检，含实时出口探测；`--json` 给工具用 |
| `install ...` | 打印计划、备份、安装（支持 `--dry-run`） |
| `verify` | 静态检查 + 实时出口核验 |
| `verify --deep` | 额外证明「白名单挡住直连、仍放行代理」 |
| `status` | 查看当前策略（代理凭据打码） |
| `set-exit --ip ADDR [--country CC]` | 跟随变化的出口：先探测，代理确实在该地址才改策略，再自动 verify |
| `drill --service UNIT` | 停代理单元，证明闸门拒绝，再拉起并等待恢复 |
| `show <guard\|check\|config>` | 打印已安装的闸门/检查器/策略，便于审计 |
| `uninstall` | 从最新备份恢复并移除闸门 |

退出码：`0` 成功，`1` 校验失败，`2` 用法错误，`77` 闸门拒绝启动。

---

## 出口变了怎么办

住宅出口会漂。别手改配置，让闸门跟着走：

```bash
sudo claude-egress-guard set-exit --ip 198.51.100.23 --country JP
```

它先用候选地址探测代理，代理确实在该地址才原子改写 `EXPECTED_IP`/`EXPECTED_COUNTRY`
（权限保持 0600），然后自动跑 `verify`；不爆料就拒绝，不会把没验证过的地址写进策略。

不知道新地址时先看一眼：

```bash
curl -4 -fsS --max-time 8 -x http://127.0.0.1:1080 https://www.cloudflare.com/cdn-cgi/trace
```

取输出里的 `ip=` 和 `loc=`。

---

## 拒绝日志

拒绝默认只出现在终端，没人盯着就看不见。开一次 journald 记录：

```bash
sudo sed -i 's/^LOG_REFUSALS=0/LOG_REFUSALS=1/' /etc/claude-egress-guard.conf
```

之后：

```bash
journalctl -t claude-egress-guard --since -24h
```

每条是 `refused: <原因>`。这决定了你是「我觉得没拒绝过」还是「它拒绝过 11 次，都在这」。

---

## 日常维护

| 事件 | 动作 |
| --- | --- |
| `npm i -g` 或 Claude Code 自更新 | `sudo claude-egress-guard verify --deep`（备用路径会自动补回） |
| 代理出口变了 | `sudo claude-egress-guard set-exit --ip 新地址 --country CC` |
| 代理改走远程中转 | 用 `--allow` 加中转地址，再 `verify --deep` |
| 不要内核白名单 | 设 `STRICT_NET=0` 再 `verify`（会出现 WARN），进程树出口不再强制 |
| 怀疑有绕过 | `status`，然后看 `/proc/<pid>/cgroup` 里有没有 `run-r...scope` |

---

## 不做什么

- **不创建、不管理代理。** 入口要你自己提供并保持存活。
- **只闸一个二进制。** `npx @anthropic-ai/claude-code` 不经过 `/usr/local/bin/claude`，
  因此不受保护；要么别这么用，要么自己再包一层。另一份装在别的前缀里的 Claude 同样不受保护。
- **不是 VPN。** 主机上其他服务、包管理器、其他用户不受影响，白名单只管 Claude 进程树。
- **挡不住 root。** 有 root 就能设 `STRICT_NET=0`、改配置或直接跑 `/opt/claude-real/claude`。
  这是护栏，不是强制访问控制边界。
- **不覆盖容器。** Docker/Kubernetes 的流量不经过主机的出口路径。
- **不保证账号安全。** 注册、付款、身份核验和平台判定都由账号本人承担；这个项目不用于规避服务商条款。

完整威胁模型见 [SECURITY.md](SECURITY.md)。

---

## 从源码手动安装

```bash
git clone https://github.com/yinyues2/claude-egress-guard.git
cd claude-egress-guard

# 一条命令，参数和 curl 版一致
sudo ./install.sh --proxy http://127.0.0.1:1080 --exit-ip 203.0.113.10 --country JP

# 或者直接驱动 CLI
sudo skills/claude-egress-guard/scripts/claude-egress-guard install \
  --proxy http://127.0.0.1:1080 --exit-ip 203.0.113.10 --country JP --dry-run
```

---

## 开发与测试

```bash
make check        # shellcheck + 44 项自测 + 泄漏扫描
make test         # 只跑沙箱自测（不需要 root，不联网）
make lint
make scan
```

自测在临时前缀里用假的 `curl`/`id`/`logger`/`systemd-run` 跑，不碰主机。

---

## 仓库结构

```
install.sh                  一键安装（下载固定 tag）
AGENTS.md                   agent 运行器的机器入口
llms.txt                    给 LLM 工具的链接索引
skills/claude-egress-guard/
  SKILL.md                  部署 skill 本体
  references/               playbook 与故障排查
  scripts/claude-egress-guard   安装/验证/演练/卸载 CLI
  scripts/guard-claude.sh   闸门本体（安装为 `claude`）
  scripts/egress-check.sh   出口检查器（可单独运行）
  scripts/selftest.sh       44 项沙箱断言
  templates/                策略文件示例
tools/leak-scan.py          拦截凭据、个人标识和非文档网段
```

---

## 许可、安全、隐私

Apache-2.0，见 [LICENSE](LICENSE)。安全模型与漏洞报告见 [SECURITY.md](SECURITY.md)，
数据收集见 [PRIVACY.md](PRIVACY.md)（简短版：不收集任何东西，只探测你自己的代理）。
