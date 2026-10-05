import 'package:flutter/material.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'design/copy.dart';
import 'design/spacing.dart';

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
  'permissions.read',
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

/// The other member the report deliberately accounts for by name.
///
/// `Permissions.openSettings` opens a system page, which is a thing the user asks
/// for exactly as an injection is, so start-up never calls it. It is reported as
/// unasked for the same reason [unaskedMember] is: [startupProbeNames] and these
/// two together have to name every member of the contract, or a member added
/// tomorrow would be missing from the one screen that exists to show the contract,
/// and nothing would say so.
const String unaskedSettingsMember = 'permissions.openSettings';

/// Every member the report either asks or accounts for by name.
///
/// Read by the test that checks the three lists against the manifest. A member
/// that is in none of them is invisible on the diagnostics page, which is a hole
/// rather than a decision — the decision has to be written down here.
const List<String> reportedMemberNames = <String>[
  ...startupProbeNames,
  unaskedMember,
  unaskedSettingsMember,
];

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

  /// The one line at the top: eleven capabilities, and how each of them answered.
  ///
  /// Built from copy keys rather than written here, even though the row labels
  /// below are the same words: a screen that spells a state two ways is how the
  /// three ports came to disagree about what a refusal meant.
  String summary(AppCopy copy) =>
      '${copy.text(CopyKey.capabilitySummaryPrefix)}'
      '${copy.text(CopyKey.supportAnswered)} ${count(SupportAnswer.answered)}，'
      '${copy.text(CopyKey.supportUnsupported)} ${count(SupportAnswer.unsupported)}，'
      '${copy.text(CopyKey.supportNotYetBuilt)} ${count(SupportAnswer.notYetBuilt)}，'
      '${copy.text(CopyKey.supportFailed)} ${count(SupportAnswer.failed)}，'
      '${copy.text(CopyKey.supportUnasked)} ${count(null)}';
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
        implementation: implementations[member.split('.').first] ?? '',
        answer: await askCapability(() => probe(capabilities)),
      ),
    );
  }

  for (final String member in <String>[unaskedMember, unaskedSettingsMember]) {
    rows.add(
      CapabilityReportRow(
        member: member,
        implementation: implementations[member.split('.').first] ?? '',
        answer: null,
      ),
    );
  }

  return CapabilityReport(rows);
}

/// How one member answered, in words.
///
/// The unasked row is the interesting branch: it is not a refusal the platform
/// made, it is a decision the start-up made not to ask, and the screen has to
/// say which of the two it is looking at.
String describeAnswer(AppCopy copy, SupportAnswer? answer) => switch (answer) {
      null => copy.text(CopyKey.unaskedReason),
      SupportAnswer.answered => copy.text(CopyKey.supportAnswered),
      SupportAnswer.unsupported => copy.text(CopyKey.supportUnsupported),
      SupportAnswer.notYetBuilt => copy.text(CopyKey.supportNotYetBuilt),
      SupportAnswer.failed => copy.text(CopyKey.supportFailed),
    };

/// What this build can do, asked rather than assumed.
///
/// A placeholder screen in the sense that #11 replaced the shell around it, but
/// not a throwaway: it is the migration's own answer to "which of the eleven does
/// this port answer for", and after promotion it is what tells a user why a
/// button does nothing.
///
/// It is a body and not a [Scaffold] on purpose: the shell gives it its app bar
/// when it is the destination, and [CapabilityReportPage] gives it one when it
/// is pushed. A scaffold inside a scaffold would give it two.
class CapabilityReportView extends StatefulWidget {
  const CapabilityReportView({super.key, required this.capabilities});

  final CapabilitySet capabilities;

  @override
  State<CapabilityReportView> createState() => _CapabilityReportViewState();
}

class _CapabilityReportViewState extends State<CapabilityReportView> {
  late final Future<CapabilityReport> _report =
      buildCapabilityReport(widget.capabilities);

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);

    return FutureBuilder<CapabilityReport>(
      future: _report,
      builder: (BuildContext context, AsyncSnapshot<CapabilityReport> snapshot) {
        final CapabilityReport? report = snapshot.data;
        if (snapshot.hasError) {
          return Center(
            child: Text('${copy.text(CopyKey.reportFailed)}${snapshot.error}'),
          );
        }
        if (report == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView.builder(
          padding: AppSpacing.page,
          itemCount: report.rows.length + 2,
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.m),
                child: Text(copy.text(CopyKey.diagnosticsIntro)),
              );
            }
            if (index == 1) {
              return ListTile(
                title: Text(report.summary(copy)),
                dense: true,
                contentPadding: EdgeInsets.zero,
              );
            }
            final CapabilityReportRow row = report.rows[index - 2];
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(row.member),
              subtitle: Text(
                row.implementation.isEmpty
                    ? copy.text(CopyKey.unknownImplementation)
                    : row.implementation,
              ),
              trailing: Text(describeAnswer(copy, row.answer)),
            );
          },
        );
      },
    );
  }
}

/// The report as a pushed route: a scaffold of its own, with its own way back.
class CapabilityReportPage extends StatelessWidget {
  const CapabilityReportPage({super.key, required this.capabilities});

  final CapabilitySet capabilities;

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = CopyScope.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(copy.text(CopyKey.diagnosticsTitle))),
      body: CapabilityReportView(capabilities: capabilities),
    );
  }
}
