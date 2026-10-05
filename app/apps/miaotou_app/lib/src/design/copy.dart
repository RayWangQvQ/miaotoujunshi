import 'package:flutter/material.dart';

/// Every string a person reads, in one file.
///
/// The three ports wrote their copy three times, and the drift was not only in
/// wording: the same state was named two ways on two ports, which is how a
/// "排序暂不可用" came to be shown on one as a ranking and on another as a
/// failure. A key here is one decision about one state, and the audit in
/// `test/` fails if a Chinese literal is written anywhere else in `lib/`.
///
/// ## What is deliberately not here
///
/// * **The domain's own sentences.** `intentConfidenceLabel` and the strategy
///   rendering in `miaotou_domain` are part of what the model is told and what
///   comes back; they travel with the domain, not with the chrome.
/// * **The payload's sentences.** The metric disclaimer is `metric_note` in
///   `trend-rules.json`. It is data, it is read at runtime, and a chart that
///   forgets to render it is a bug — not a missing translation.
/// * **The capability contract's identifiers.** `screenCapture.findTargetWindow`
///   names a member of `miaotou_capabilities`; it is not prose and translating
///   it would hide what it points at.
enum CopyKey {
  appTitle,

  navDetail,
  navTrend,
  navKnowledge,
  navSettings,

  detailTitle,
  detailEmpty,
  detailSupport,
  detailFacts,
  detailHypotheses,
  detailUnknowns,
  detailStrategy,
  detailRecommendation,
  detailNextStep,
  detailStopCondition,
  detailQuestion,
  detailCandidates,

  candidateCopy,
  candidateWeight,
  candidateUnranked,
  candidateRank,
  candidateReason,
  candidateTradeoff,
  rankingUnavailable,

  trendTitle,
  trendEmpty,
  trendDayCount,
  trendDayUnit,
  trendMessages,
  trendSource,

  knowledgeTitle,
  knowledgeEmpty,
  profileLabel,
  profileStage,
  profileGoal,
  profileBackground,
  profileMyMbti,
  profileTheirMbti,
  profileMyScore,
  profileTheirScore,
  profileNotes,

  settingsTitle,
  settingsStorage,
  settingsReplySection,
  settingsReplyBaseUrl,
  settingsReplyModel,
  settingsReplyKey,
  settingsStrategySection,
  settingsStrategyProvider,
  settingsStrategyNone,
  settingsStrategyJev,
  settingsStrategyDeepSeek,
  settingsStrategyBaseUrl,
  settingsStrategyModel,
  settingsStrategyKey,
  settingsRelationshipBackground,
  settingsGoalDefault,
  settingsAutoAnalyze,
  settingsSave,
  settingsSaved,
  settingsLoadFailed,
  settingsSaveFailed,
  settingsGallery,
  settingsDiagnostics,

  galleryTitle,
  galleryIntro,
  galleryCandidateCard,
  galleryBadge,
  galleryTrendChart,
  galleryToneNeutral,
  galleryTonePositive,
  galleryToneCaution,
  galleryToneAlert,
  gallerySampleTitle,
  gallerySampleReply,
  gallerySampleReason,
  gallerySampleTradeoff,
  gallerySampleNote,
  // The panel preview needs names for two conversations. They are copy keys and
  // not literals in `gallery_page.dart` for the same reason everything else
  // there is: a literal would be a second source of truth, and the audit that
  // renders the gallery with a sentinel copy would have to let it through.
  gallerySampleApp,
  gallerySampleAppOther,
  gallerySampleThread,
  gallerySampleThreadOther,

  diagnosticsTitle,
  diagnosticsIntro,
  capabilitySummaryPrefix,
  supportAnswered,
  supportUnsupported,
  supportNotYetBuilt,
  supportFailed,
  supportUnasked,
  unaskedReason,
  reportFailed,
  unknownImplementation,

  // The floating panel (#12). The header's four fallbacks are one decision each,
  // and the placeholders are how the separator stays here instead of being
  // punctuation typed into a widget.
  panelLabelPair,
  panelLabelTitleOnly,
  panelLabelUnrecognised,
  panelStatusNotAnalysed,
  panelStatusViewing,
  panelStatusBrowsing,
  panelReadOnlyBanner,
  panelEmpty,
  panelDraftLabel,
  panelActionFill,
  panelActionDetails,
  panelActionReanalyse,
  panelActionAnalyseCurrent,
  panelActionRecognise,
  panelNoteSidesGuessed,
  panelNoteSidesNotSplit,
  panelActionClose,
  panelPreviewCurrent,
  panelPreviewBrowsing,

  runtimeAnalysing,
  runtimeConfigureModels,
  runtimeConversationChanged,
  runtimeNoConversation,
  runtimeCopied,
  runtimeFilled,
  runtimeFillUnverified,
  runtimeAnalysisFailed,
  runtimeRecognising,
  runtimeCaptureFailed,
  runtimeNothingRecognised,
  runtimeHttpStatus,
  runtimeNetworkFailure,
  runtimeInvalidResponse,

  noValue,
}

/// A set of strings addressed by [CopyKey].
///
/// A map rather than a class of getters, so that [AppCopy.sentinel] can exist:
/// that factory is what lets a test render every page with every string replaced
/// by one marker, and then assert that not one literal slipped past the copy
/// file. A class of thirty getters could not be swapped out like that.
final class AppCopy {
  const AppCopy(this._values);

  final Map<CopyKey, String> _values;

  String text(CopyKey key) {
    final String? value = _values[key];
    if (value == null) {
      throw StateError(
        'no copy for ${key.name}; AppCopy must cover every CopyKey, and the '
        'test that renders every page with a sentinel is what catches a hole',
      );
    }
    return value;
  }

  /// Every string this copy holds. Read by the audit.
  Iterable<String> get values => _values.values;

  /// The keys this copy holds. A partial copy is a hole, and a hole is a page
  /// that falls back to whatever literal somebody typed.
  Iterable<CopyKey> get keys => _values.keys;

  /// The one copy the application ships.
  static const AppCopy zh = AppCopy(_zh);

  /// One marker for every key. For tests only: it is what makes every
  /// hard-coded string visible, because a hard-coded string is the one string
  /// on the page that is not the marker.
  factory AppCopy.sentinel(String marker) => AppCopy(<CopyKey, String>{
    for (final CopyKey key in CopyKey.values) key: marker,
  });

  static const Map<CopyKey, String> _zh = <CopyKey, String>{
    CopyKey.appTitle: '喵头军师',

    CopyKey.navDetail: '详情',
    CopyKey.navTrend: '走势',
    CopyKey.navKnowledge: '知识库',
    CopyKey.navSettings: '设置',

    CopyKey.detailTitle: '详情',
    CopyKey.detailEmpty: '还没有分析过一次对话。',
    CopyKey.detailSupport: '接住情绪',
    CopyKey.detailFacts: '看到的事实',
    CopyKey.detailHypotheses: '猜测',
    CopyKey.detailUnknowns: '还不确定的',
    CopyKey.detailStrategy: '策略',
    CopyKey.detailRecommendation: '建议',
    CopyKey.detailNextStep: '下一步',
    CopyKey.detailStopCondition: '停手条件',
    CopyKey.detailQuestion: '可以问的一句',
    CopyKey.detailCandidates: '候选回复',

    CopyKey.candidateCopy: '复制',
    CopyKey.candidateWeight: '权重',
    CopyKey.candidateUnranked: '未排序',
    CopyKey.candidateRank: '候选',
    CopyKey.candidateReason: '理由',
    CopyKey.candidateTradeoff: '代价',
    CopyKey.rankingUnavailable: '排序暂不可用',

    CopyKey.trendTitle: '走势',
    CopyKey.trendEmpty: '还没有走势数据。',
    CopyKey.trendDayCount: '共 ',
    CopyKey.trendDayUnit: ' 天',
    CopyKey.trendMessages: '条消息',
    CopyKey.trendSource: '来源',

    CopyKey.knowledgeTitle: '知识库',
    CopyKey.knowledgeEmpty: '还没有记录过任何人的资料。',
    CopyKey.profileLabel: '称呼',
    CopyKey.profileStage: '阶段',
    CopyKey.profileGoal: '目标',
    CopyKey.profileBackground: '背景',
    CopyKey.profileMyMbti: '我的 MBTI',
    CopyKey.profileTheirMbti: '对方 MBTI',
    CopyKey.profileMyScore: '我的评分',
    CopyKey.profileTheirScore: '对方评分',
    CopyKey.profileNotes: '备注',

    CopyKey.settingsTitle: '设置',
    CopyKey.settingsStorage: '偏好保存在应用数据中；密钥单独保存在系统凭据存储中。',
    CopyKey.settingsReplySection: '回复模型',
    CopyKey.settingsReplyBaseUrl: '兼容 OpenAI 的 API 地址（到 /v1）',
    CopyKey.settingsReplyModel: '回复模型',
    CopyKey.settingsReplyKey: '回复模型密钥',
    CopyKey.settingsStrategySection: '独立策略判断',
    CopyKey.settingsStrategyProvider: '策略提供方',
    CopyKey.settingsStrategyNone: '关闭（由回复模型直接判断）',
    CopyKey.settingsStrategyJev: 'TypeSafe Jev',
    CopyKey.settingsStrategyDeepSeek: 'DeepSeek',
    CopyKey.settingsStrategyBaseUrl: '策略 API 地址',
    CopyKey.settingsStrategyModel: '策略模型',
    CopyKey.settingsStrategyKey: '策略模型密钥',
    CopyKey.settingsRelationshipBackground: '关系与背景',
    CopyKey.settingsGoalDefault: '自然接话',
    CopyKey.settingsAutoAnalyze: '对话变化后自动分析',
    CopyKey.settingsSave: '保存设置',
    CopyKey.settingsSaved: '设置已保存',
    CopyKey.settingsLoadFailed: '无法读取设置',
    CopyKey.settingsSaveFailed: '无法保存设置',
    CopyKey.settingsGallery: '组件陈列',
    CopyKey.settingsDiagnostics: '能力自检',

    CopyKey.galleryTitle: '组件陈列',
    CopyKey.galleryIntro: '主窗口各页与悬浮面板复用同一套组件，这里把它们单独摆出来。',
    CopyKey.galleryCandidateCard: '候选卡片',
    CopyKey.galleryBadge: '状态徽章',
    CopyKey.galleryTrendChart: '走势图',
    CopyKey.galleryToneNeutral: '中性',
    CopyKey.galleryTonePositive: '正常',
    CopyKey.galleryToneCaution: '注意',
    CopyKey.galleryToneAlert: '出错',
    CopyKey.gallerySampleTitle: '示例走势',
    CopyKey.gallerySampleReply: '那你先忙，忙完了跟我说一声。',
    CopyKey.gallerySampleReason: '给对方留出时间，同时把下一次开口留在自己这边。',
    CopyKey.gallerySampleTradeoff: '这一轮里你主动开口的机会会晚一点。',
    CopyKey.gallerySampleNote: '示例数据的口径说明；真实走势图下方的这句话来自共享载荷的 metric_note。',
    CopyKey.gallerySampleApp: '微信',
    CopyKey.gallerySampleAppOther: 'QQ',
    CopyKey.gallerySampleThread: '示例会话',
    CopyKey.gallerySampleThreadOther: '另一个会话',

    CopyKey.diagnosticsTitle: '能力自检',
    CopyKey.diagnosticsIntro: '这一版在所在端能做什么，是问出来的，不是猜出来的。',
    CopyKey.capabilitySummaryPrefix: '十项能力：',
    CopyKey.supportAnswered: '已应答',
    CopyKey.supportUnsupported: '永久不支持',
    CopyKey.supportNotYetBuilt: '尚未实现',
    CopyKey.supportFailed: '异常',
    CopyKey.supportUnasked: '未询问',
    CopyKey.unaskedReason: '未询问：调用它等于往聊天窗口里写入文本',
    CopyKey.reportFailed: '自检失败：',
    CopyKey.unknownImplementation: '未知',

    CopyKey.panelLabelPair: '{app} · {title}',
    CopyKey.panelLabelTitleOnly: '{title}',
    CopyKey.panelLabelUnrecognised: '未识别会话',
    CopyKey.panelStatusNotAnalysed: '尚未分析',
    CopyKey.panelStatusViewing: '正在看',
    CopyKey.panelStatusBrowsing: '浏览中 · 只读',
    CopyKey.panelReadOnlyBanner: '你现在看的不是这次分析的会话，所以「填入」停用了；复制和详情仍然可用。',
    CopyKey.panelEmpty: '先读取对话，再让军师帮你想下一句。',
    CopyKey.panelDraftLabel: '编辑回复',
    CopyKey.panelActionFill: '填入',
    CopyKey.panelActionDetails: '详情',
    CopyKey.panelActionRecognise: '识别一次',
    CopyKey.panelNoteSidesGuessed: '这一屏是截图识别的，左右按位置推定，可能有误；填入前请核对。',
    CopyKey.panelNoteSidesNotSplit: 'OCR 未分边，把全部消息当作对方所说',
    CopyKey.panelActionReanalyse: '重新分析',
    CopyKey.panelActionAnalyseCurrent: '分析当前会话',
    CopyKey.panelActionClose: '关闭',
    CopyKey.panelPreviewCurrent: '悬浮面板 · 正在看',
    CopyKey.panelPreviewBrowsing: '悬浮面板 · 浏览中（只读）',

    CopyKey.runtimeAnalysing: '正在分析当前会话…',
    CopyKey.runtimeConfigureModels: '请先在设置中填写回复模型地址、模型和密钥。',
    CopyKey.runtimeConversationChanged: '会话已切换，未填入；请分析当前会话后重试。',
    CopyKey.runtimeNoConversation: '当前没有可分析的会话。',
    CopyKey.runtimeCopied: '已复制。',
    CopyKey.runtimeFilled: '已填入并确认落地，请检查后自行发送。',
    CopyKey.runtimeFillUnverified: '无法确认是否填入；内容已复制，请手动粘贴。',
    CopyKey.runtimeAnalysisFailed: '分析失败，请检查模型设置和网络后重试。',
    CopyKey.runtimeRecognising: '正在截屏识别这一屏…',
    CopyKey.runtimeCaptureFailed: '拿不到画面。请确认已开启无障碍与悬浮窗，且该界面允许截屏。',
    CopyKey.runtimeNothingRecognised: '这一屏没有识别到可用的文字。',
    CopyKey.runtimeHttpStatus: '模型请求失败（HTTP {status}），请检查地址、模型和密钥。',
    CopyKey.runtimeNetworkFailure: '模型请求失败，请检查网络和 API 地址。',
    CopyKey.runtimeInvalidResponse: '模型返回了无法识别的响应。',

    CopyKey.noValue: '未填写',
  };
}

/// Puts a copy where every page below it can read it.
///
/// An [InheritedWidget] rather than a constructor parameter threaded through
/// five pages: a page that forgot to ask for the copy would still compile and
/// would silently fall back to a literal, which is the failure this ticket
/// exists to prevent. Asking the context means there is no way to get a string
/// on screen without going through [AppCopy].
class CopyScope extends InheritedWidget {
  const CopyScope({super.key, required this.copy, required super.child});

  final AppCopy copy;

  static AppCopy of(BuildContext context) {
    final CopyScope? scope = context
        .dependOnInheritedWidgetOfExactType<CopyScope>();
    if (scope == null) {
      throw StateError(
        'no CopyScope above this widget; the application was built without one, '
        'and a page is asking for a string it would otherwise have hard-coded',
      );
    }
    return scope.copy;
  }

  @override
  bool updateShouldNotify(CopyScope oldWidget) => oldWidget.copy != copy;
}
