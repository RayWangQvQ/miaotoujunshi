# 术语表

本仓库同时存在三层内容命名，**不要混用**。三层的内容各自收在自己的目录里：
上游 skill 载荷在 `goutoujunshi/`，本仓自有载荷在 `miaotoujunshi/`，应用层实现（三端）在 `integrations/`。

## 应用层（`integrations/`，另有根级例外）

用户可见、可安装、可打包的桌面与移动应用。

主体在 `integrations/`，另有若干根级例外——`documentation/`（应用截图与设计稿）、
`PRIVACY.md`（数据使用说明，根级是 GitHub 惯例）。三端在运行期共读的材料不在这里，属于下面的自有载荷层。
根级例外逐项登记在 `scripts/validate_layout.py` 的白名单里，以那里为准。

| 术语 | 含义 |
| --- | --- |
| 喵头军师 | 应用的中文显示名。出现在窗口标题、应用图标名称、通知栏标题、设置页与打包说明中 |
| 喵球 | 悬浮球的显示名，只是这个 UI 元件的名字，**不是应用名**。只出现在球面与其自带文案（球的窗口标题、无障碍标签）中 |
| miaotoujunshi | 应用的技术标识前缀。用于 applicationId（`com.miaotoujunshi.chat`）、PyInstaller `NAME`、CI artifact 名、zip 前缀与 dist 目录名。**也是本仓自有载荷目录名 `miaotoujunshi/`**——同名是有意的：本仓自有的一侧统一叫这个 |
| Jev Chat | 上游 `jev-chat-jarvis` 的品牌名。应用侧**不再使用**，以免违反 NOTICE 的署名禁令。仍作为策略判断服务名（TypeSafe Jev）出现在配置界面 |
| 跨端公用材料 | **设计上供三端运行期读取**的内容：本仓自有载荷 `miaotoujunshi/`（散文在 `references/knowledge/`，结构化数据在 `references/data/`，演示案例在 `examples/`），加上上游 skill 载荷 `goutoujunshi/`。三端一律读文件，不在任一端内联副本 |
| preview 包 | 未签名/未公证的源码或调试构建，仅供自行安装验收，不是商店发布版 |

## 自有载荷层（`miaotoujunshi/`）

本仓自己写、**三端在运行期共读**的载荷，与上游载荷并列。层名 `miaotoujunshi-skill`
（`scripts/validate_layout.py` 的登记值）。

成员判据：**三端在运行期读取，且不属于上游 skill 载荷**。按此判据收入 `references/`
（`knowledge/` 放给模型读的散文，`data/` 放给代码读的结构化数据）与 `examples/`（演示案例）；
`integrations/`、`documentation/` 只被单端或构建链使用，留在应用层。
决策、被取代的旧结构与已知代价见 `docs/adr/0006`。

| 术语 | 含义 |
| --- | --- |
| 上游载荷 | 目录 `goutoujunshi/`，成员由「上游有同源对应」判据决定，**逐字节一致**，本仓只读不写 |
| 自有载荷 | 目录 `miaotoujunshi/`，本仓所有、可自由修改；与上游载荷同为「载荷」，但归属与修改权相反 |

## 上游 skill 载荷层（`goutoujunshi/`）

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

## Flutter 迁移层（macOS 与 Windows 已替换，`integrations/jev_flutter/`）

三端合并为一份 Flutter 代码库后的词汇。决策见 `docs/adr/0007`、`docs/adr/0008`。

| 术语 | 含义 |
| --- | --- |
| 能力契约 | 平台差异的唯一接口层。接口在 `miaotou_capabilities`，实现在 `miaotou_capabilities_<platform>`；领域层只依赖接口，不依赖平台 |
| 平台实现包 | 某一端对能力契约的实现。某能力在该端不适用时必须**显式表态**（抛错），不得静默返回空值或降级 |
| 共享载荷装载 | 让跨端公用材料进入各端产物并可在运行期读取的机制。**不经过 Flutter assets**，由各平台构建期按目录整体复制，Dart 经 `SharedPayload` 接口读取 |
| 标定 fixture | 合成素材（假昵称、假文案的界面截图与节点树）加期望输出，用于锁定感知启发式。**不是**跨端一致性断言，与「不做机械校验」的既有决定不冲突 |
| 感知启发式 | 在真机上反复试错标定出来的常量与判据：`chat_area()` 的像素锚点、`ChatAppAdapter` 的 per-app 节点路径、AX 控件面积阈值、截屏限流退避参数。本项目最贵的资产 |
| 单端独有功能 | 迁移前只在一端存在的功能（Android 知识库、macOS 记忆桥、Windows 反注入过滤、Windows 自更新检查）。迁移后统一为三端可用 |
| 面板窗 / 主窗路由 | 桌面端界面的两类落点：必须独立成窗的（悬浮球、面板、详情浮层）与收进主窗口的页面（设置、趋势） |
| 冻结（旧端） | 迁移期间旧三端只修阻塞级缺陷、不接新功能；每端被替换后打 git tag 归档再删除 |

## 边界规则

- 改应用显示名 → 只动 `integrations/` 与 `PRIVACY.md`。
- 改悬浮球显示名 → 只动球面与球自带文案（球的窗口标题、无障碍标签）；应用显示名与技术标识不动。
- 改 Skill 标识 → 需同时评估已安装用户的升级路径，另开 ADR。
- 往仓库根新增条目 → 必须在同一次提交里登记进 `scripts/validate_layout.py` 的白名单，并注明所属层与留在根的理由；未登记的条目会让 CI 失败。
- 上游载荷内容只放 `goutoujunshi/`，自有载荷内容只放 `miaotoujunshi/`，应用层实现只放 `integrations/`
  （根级例外见上节与白名单）。
- 两个 `references/` 不同层：`goutoujunshi/references/` 是上游载荷的参考库（上游所有，逐字节一致）；
  `miaotoujunshi/references/` 是本仓自有的参考材料（本仓所有；给模型读的散文放 `knowledge/`，
  给代码读的结构化数据放 `data/`）。跨端共用的材料一律放自有载荷，**不要放进某个单端目录**。
- **跨端公用材料三端一律在运行期读文件**：不得在任一端内联副本，不得放在 `integrations/<port>/` 下。
  各端打包必须**按目录整体**纳入自有载荷（Windows Flutter runner 的 CMake install、Android 的
  `assets`、macOS Flutter runner 的 `sync_shared_payload.sh` 都登记 `miaotoujunshi/` 本身，
  不逐文件列）；读不到即报错，不降级回内联副本。
  取舍与代价见 `docs/adr/0005`（读文件不内联）与 `docs/adr/0006`（材料放在哪）。
- 上游载荷目录 `goutoujunshi/` 必须与上游**逐字节一致**：`check_upstream.py` 的 `drifted` 与
  `only this repo has` 两行都必须恒为 0。本仓对 skill 内容的任何意见一律落在自有载荷或应用层，
  不改上游载荷；要改 skill 本身只能提给上游（见 `docs/adr/0004`）。
- 上游 `goutoujunshi` 的 `documentation/`（7 个开发文档）**未导入**；本仓 `documentation/` 是应用目录，与上游同名但不同义，不要按上游语义理解。
- model prompt 中的自称属于 Skill 语义层，不随应用改名而变。
- 上游 `jev-chat` 的版权、许可证与 NOTICE 段落是署名义务，任何情况下不得改写。
- 面板头部有分析时显示「分析所属会话」，无分析时显示「当前会话」；不得显示裸包名。
- 只读态只撤销「填入」，不撤销「复制」与「详细分析」——用户仍应能读到那份候选。
- 跨端公用材料**不得经 Flutter assets 装载**（Flutter 的 assets 目录声明不递归，会破坏「新增文件零改动」）。
  各平台构建期按目录整体复制，Dart 统一经 `SharedPayload` 接口读；读不到即报错，不降级（`docs/adr/0008`）。
- 能力契约的每个方法在任何平台都必须表态：能实现就实现，不能实现就抛错。**不得**静默返回空值、空集合或默认值。
- 迁移期间尚未替换的旧端**冻结**：只修阻塞级缺陷，不接新功能；每端被 Flutter 版替换并验收后才删除，删除前先打 git tag。
