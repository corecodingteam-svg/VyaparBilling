import 'package:flutter/material.dart';

import '../../shared/theme.dart';
import 'key_combo.dart';

/// A shortcut drawn as keys: `[Ctrl] + [N]`. For the settings, the Playbook and the shortcut overlay.
class KeyChip extends StatelessWidget {
  const KeyChip(this.parts, {super.key, this.dense = false});

  /// A combination's keys in order, e.g. `['Ctrl', 'N']`.
  final List<String> parts;
  final bool dense;

  factory KeyChip.combo(KeyCombo c, {bool dense = false}) => KeyChip(c.parts, dense: dense);

  /// Fixed keys written as text, e.g. "Shift + Tab" or "↑ ↓".
  factory KeyChip.text(String keys, {bool dense = false}) => KeyChip(keys.split(' + '), dense: dense);

  @override
  Widget build(BuildContext context) => Semantics(
        label: parts.join(' plus '),
        child: ExcludeSemantics(
          child: Wrap(
            spacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < parts.length; i++) ...[
                if (i > 0) const Text('+', style: TextStyle(color: AppColors.textMuted, fontSize: AppFont.small)),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: dense ? AppSpace.xs + 2 : AppSpace.sm, vertical: dense ? 1 : AppSpace.xs),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: AppRadius.smAll,
                    border: Border.all(color: AppColors.borderStrong),
                  ),
                  child: Text(parts[i], style: TextStyle(fontSize: dense ? AppFont.caption : AppFont.small, fontWeight: FontWeight.w600, color: AppColors.textBody)),
                ),
              ],
            ],
          ),
        ),
      );
}
