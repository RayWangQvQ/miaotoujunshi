import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// The members the shell asks about when it starts, and the only ones.
///
/// An allow-list rather than "everything except the writers", because the failure
/// has to be the safe one: a member added to the contract tomorrow is not asked
/// until somebody decides it may be. Running the whole manifest would, on a port
/// that implements it, put a panel on screen and type probe text into the user's
/// chat window every time the application started.
const List<String> startupProbeNames = <String>[
  'screenCapture.findTargetWindow',
  'uiTreeReader.readActiveChat',
  'uiTreeReader.snapshots',
  'ocr.recognize',
  'floatingPanel.events',
  'sharedPayload.list',
  'preferences.keys',
  'secretStore.keys',
  'knowledgeStore.notes',
  'knowledgeStore.contacts',
  'memoryStore.status',
];

/// The one capability with no member that is safe to ask.
///
/// `TextInject` offers injection and nothing else — there is no send path and none
/// may be added — so every member it has writes into another application's input
/// field. That is a thing the user asks for, never a thing start-up does.
const String unaskedMember = 'textInject.inject';
const String unaskedReason = '未询问：调用它等于往聊天窗口里写入文本';

/// One line of the report.
final class CapabilityReportRow {
  const CapabilityReportRow({
    required this.member,
    required this.implementation,
    required this.answer,
  });

  /// The contract member, as `capability.member`.
  final String member;

  /// The type answering for it, from [CapabilitySet.describe].
  final String implementation;

  /// How it answered, or null when the shell did not ask.
  final SupportAnswer? answer;
}

/// The whole report, in the order the manifest lists.
final class CapabilityReport {
  const CapabilityReport(this.rows);

  final List<CapabilityReportRow> rows;

  int count(SupportAnswer? answer) =>
      rows.where((CapabilityReportRow row) => row.answer == answer).length;

  /// The one line at the top: ten capabilities, and how each of them answered.
  String get summary => '十项能力：已应答 ${count(SupportAnswer.answered)}，'
      '永久不支持 ${count(SupportAnswer.unsupported)}，'
      '尚未实现 ${count(SupportAnswer.notYetBuilt)}，'
      '异常 ${count(SupportAnswer.failed)}，'
      '未询问 ${count(null)}';
}

/// Asks the safe members and records every answer, refusals included.
///
/// A refusal is data here, not an exception: that is the same rule the contract
/// states (ADR-0009 decision 2), and it is what lets one screen say what a port
/// supports without a device to try it on.
Future<CapabilityReport> buildCapabilityReport(CapabilitySet capabilities) async {
  final Map<String, String> implementations = capabilities.describe();
  final List<CapabilityReportRow> rows = <CapabilityReportRow>[];

  for (final String member in startupProbeNames) {
    final Future<Object?> Function(CapabilitySet)? probe = capabilityProbes[member];
    if (probe == null) {
      throw StateError(
        '$member is in the start-up allow-list but not in the contract manifest; '
        'the two have drifted apart',
      );
    }
    rows.add(
      CapabilityReportRow(
        member: member,
        implementation: implementations[member.split('.').first] ?? '未知',
        answer: await askCapability(() => probe(capabilities)),
      ),
    );
  }

  rows.add(
    CapabilityReportRow(
      member: unaskedMember,
      implementation: implementations[unaskedMember.split('.').first] ?? '未知',
      answer: null,
    ),
  );

  return CapabilityReport(rows);
}

/// Reads as one phrase, so the screen needs no logic of its own.
String describeAnswer(SupportAnswer? answer) => switch (answer) {
      null => unaskedReason,
      SupportAnswer.answered => '已应答',
      SupportAnswer.unsupported => '永久不支持',
      SupportAnswer.notYetBuilt => '尚未实现',
      SupportAnswer.failed => '异常',
    };

/// What this build can do, asked rather than assumed.
///
/// A placeholder screen in the sense that #11 will replace it, but not a
/// throwaway: it is the migration's own answer to "which of the ten does this port
/// answer for", and after promotion it is what tells a user why a button does
/// nothing.
class CapabilityReportPage extends StatefulWidget {
  const CapabilityReportPage({super.key, required this.capabilities});

  final CapabilitySet capabilities;

  @override
  State<CapabilityReportPage> createState() => _CapabilityReportPageState();
}

class _CapabilityReportPageState extends State<CapabilityReportPage> {
  late final Future<CapabilityReport> _report =
      buildCapabilityReport(widget.capabilities);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('喵头军师 · 能力契约自检')),
        body: FutureBuilder<CapabilityReport>(
          future: _report,
          builder: (BuildContext context, AsyncSnapshot<CapabilityReport> snapshot) {
            final CapabilityReport? report = snapshot.data;
            if (snapshot.hasError) {
              return Center(child: Text('自检失败：${snapshot.error}'));
            }
            if (report == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView.builder(
              itemCount: report.rows.length + 1,
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return ListTile(
                    title: Text(report.summary),
                    dense: true,
                  );
                }
                final CapabilityReportRow row = report.rows[index - 1];
                return ListTile(
                  dense: true,
                  title: Text(row.member),
                  subtitle: Text(row.implementation),
                  trailing: Text(describeAnswer(row.answer)),
                );
              },
            );
          },
        ),
      );
}
