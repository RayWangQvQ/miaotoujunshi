# 应用改名：狗头军师 → 喵头军师

- 状态：已接受
- 日期：2026-10-02

## 背景

`integrations/` 下的三端预览包在 debug 和打包后，应用名显示为「狗头军师 Jev Chat」，
与仓库目录名 `miaotoujunshi`、根 `README.md` 已经不一致。

## 决策

**分两层，只改应用层。**

| 层 | 名称 | 理由 |
| --- | --- | --- |
| Skill / Agent（`SKILL.md` frontmatter、`agents/openai.yaml`、`references/`、`examples/`、`scripts/check_upstream.py`） | 保持 `goutoujunshi` / 狗头军师 | Skill 是可独立分发的能力包，标识符已对外稳定；改名会让已安装的 skill 变成孤儿 |
| 应用（`integrations/jev_android`、`jev_windows`、`jev_mac`、打包产物、CI artifact、`PRIVACY.md`、`documentation/design/overlay-proposal.md`） | 中文「喵头军师」/ 标识符 `miaotoujunshi` | 用户可见的品牌，改名诉求来自这里 |

具体规则：

1. **中文显示名**：应用界面文字统一为「喵头军师」。唯一例外是悬浮球自身的显示名
   「喵球」——它是 UI 元件的名字而非应用名，不随应用名走（见「后果」里的三名分层）。
2. **英文标识符**：所有应用侧的技术标识统一为 `miaotoujunshi`，去掉 `jev-chat` 段
   （`Jev Chat` 是上游 `jev-chat-jarvis` 的品牌名，两个 NOTICE 明确禁止用它暗示背书）。
3. **model prompt 里的自称保持「狗头军师」**：`ReplyClient.kt`、`core.py`、`ranking.py`
   等 system prompt 是发给大模型的指令而非界面文字，属于 skill 语义层，本次不改。
   唯一例外：Android `ReplyClient.kt` 那句里嵌了要废弃的英文旧名，改为「你是喵头军师的
   即时通讯回复助手」。
4. **`applicationId` 改为 `com.miaotoujunshi.chat`**：接受代价——系统视为全新应用，
   旧包无法覆盖升级，必须卸载重装，本机设置、密钥与已同意保存的关系档案会清空。
5. **Mac Keychain 服务名改为 `ai.miaotoujunshi.*`**（含 `USER_AGENT`）：接受代价——
   存量用户已保存的 DeepSeek / OpenRouter / Jev 密钥会读不到，需重新填写。
6. **不动的东西**：`GOUTOU_JEV_API_KEY` 等环境变量名（用户已有配置的契约）、
   `namespace = "com.jev.probe"` 与 Kotlin 包路径（改名会波及全部 import，无收益）、
   上游 NOTICE/LICENSE 的版权与署名段落。

## 后果

- Windows 包升级路径断裂：发布新版本时必须在 README 与 App 内说明「卸载旧版再安装」。
- macOS 存量用户需重新填写全部 API 密钥（Keychain 服务名已变），README 中的
  `security add-generic-password` 示例已同步更新。
- 环境变量名仍是 `GOUTOU_*`，与新的应用名不一致。这是有意的取舍：改名会让存量用户的
  密钥配置失效，且 `PRIVACY.md` 已把它作为对外契约公布。若后续要统一，需单独评估迁移。
- 代码内所有应用侧仓库链接已统一为实际远端 `RayWangQvQ/miaotoujunshi`
  （此前 Android 的 `PRIVACY_URL` / `REPO_URL` 和 Windows 自更新接口指向的是过期的
  `shengjidaguai-china/goutoujunshi-jev-chat`）。`scripts/check_upstream.py` 里的
  `shengjidaguai-china/goutoujunshi` 是 skill 上游仓库，不属于应用侧，保持不变。
- Skill 与 App 名称从此不同（`goutoujunshi` vs `喵头军师`）。这是有意的分层，
  新增文档时应写明属于哪一层，避免再次混淆。
- 界面共有三个名字，各归其位：应用显示名「喵头军师」（窗口标题、应用图标、通知栏）、
  悬浮球显示名「喵球」（球面与球自带文案：球的窗口标题、无障碍标签）、文案拟人称谓
  「军师」（如「军师建议」「让军师帮你想下一句」）。三者是刻意并存的，不是遗留不一致；
  改球名不会波及另两个名字，改应用名也不会波及球名。`GLOSSARY.md` 的边界规则按此约束。
