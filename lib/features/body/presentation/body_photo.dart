import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// A progress photo, or a note that it is not on this device (taken on
/// another one, while there is no backup to fetch it from).
class BodyPhoto extends StatelessWidget {
  const BodyPhoto({
    super.key,
    required this.file,
    required this.label,
    required this.missingText,
  });

  final String? file;
  final String label;
  final String missingText;

  /// Portrait, like the photos.
  static const aspectRatio = 3 / 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = this.file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: Gap.xs),
        AspectRatio(
          aspectRatio: aspectRatio,
          child: file == null
              ? ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.sm),
                      child: Text(
                        missingText,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                )
              : Image.file(File(file), fit: BoxFit.cover),
        ),
      ],
    );
  }
}

/// [photos] two to a row.
class PhotoRows extends StatelessWidget {
  const PhotoRows(this.photos, {super.key});

  final List<Widget> photos;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < photos.length; i += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: photos[i]),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: i + 1 < photos.length
                    ? photos[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
    ],
  );
}
