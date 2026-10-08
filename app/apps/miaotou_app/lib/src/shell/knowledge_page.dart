import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/colors.dart';
import '../design/copy.dart';
import '../design/spacing.dart';
import '../widgets/empty_state.dart';
import '../widgets/labeled_block.dart';

/// The knowledge base, as a list of contacts grouped by application.
///
/// A contact's [KnowledgeContact.packageNames] are the grouping key, and the
/// section header shows the display name recorded beside each package
/// ([KnowledgeContact.packageAppNames]) rather than the bare id. The same person
/// can be seen in several chat applications, so each application gets a section.
/// Tapping a contact expands it to show the profile fields, an edit entry that
/// fills those fields in, and the conversation history saved alongside it.
class KnowledgePage extends StatefulWidget {
  const KnowledgePage({super.key, required this.store, required this.payload});

  final KnowledgeStore store;

  /// Read once for the stage/goal enum the edit form offers as a dropdown, so
  /// the options are the payload's own vocabulary rather than a second copy.
  final SharedPayload payload;

  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
  List<KnowledgeContact>? _contacts;
  RelationshipVocabulary? _vocabulary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<KnowledgeContact> contacts;
    RelationshipVocabulary? vocabulary;
    try {
      contacts = await widget.store.contacts();
    } on Object {
      contacts = const <KnowledgeContact>[];
    }
    try {
      final SharedMaterial material =
          await SharedMaterial.load(widget.payload);
      vocabulary = material.vocabulary.relationship;
    } on Object {
      // A payload that will not parse must not blank the page; the edit form
      // falls back to free text without the dropdown.
      vocabulary = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _contacts = contacts;
      _vocabulary = vocabulary;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    final List<KnowledgeContact>? contacts = _contacts;

    if (contacts == null) {
      // Loading: the store has not answered yet. Not a spinner that promises a
      // value — a blank read that resolves into the list or the empty state.
      return const SizedBox.shrink();
    }
    if (contacts.isEmpty) {
      return EmptyState(message: copy.text(CopyKey.knowledgeEmpty));
    }

    // Group by package, in first-seen order. A contact with no package sits
    // under the unnamed bucket rather than disappearing.
    final Map<String, List<KnowledgeContact>> grouped =
        <String, List<KnowledgeContact>>{};
    for (final KnowledgeContact contact in contacts) {
      final List<String> packages = contact.packageNames.isEmpty
          ? const <String>['']
          : contact.packageNames;
      for (final String package in packages) {
        grouped.putIfAbsent(package, () => <KnowledgeContact>[]).add(contact);
      }
    }

    return ListView(
      padding: AppSpacing.page,
      children: <Widget>[
        for (final MapEntry<String, List<KnowledgeContact>> entry
            in grouped.entries) ...<Widget>[
          _AppHeader(name: _appName(copy, entry.key, contacts)),
          for (final KnowledgeContact contact in entry.value)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.m),
              child: _ContactCard(
                store: widget.store,
                contact: contact,
                vocabulary: _vocabulary,
                onChanged: _load,
              ),
            ),
        ],
      ],
    );
  }

  String _appName(
    AppCopy copy,
    String package,
    List<KnowledgeContact> contacts,
  ) {
    if (package.isEmpty) {
      return copy.text(CopyKey.knowledgeAppUnknown);
    }
    // A name the user recorded beside the package wins; failing that the known
    // table; failing that the package id itself.
    for (final KnowledgeContact contact in contacts) {
      final String recorded = contact.packageAppNames[package] ?? '';
      if (recorded.isNotEmpty) {
        return recorded;
      }
    }
    return appDisplayNames[package] ?? package;
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s, top: AppSpacing.s),
      child: Text(name, style: theme.textTheme.titleSmall),
    );
  }
}

/// One contact, expandable into its profile fields, an edit form, and history.
class _ContactCard extends StatefulWidget {
  const _ContactCard({
    required this.store,
    required this.contact,
    required this.onChanged,
    this.vocabulary,
  });

  final KnowledgeStore store;
  final KnowledgeContact contact;
  final VoidCallback onChanged;
  final RelationshipVocabulary? vocabulary;

  @override
  State<_ContactCard> createState() => _ContactCardState();
}

class _ContactCardState extends State<_ContactCard> {
  bool _expanded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
  }

  void _openHistory() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => KnowledgeHistoryPage(
          store: widget.store,
          contact: widget.contact,
        ),
      ),
    );
  }

  Future<void> _edit() async {
    final KnowledgeContact? updated = await showDialog<KnowledgeContact>(
      context: context,
      builder: (BuildContext context) => _ContactEditDialog(
        contact: widget.contact,
        vocabulary: widget.vocabulary,
      ),
    );
    if (updated == null) {
      return;
    }
    try {
      await widget.store.saveContact(updated);
    } on Object {
      // A store that will not answer must not crash the page; the field edit is
      // best-effort and the list simply keeps its previous reading.
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    final KnowledgeContact contact = widget.contact;

    final List<(CopyKey, String)> fields = <(CopyKey, String)>[
      (CopyKey.profileStage, contact.stage),
      (CopyKey.profileGoal, contact.goal),
      (CopyKey.profileBackground, contact.relationship),
      (CopyKey.profileNotes, contact.notes),
    ];
    final List<(CopyKey, String)> filled = <(CopyKey, String)>[
      for (final (CopyKey key, String value) in fields)
        if (value.isNotEmpty) (key, value),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              onTap: _toggle,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      contact.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
            if (_expanded) ...<Widget>[
              AppSpacing.gapM,
              if (filled.isEmpty)
                Text(copy.text(CopyKey.knowledgeNoFields))
              else
                for (final (CopyKey key, String value) in filled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.m),
                    child: LabeledBlock(label: copy.text(key), value: value),
                  ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(copy.text(CopyKey.knowledgeEdit)),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _openHistory,
                  icon: const Icon(Icons.history),
                  label: Text(copy.text(CopyKey.knowledgeViewHistory)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The full conversation history of one contact, read at length.
///
/// A contact's history can grow without bound, so it is a page of its own rather
/// than a block that inflates the card it came from. Entries load in pages of
/// [_pageSize] (oldest first) and the list appends the next page as it scrolls;
/// a date header separates one day from the next, so a long chat reads as days
/// rather than as one wall of lines.
class KnowledgeHistoryPage extends StatefulWidget {
  const KnowledgeHistoryPage({
    super.key,
    required this.store,
    required this.contact,
  });

  final KnowledgeStore store;
  final KnowledgeContact contact;

  @override
  State<KnowledgeHistoryPage> createState() => _KnowledgeHistoryPageState();
}

class _KnowledgeHistoryPageState extends State<KnowledgeHistoryPage> {
  static const int _pageSize = 50;

  /// All the entries loaded so far, oldest first.
  final List<KnowledgeLogEntry> _entries = <KnowledgeLogEntry>[];

  /// Whether another page can still be loaded.
  bool _hasMore = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) {
      return;
    }
    _loading = true;
    List<KnowledgeLogEntry> page;
    try {
      page = await widget.store.recentLog(
        widget.contact.id,
        limit: _entries.length + _pageSize,
      );
    } on Object {
      page = const <KnowledgeLogEntry>[];
    }
    if (!mounted) {
      return;
    }
    // `recentLog` returns the newest `limit` in full; only the entries beyond
    // what is already on screen are new.
    final int before = _entries.length;
    setState(() {
      if (page.length <= before) {
        _hasMore = false;
      } else {
        _entries
          ..clear()
          ..addAll(page);
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(copy.text(CopyKey.knowledgeHistoryTitle)),
      ),
      body: _entries.isEmpty
          ? (_hasMore
                ? const Center(child: CircularProgressIndicator())
                : EmptyState(message: copy.text(CopyKey.knowledgeHistoryEmpty)))
          : NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification notification) {
                if (notification.metrics.extentAfter < 200) {
                  _loadMore();
                }
                return false;
              },
              child: ListView.builder(
                padding: AppSpacing.page,
                itemCount: _entries.length + (_hasMore ? 1 : 0),
                itemBuilder: (BuildContext context, int index) {
                  if (index >= _entries.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.m,
                      ),
                      child: Center(
                        child: TextButton(
                          onPressed: _loadMore,
                          child: Text(copy.text(CopyKey.knowledgeHistoryLoadMore)),
                        ),
                      ),
                    );
                  }
                  final KnowledgeLogEntry entry = _entries[index];
                  final bool startsNewDay = index == 0 ||
                      !_sameDay(_entries[index - 1].timestamp, entry.timestamp);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (startsNewDay)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppSpacing.m,
                            bottom: AppSpacing.s,
                          ),
                          child: Text(
                            _dayLabel(entry.timestamp),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.of(context).textMuted,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: Text(
                          '${copy.text(_speakerKey(entry.speaker))}：${entry.text}',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// A day's header, `M月d日` for the local calendar.
  static String _dayLabel(DateTime time) => '${time.month}月${time.day}日';

  CopyKey _speakerKey(Speaker speaker) => switch (speaker) {
    Speaker.me => CopyKey.panelSpeakerMe,
    Speaker.other => CopyKey.panelSpeakerOther,
    Speaker.unknown => CopyKey.panelSpeakerUnknown,
  };
}

/// The four editable fields of a contact, in a dialog.
///
/// `stage` and `goal` are a closed vocabulary (loaded from the shared payload),
/// so they are dropdowns; `background` and `notes` are free text. Every field
/// carries a helper line that says what it is for.
class _ContactEditDialog extends StatefulWidget {
  const _ContactEditDialog({required this.contact, this.vocabulary});

  final KnowledgeContact contact;
  final RelationshipVocabulary? vocabulary;

  @override
  State<_ContactEditDialog> createState() => _ContactEditDialogState();
}

class _ContactEditDialogState extends State<_ContactEditDialog> {
  late final TextEditingController _stageText =
      TextEditingController(text: widget.contact.stage);
  late final TextEditingController _goalText =
      TextEditingController(text: widget.contact.goal);
  late final TextEditingController _relationship =
      TextEditingController(text: widget.contact.relationship);
  late final TextEditingController _notes =
      TextEditingController(text: widget.contact.notes);
  late String _stage = widget.contact.stage;
  late String _goal = widget.contact.goal;

  @override
  void dispose() {
    _stageText.dispose();
    _goalText.dispose();
    _relationship.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);
    final RelationshipVocabulary? vocabulary = widget.vocabulary;
    final List<String> stages = vocabulary?.stages ?? const <String>[];
    final List<String> goals = (vocabulary?.goals.keys ?? const <String>[])
        .toList(growable: false);

    return AlertDialog(
      title: Text(copy.text(CopyKey.knowledgeEditTitle)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _dropdown(
              copy,
              value: _stage,
              label: CopyKey.profileStage,
              helper: CopyKey.knowledgeStageHelp,
              options: stages,
              textController: _stageText,
              onChanged: (String value) => setState(() => _stage = value),
            ),
            _dropdown(
              copy,
              value: _goal,
              label: CopyKey.profileGoal,
              helper: CopyKey.knowledgeGoalHelp,
              options: goals,
              textController: _goalText,
              onChanged: (String value) => setState(() => _goal = value),
            ),
            _textField(
              copy,
              controller: _relationship,
              label: CopyKey.profileBackground,
              helper: CopyKey.knowledgeBackgroundHelp,
            ),
            _textField(
              copy,
              controller: _notes,
              label: CopyKey.profileNotes,
              helper: CopyKey.knowledgeNotesHelp,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(copy.text(CopyKey.knowledgeEditCancel)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_saved()),
          child: Text(copy.text(CopyKey.knowledgeEditSave)),
        ),
      ],
    );
  }

  KnowledgeContact _saved() => KnowledgeContact(
    id: widget.contact.id,
    name: widget.contact.name,
    updatedAt: DateTime.now(),
    aliases: widget.contact.aliases,
    packageNames: widget.contact.packageNames,
    packageAppNames: widget.contact.packageAppNames,
    relationship: _relationship.text.trim(),
    notes: _notes.text.trim(),
    stage: _stage.trim(),
    goal: _goal.trim(),
    autoSummary: widget.contact.autoSummary,
  );

  Widget _dropdown(
    AppCopy copy, {
    required String value,
    required CopyKey label,
    required CopyKey helper,
    required List<String> options,
    required TextEditingController textController,
    required ValueChanged<String> onChanged,
  }) {
    // When the vocabulary is unavailable (payload did not load) the dropdown
    // has nothing to offer; fall back to a text field so the field stays
    // editable rather than vanishing.
    if (options.isEmpty) {
      return _textField(
        copy,
        controller: textController,
        label: label,
        helper: helper,
        onChanged: onChanged,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: DropdownButtonFormField<String>(
        initialValue: options.contains(value) ? value : null,
        decoration: InputDecoration(
          labelText: copy.text(label),
          helperText: copy.text(helper),
        ),
        items: <DropdownMenuItem<String>>[
          for (final String option in options)
            DropdownMenuItem<String>(value: option, child: Text(option)),
        ],
        onChanged: (String? selected) {
          if (selected != null) {
            onChanged(selected);
          }
        },
      ),
    );
  }

  Widget _textField(
    AppCopy copy, {
    required TextEditingController controller,
    required CopyKey label,
    required CopyKey helper,
    ValueChanged<String>? onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: copy.text(label),
            helperText: copy.text(helper),
          ),
        ),
      );
}
