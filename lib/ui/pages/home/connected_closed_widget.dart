import 'package:flutter/material.dart';
import 'package:freebuddy/l10n/generated/app_localizations.dart';

import '../../../platform_stuff/android/background/foreground_service.dart';

class ConnectedClosedWidget extends StatelessWidget {
  const ConnectedClosedWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final t = Theme.of(context);
    final tt = t.textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          l.pageHomeConnectedClosed,
          style: tt.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(l.pageHomeConnectedClosedDesc, textAlign: TextAlign.center),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => nativeMonitorChannel.invokeMethod<void>('start'),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(l.pageHomeConnectedClosedConnect),
          ),
        ),
      ],
    );
  }
}
