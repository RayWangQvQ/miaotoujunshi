# 术语表

本仓库同时存在两层命名，**不要混用**。

## 应用层（integrations/）

用户可见、可安装、可打包的桌面与移动应用。

| 术语 | 含义 |
| --- | --- |
| 喵头军师 | 应用的中文显示名。出现在窗口标题、应用图标名称、通知栏标题、设置页与打包说明中 |
| 喵球 | 悬浮球的显示名，只是这个 UI 元件的名字，**不是应用名**。只出现在球面与其自带文案（球的窗口标题、无障碍标签）中 |
| miaotoujunshi | 应用的技术标识前缀。用于 applicationId（`com.miaotoujunshi.chat`）、PyInstaller `NAME`、CI artifact 名、zip 前缀与 dist 目录名 |
| Jev Chat | 上游 `jev-chat-jarvis` 的品牌名。应用侧**不再使用**，以免违反 NOTICE 的署名禁令。仍作为策略判断服务名（TypeSafe Jev）出现在配置界面 |
| preview 包 | 未签名/未公证的源码或调试构建，仅供自行安装验收，不是商店发布版 |

## Skill 层（SKILL.md、agents/、references/、examples/）

可独立分发的 AI 能力包，不随应用改名。

| 术语 | 含义 |
| --- | --- |
| goutoujunshi | Skill 的 frontmatter `name`，也是 `agents/openai.yaml` 里 `$goutoujunshi` 的调用名。**保持不变** |
| 狗头军师 | Skill 语义层的自称。SKILL.md 正文标题与 model system prompt 中的「你是狗头军师的…」都属于这一层，**保持不变** |
| TypeSafe Jev | 可选的策略判断服务。与上游同名，但指的是服务而非应用品牌 |

## 边界规则

- 改应用显示名 → 只动 `integrations/` 与 `PRIVACY.md`。
- 改悬浮球显示名 → 只动球面与球自带文案（球的窗口标题、无障碍标签）；应用显示名与技术标识不动。
- 改 Skill 标识 → 需同时评估已安装用户的升级路径，另开 ADR。
- model prompt 中的自称属于 Skill 语义层，不随应用改名而变。
- 上游 `jev-chat` 的版权、许可证与 NOTICE 段落是署名义务，任何情况下不得改写。
