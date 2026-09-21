import 'package:flutter/material.dart';

import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../../../domain/constituencies.dart';

/// One dropdown listing wards under their Assembly Constituency headings —
/// the grouping the admin dashboard uses — while the closed button shows only
/// "Ward 108".
///
/// Item values are `constituency|ward`, never the bare ward: a ward on a
/// constituency boundary appears under both constituencies, and a
/// DropdownButton throws if two items share a value. Picking either listing
/// reports the same ward to [onChanged].
class ConstituencyWardDropdown extends StatelessWidget {
  const ConstituencyWardDropdown({
    super.key,
    required this.wards,
    required this.ward,
    required this.onChanged,
  });

  /// Every ward that can be chosen (those with a loaded boundary).
  final List<String> wards;

  /// The chosen ward, or null.
  final String? ward;
  final ValueChanged<String> onChanged;

  static String _itemValue(WardGroup g, String ward) => '${g.key}|$ward';

  /// The value of the chosen ward's first listing — both listings of a
  /// boundary ward pick the same ward.
  String? _selected(List<WardGroup> groups) {
    if (ward == null) return null;
    for (final g in groups) {
      if (g.wards.contains(ward)) return _itemValue(g, ward!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupWardsByConstituency(wards);
    Text wardLabel(String w) =>
        Text('${context.tr('Ward')} $w', overflow: TextOverflow.ellipsis);

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selected(groups),
        isDense: true,
        isExpanded: true,
        // Wide enough for "18 · Chepauk-Thiruvallikeni"; the closed button is
        // sized by its parent and stays compact.
        menuWidth: 250,
        menuMaxHeight: 420,
        hint: Text(context.tr('Ward'),
            style: const TextStyle(fontSize: 12, color: NkColors.slate500)),
        icon: const Icon(Icons.expand_more, size: 14, color: NkColors.slate500),
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: NkColors.slate700),
        borderRadius: BorderRadius.circular(12),
        // One entry per item, in the same order as [items]. Headings can never
        // be the selected value, so they render nothing here.
        selectedItemBuilder: (context) => [
          for (final g in groups) ...[
            const SizedBox.shrink(),
            for (final w in g.wards) wardLabel(w),
          ],
        ],
        items: [
          for (final g in groups) ...[
            DropdownMenuItem<String>(
              value: '#${g.key}',
              enabled: false,
              child: _Heading(group: g),
            ),
            for (final w in g.wards)
              DropdownMenuItem<String>(
                value: _itemValue(g, w),
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: wardLabel(w),
                ),
              ),
          ],
        ],
        onChanged: (value) {
          if (value == null || !value.contains('|')) return;
          onChanged(value.split('|').last);
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.group});

  final WardGroup group;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          group.isUnmapped ? context.tr(group.label) : group.label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: group.isUnmapped ? NkColors.rose600 : NkColors.refBlue,
          ),
        ),
      );
}
