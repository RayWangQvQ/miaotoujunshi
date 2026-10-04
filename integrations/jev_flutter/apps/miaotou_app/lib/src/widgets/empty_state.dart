import 'package:flutter/material.dart';

import '../design/colors.dart';
import '../design/spacing.dart';

/// The answer a page gives when there is nothing to show yet.
///
/// One widget for all of them, because "nothing yet" is a state a reader meets
/// four times on the first run and it should read the same way every time. It is
/// never a spinner: nothing is loading, and a spinner would be a promise.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Center(
      child: Padding(
        padding: AppSpacing.page,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colors.textMuted),
        ),
      ),
    );
  }
}
