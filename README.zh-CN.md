# cc-skill-args-guard（中文）

> Claude Code 的护栏：防止压缩续接后，**前几次会话残留的 skill `ARGUMENTS` 被当成当前请求**。

## Bug 是什么

当你用参数调用 Claude Code skill（比如 `/frontend-design:frontend-design 重做顶部跑马灯`），CLI 会把这些 args 存为该 skill 的 `lastInvocationArgs`。**之后每次请求**，system prompt 里都会带：

```
### Skill: frontend-design:frontend-design
[完整 skill 内容]

ARGUMENTS: 重做顶部跑马灯
```

这段 args **没有时间戳、不会过期**。会话压缩、跨天续接都保留着——哪怕用户早就换主题了。

压缩之后，原本解释这次调用的对话历史被裁掉了，模型看到一段没时间戳的 args，就当成"刚刚被调用的 skill"。结果：模型默默接着几天前放弃的主题干，无视你当前的请求。

### 症状

- `/compact` 或会话续接后，模型开始做你几天前聊过的事
- 模型引用某个 skill 的 `ARGUMENTS`，仿佛你刚刚才输入
- 你最新的请求被当成次要的、或者被忽略

### 怎么验证

去 `~/.claude/projects/<project>/<session>.jsonl` 翻日志：

- 那段 `ARGUMENTS:` 文本只在**最初调用那天**作为 `user` 消息出现过
- 之后**再也没作为 user/system 消息出现**——证明它住在 system prompt 里，而 system prompt 不写日志
- 但在 assistant 输出里反复被引用——这是泄漏的行为指纹

## 修复（三层防御）

三层独立，任何一层都能拦住 bug，叠在一起是冗余保险。

### 第一层 — `SessionStart` hook（settings.json）

每次会话开始，CLI 强制执行一段 shell 脚本，把 stdout 作为 system context 注入。内容是："ARGUMENTS 可能过期，必须跟续接 summary 比对"。这一层**不依赖模型自觉**——是 CLI 主动塞进上下文的。

### 第二层 — `CLAUDE.md` 规则

往 `~/.claude/CLAUDE.md` 末尾追加一段强制规则。CLAUDE.md 随 system prompt 加载，**权重高于 skill context**。规则要求：续接时 summary 的 `All user messages` 是权威；skill ARGUMENTS 跟它冲突就跟 summary，忽略 ARGUMENTS。

### 第三层 — 项目 memory（可选，手写）

按项目写 memory 文件，标注当前主线任务和"不要跑偏到字体/样式"的反馈。`install.sh` **不**自动写这一层——你自己根据项目情况写。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/zvv1999/cc-skill-args-guard/main/install.sh | bash
```

或者手动：

```bash
git clone https://github.com/zvv1999/cc-skill-args-guard
cd cc-skill-args-guard
./install.sh
```

`install.sh` 是幂等的，patch 前会给 `~/.claude/CLAUDE.md` 和 `~/.claude/settings.json` 打时间戳备份。

## 卸载

```bash
./uninstall.sh
```

从最近的备份恢复。

## 这个包不修什么

Bug 的根源在 Claude Code 二进制里的 system prompt 构造逻辑。这个包只补丁**模型行为层**——让模型对过期 args 免疫。`lastInvocationArgs` 泄漏本身还是上游的 bug。

上游 issue 跟踪：https://github.com/anthropics/claude-code/issues/69679。

## 环境要求

- macOS 或 Linux（用 `bash`、`python3`、`cp`、`date`）
- Claude Code ≥ 2.1（支持 hooks + SessionStart）
- 存在 `~/.claude/CLAUDE.md` 和 `~/.claude/settings.json`（缺失会自动创建）

## License

MIT
