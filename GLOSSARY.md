# 术语表

本仓库同时存在两层命名，**不要混用**。两层的内容各自收在自己的目录里：
Skill 层在 `goutoujunshi/`，应用层在 `integrations/`。

## 应用层（`integrations/`，另有根级例外）

用户可见、可安装、可打包的桌面与移动应用。

主体在 `integrations/`，另有若干根级例外——`tests/`（只测应用集成）、`documentation/`（应用截图与设计稿）、
`examples/`（演示案例，运行期消费者是 `integrations/jev_mac/trend.py`，不是 skill）、`PRIVACY.md`
（数据使用说明，根级是 GitHub 惯例）、`references/`（三端共用的参考材料，不属于任何单端）。
根级例外逐项登记在 `scripts/validate_layout.py` 的白名单里，以那里为准。

| 术语 | 含义 |
| --- | --- |
| 喵头军师 | 应用的中文显示名。出现在窗口标题、应用图标名称、通知栏标题、设置页与打包说明中 |
| 喵球 | 悬浮球的显示名，只是这个 UI 元件的名字，**不是应用名**。只出现在球面与其自带文案（球的窗口标题、无障碍标签）中 |
| miaotoujunshi | 应用的技术标识前缀。用于 applicationId（`com.miaotoujunshi.chat`）、PyInstaller `NAME`、CI artifact 名、zip 前缀与 dist 目录名 |
| Jev Chat | 上游 `jev-chat-jarvis` 的品牌名。应用侧**不再使用**，以免违反 NOTICE 的署名禁令。仍作为策略判断服务名（TypeSafe Jev）出现在配置界面 |
| preview 包 | 未签名/未公证的源码或调试构建，仅供自行安装验收，不是商店发布版 |

## Skill 层（`goutoujunshi/`）

可独立分发的 AI 能力包，不随应用改名。载体是根级目录 `goutoujunshi/`，成员为：
`SKILL.md`、`agents/openai.yaml`、`assets/`、`references/`、`scripts/memory_store.py`、
`scripts/validate_skill.py`。

归属判据：**该文件在上游 `shengjidaguai-china/goutoujunshi` 有同源对应，且不是上游的仓库治理文件**
（上游的 `README.md`、`LICENSE`、`CHANGELOG.md`、`CONTRIBUTING.md`、`CODE_OF_CONDUCT.md`、
`SECURITY.md`、`.gitignore`、`.github/*` 与本仓无关，未导入）。本仓自有的 `scripts/` 脚本不属这一层。

成员与上游的漂移用 `python3 -B scripts/check_upstream.py` 检查；参与比对的路径清单由该脚本的
`TRACKED_FILES`/`TRACKED_DIRS` 定义。被删除的追踪文件由该脚本的 `tracked but missing` 一行报出。

| 术语 | 含义 |
| --- | --- |
| goutoujunshi | Skill 的 frontmatter `name`，也是 `agents/openai.yaml` 里 `$goutoujunshi` 的调用名。**保持不变** |
| 狗头军师 | Skill 语义层的自称。SKILL.md 正文标题与 model system prompt 中的「你是狗头军师的…」都属于这一层，**保持不变** |
| TypeSafe Jev | 可选的策略判断服务。与上游同名，但指的是服务而非应用品牌 |

## 会话态（应用运行期）

悬浮球面板与用户当前所处聊天会话之间的关系。用于决定「填入」是否可用。

| 术语 | 含义 |
| --- | --- |
| 会话身份 | 一个会话的标识：聊天应用包名 + 会话标题。两段都可能缺失，**缺失是合法状态而非错误**，不得由其中一段推断另一段 |
| 分析所属会话 | 面板上当前那份判断与候选回复所属的会话。面板头部显示的就是它 |
| 当前会话 | 用户此刻正在看的会话，由无障碍服务在前台变化时告知面板；没有聊天窗口时为空 |
| 只读态 | 分析所属会话与当前会话不一致时，面板进入的状态 |
| 未识别会话 | 拿不到会话标题时的占位显示 |

## 边界规则

- 改应用显示名 → 只动 `integrations/` 与 `PRIVACY.md`。
- 改悬浮球显示名 → 只动球面与球自带文案（球的窗口标题、无障碍标签）；应用显示名与技术标识不动。
- 改 Skill 标识 → 需同时评估已安装用户的升级路径，另开 ADR。
- 往仓库根新增条目 → 必须在同一次提交里登记进 `scripts/validate_layout.py` 的白名单，并注明所属层与留在根的理由；未登记的条目会让 CI 失败。
- Skill 层内容只放 `goutoujunshi/`，应用层内容只放 `integrations/`（根级例外见上节与白名单）。
- 两个 `references/` 不同层：`goutoujunshi/references/` 是 skill 载荷的参考库（上游所有，逐字节一致）；
  根级 `references/` 是应用层三端共用的参考材料（本仓所有）。跨端共用的应用层内容一律放根级后者，
  **不要放进某个单端目录**。
- 载荷目录 `goutoujunshi/` 必须与上游**逐字节一致**：`check_upstream.py` 的 `drifted` 与
  `only this repo has` 两行都必须恒为 0。本仓对 skill 内容的任何意见一律落在应用层，
  不改载荷；要改 skill 本身只能提给上游（见 `docs/adr/0004`）。
- 上游 `goutoujunshi` 的 `documentation/`（7 个开发文档）**未导入**；本仓 `documentation/` 是应用目录，与上游同名但不同义，不要按上游语义理解。
- model prompt 中的自称属于 Skill 语义层，不随应用改名而变。
- 上游 `jev-chat` 的版权、许可证与 NOTICE 段落是署名义务，任何情况下不得改写。
- 面板头部有分析时显示「分析所属会话」，无分析时显示「当前会话」；不得显示裸包名。
- 只读态只撤销「填入」，不撤销「复制」与「详细分析」——用户仍应能读到那份候选。
