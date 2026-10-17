import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freebuddy/l10n/generated/app_localizations.dart';

import '../../../platform_stuff/android/background/foreground_service.dart';
import '../../../platform_stuff/android/background/periodic.dart';
import '../../app_settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final settings = context.read<AppSettings>();
    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          StreamBuilder<int>(
            stream: settings.caseBatteryThreshold,
            initialData: 20,
            builder: (context, snapshot) {
              final threshold = (snapshot.data ?? 20).clamp(5, 50);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.caseBatteryThresholdTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(l.caseBatteryThresholdDescription),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              min: 5,
                              max: 50,
                              divisions: 9,
                              value: threshold.toDouble(),
                              label: '$threshold%',
                              onChanged: (value) async {
                                await settings.setCaseBatteryThreshold(
                                  value.round(),
                                );
                                await checkStoredCaseBatteryNotification();
                              },
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Text(
                              '$threshold%',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        l.caseBatteryThresholdHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pushNamed('/settings/about'),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(l.pageAboutTitle),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: requestBackgroundPermissions,
            icon: const Icon(Icons.battery_saver),
            label: Text(l.backgroundServicePermission),
          ),
        ],
      ),
    );
  }
}
