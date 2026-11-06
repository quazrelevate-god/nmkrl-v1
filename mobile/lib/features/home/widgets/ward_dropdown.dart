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
    final selected = _selected(groups);

    // A [MenuAnchor], not a DropdownButton.
    //
    // Material's DropdownButton positions its menu so the SELECTED item lands
    // on the button — which is why it opened upward and downward at once,
    // covering the app bar and the stories above the control. With sixty-odd
    // wards and a selection somewhere in the middle, that is most of the
    // screen. A menu anchored under its trigger is what a dropdown is
    // supposed to do, and it leaves everything above the control alone.
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        // Wide enough for "18 · Chepauk-Thiruvallikeni", and capped so the
        // list scrolls rather than running off the bottom of the screen.
        minimumSize: const WidgetStatePropertyAll(Size(250, 0)),
        maximumSize: const WidgetStatePropertyAll(Size(250, 420)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      builder: (context, controller, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                ward == null
                    ? context.tr('Ward')
                    : '${context.tr('Ward')} $ward',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ward == null ? NkColors.slate500 : NkColors.slate700,
                ),
              ),
            ),
            const Icon(Icons.expand_more, size: 14, color: NkColors.slate500),
          ],
        ),
      ),
      menuChildren: [
        for (final g in groups) ...[
          // Headings are not selectable, so they are plain widgets rather
          // than disabled buttons — a disabled MenuItemButton still takes a
          // focus stop on the way down the list.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: _Heading(group: g),
          ),
          for (final w in g.wards)
            MenuItemButton(
              onPressed: () => onChanged(w),
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(
                  _itemValue(g, w) == selected
                      ? NkColors.brand50
                      : Colors.transparent,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  '${context.tr('Ward')} $w',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: _itemValue(g, w) == selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: NkColors.slate700,
                  ),
                ),
              ),
            ),
        ],
      ],
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
