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
          _Heading(group: g, first: g == groups.first),
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
              // Indented under its heading, and a step larger: the ward is
              // the thing being chosen, the constituency is only where to
              // look for it.
              child: Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Text(
                  '${context.tr('Ward')} $w',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.1,
                    fontWeight: _itemValue(g, w) == selected
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: _itemValue(g, w) == selected
                        ? NkColors.refBlue
                        : NkColors.slate800,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// The constituency band above its wards.
///
/// Heading and ward used to be 11/w800 and 12.5/w600 on the same background,
/// a difference too small to read as two levels — the list looked like one
/// long run of similar rows. The band, the tint and the indent under it are
/// what separate them now, not a point of type size.
class _Heading extends StatelessWidget {
  const _Heading({required this.group, required this.first});

  final WardGroup group;

  /// No rule above the first band — it would sit against the menu's own edge.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final unmapped = group.isUnmapped;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: first ? 0 : 6),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      decoration: BoxDecoration(
        color: unmapped ? const Color(0xFFFFF1F2) : NkColors.slate50,
        border: Border(
          top: first
              ? BorderSide.none
              : const BorderSide(color: NkColors.slate100),
          bottom: const BorderSide(color: NkColors.slate100),
        ),
      ),
      child: Text(
        // trAC keeps the number and translates only the name.
        unmapped ? context.tr(group.label) : context.trAC(group.label),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: unmapped ? NkColors.rose600 : NkColors.slate500,
        ),
      ),
    );
  }
}
