import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
// latlong2 exports its own Path class — hide it so dart:ui's Path (used by
// the pin painter) wins.
import 'package:latlong2/latlong.dart' hide Path;

import '../../../core/theme.dart';
import '../../../core/i18n.dart';
import '../../../domain/constituencies.dart';
import '../../../domain/models/boundary_data.dart';
import '../../../domain/models/issue.dart';
import '../../../domain/models/locate_result.dart';
import '../../../domain/status_meta.dart';
import '../../../domain/ticket.dart';
import '../../shared/status_chip.dart';

/// The grievance map card — OSM tiles + real GCC boundaries + status pins,
/// with the search bar, zone/ward chip, legend, Egmore demo jump and the
/// selected-issue bottom sheet floating inside the rounded card
/// (port of the map section of the web home + BoundaryLayer + MapView).
class MapCard extends StatefulWidget {
  const MapCard({
    super.key,
    required this.center,
    required this.issues,
    required this.selected,
    required this.onSelect,
    required this.boundaries,
    required this.currentWard,
    this.locate,
    this.locating = false,
    this.showLocateChip = true,
    this.egmoreActive = false,
    this.onJumpEgmore,
    this.onUpvote,
    this.searchHint = 'Search ticket no. or grievance nearby',
    this.borderRadius = 26,
    this.showLegend = true,
    this.searchTop = 8,
    this.searchHorizontal = 12,
    this.controlsBottomInset = 0,
  });

  final LatLng? center;
  final List<Issue> issues;
  final Issue? selected;
  final ValueChanged<Issue?> onSelect;
  final BoundaryData? boundaries;
  final int? currentWard;
  final LocateResult? locate;
  final bool locating;

  /// Coordinator map hides the citizen zone-detector chip.
  final bool showLocateChip;
  final bool egmoreActive;

  /// When null the demo Egmore-jump button is hidden (coordinator map).
  final VoidCallback? onJumpEgmore;

  /// When null the selected-issue sheet hides its Upvote button.
  final ValueChanged<Issue>? onUpvote;
  final String searchHint;

  /// 0 makes the map full-bleed (citizen home); the coordinator keeps the card.
  final double borderRadius;

  /// The citizen home replaces the legend with status filter pills.
  final bool showLegend;

  /// Pushes the floating search bar down past an overlaying app bar.
  final double searchTop;
  final double searchHorizontal;

  /// Lifts the zoom/legend/demo controls clear of an overlaying bottom sheet.
  final double controlsBottomInset;

  @override
  State<MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<MapCard> {
  final _map = MapController();
  final _query = TextEditingController();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(MapCard old) {
    super.didUpdateWidget(old);
    // Recenter only when the effective location actually changes.
    if (_mapReady &&
        widget.center != null &&
        (old.center?.latitude != widget.center!.latitude ||
            old.center?.longitude != widget.center!.longitude)) {
      _map.move(widget.center!, _map.camera.zoom);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Stable-ish distinct colour per zone (port of zoneColor()).
  static Color _zoneColor(String? zone) {
    if (zone == null || zone.isEmpty) return NkColors.slate400;
    var h = 0;
    for (final code in zone.codeUnits) {
      h = (h * 31 + code) % 360;
    }
    return HSLColor.fromAHSL(1, h.toDouble(), 0.65, 0.45).toColor();
  }

  List<Issue> get _filtered {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.issues;
    return widget.issues
        .where((i) =>
            ticketNumber(i.id).toLowerCase().contains(q) ||
            i.title.toLowerCase().contains(q) ||
            (i.areaName ?? '').toLowerCase().contains(q))
        .toList();
  }

  List<Polygon> _wardPolygons() {
    final b = widget.boundaries;
    if (b == null) return const [];
    final hw = widget.currentWard?.toString();
    final out = <Polygon>[];
    for (final f in b.wards) {
      final isHi = hw != null && f.ward == hw;
      final base = _zoneColor(f.zone);
      for (final part in f.parts) {
        if (part.isEmpty) continue;
        out.add(
          Polygon(
            points: part.first,
            holePointsList:
                part.length > 1 ? part.sublist(1) : null,
            color: isHi
                ? NkColors.brand.withValues(alpha: 0.22)
                : base.withValues(alpha: 0.07),
            borderColor: isHi
                ? NkColors.brand
                : base.withValues(alpha: 0.5),
            borderStrokeWidth: isHi ? 2.5 : 0.7,
          ),
        );
      }
    }
    return out;
  }

  List<Polygon> _zonePolygons() {
    final b = widget.boundaries;
    if (b == null) return const [];
    final out = <Polygon>[];
    for (final f in b.zones) {
      final c = _zoneColor(f.zone);
      for (final part in f.parts) {
        if (part.isEmpty) continue;
        out.add(
          Polygon(
            points: part.first,
            color: Colors.transparent,
            borderColor: c.withValues(alpha: 0.8),
            borderStrokeWidth: 2,
          ),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.center ?? const LatLng(13.0827, 80.2081);
    final filtered = _filtered;
    final hasQuery = _query.text.trim().isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom |
                      InteractiveFlag.drag |
                      InteractiveFlag.doubleTapZoom,
                ),
                onMapReady: () => _mapReady = true,
                onTap: (_, __) => widget.onSelect(null),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.nammakural.app',
                ),
                PolygonLayer(polygons: [..._wardPolygons(), ..._zonePolygons()]),
                // "You are here" dot
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: center,
                      radius: 6,
                      color: NkColors.brand,
                      borderColor: Colors.white,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final issue in filtered)
                      Marker(
                        point: LatLng(issue.latitude, issue.longitude),
                        width: 26,
                        height: 34,
                        alignment: Alignment.topCenter,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            widget.onSelect(issue);
                          },
                          child: _StatusPin(
                            status: issue.status,
                            highlight: issue.id == widget.selected?.id,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── Search bar + results dropdown ──
          Positioned(
            left: widget.searchHorizontal,
            right: widget.searchHorizontal,
            top: widget.searchTop,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NkColors.slate200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search,
                          size: 15, color: NkColors.slate400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _query,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: widget.searchHint,
                            hintStyle: const TextStyle(
                                fontSize: 12, color: NkColors.slate400),
                          ),
                        ),
                      ),
                      if (hasQuery)
                        GestureDetector(
                          onTap: () => _query.clear(),
                          child: const Icon(Icons.close,
                              size: 14, color: NkColors.slate400),
                        ),
                    ],
                  ),
                ),
                if (hasQuery)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 160),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NkColors.slate200),
                    ),
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'No matching grievances nearby.',
                              style: TextStyle(
                                  fontSize: 12, color: NkColors.slate400),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, color: NkColors.slate100),
                            itemBuilder: (context, i) {
                              final issue = filtered[i];
                              return InkWell(
                                onTap: () {
                                  widget.onSelect(issue);
                                  _query.clear();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      Text(
                                        (issue.ticketNo ?? ticketNumber(issue.id)),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'monospace',
                                          color: NkColors.slate500,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          issue.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: NkColors.slate800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      StatusChip(status: issue.status),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
              ],
            ),
          ),

          // ── Zone/ward detector chip (hidden while searching) ──
          if (!hasQuery && widget.showLocateChip)
            Positioned(
              right: 12,
              top: widget.searchTop + 46,
              child: _LocateChip(
                  locate: widget.locate, locating: widget.locating),
            ),

          // ── Status legend ──
          if (widget.showLegend)
          Positioned(
            left: 8,
            bottom: 8 + widget.controlsBottomInset,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NkColors.slate200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in kStatusMeta.entries)
                    if (entry.key != 'SUBMITTED' && entry.key != 'FORWARDED')
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: 8,
                              width: 8,
                              decoration: BoxDecoration(
                                color: entry.value.pin,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              context.tr(entry.value.label),
                              style: const TextStyle(
                                  fontSize: 9, color: NkColors.slate700),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),

          // ── Zoom controls ──
          Positioned(
            right: 8,
            bottom: 44 + widget.controlsBottomInset,
            child: Column(
              children: [
                for (final (icon, dz) in [(Icons.add, 1.0), (Icons.remove, -1.0)])
                  GestureDetector(
                    onTap: () => _map.move(
                        _map.camera.center, _map.camera.zoom + dz),
                    child: Container(
                      height: 28,
                      width: 28,
                      margin: const EdgeInsets.only(top: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: NkColors.slate200),
                      ),
                      child: Icon(icon, size: 15, color: NkColors.slate600),
                    ),
                  ),
              ],
            ),
          ),

          // ── Egmore demo jump (citizen only) ──
          if (widget.onJumpEgmore != null)
          Positioned(
            right: 8,
            bottom: 8 + widget.controlsBottomInset,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onJumpEgmore!();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 28,
                width: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.egmoreActive
                      ? NkColors.brand
                      : Colors.white.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.account_balance,
                  size: 12,
                  color: widget.egmoreActive
                      ? Colors.white
                      : NkColors.slate400,
                ),
              ),
            ),
          ),

          // Tapping a pin no longer opens a separate sheet — the parent
          // highlights + brings forward the matching grievance ribbon in the
          // list below (see onSelect handling in the home screens). #6
        ],
      ),
    );
  }
}

/// Colored teardrop pin (port of the MapView divIcon SVG).
class _StatusPin extends StatelessWidget {
  const _StatusPin({required this.status, required this.highlight});

  final String status;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(26, 34),
      painter: _PinPainter(
        color: statusMeta(status).pin,
        highlight: highlight,
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  _PinPainter({required this.color, required this.highlight});

  final Color color;
  final bool highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 26;
    final path = Path()
      ..moveTo(13 * s, 0)
      ..cubicTo(5.8 * s, 0, 0, 5.8 * s, 0, 13 * s)
      ..cubicTo(0, 22.2 * s, 13 * s, 34 * s, 13 * s, 34 * s)
      ..cubicTo(13 * s, 34 * s, 26 * s, 22.2 * s, 26 * s, 13 * s)
      ..cubicTo(26 * s, 5.8 * s, 20.2 * s, 0, 13 * s, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.78));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75 * s
        ..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      Offset(13 * s, 13 * s),
      5 * s,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    if (highlight) {
      canvas.drawCircle(
        Offset(13 * s, 13 * s),
        11 * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * s
          ..color = const Color(0xFFFACC15),
      );
    }
  }

  @override
  bool shouldRepaint(_PinPainter old) =>
      old.color != color || old.highlight != highlight;
}

/// Real GCC zone/ward chip (port of LocationDetector).
class _LocateChip extends StatelessWidget {
  const _LocateChip({required this.locate, required this.locating});

  final LocateResult? locate;
  final bool locating;

  @override
  Widget build(BuildContext context) {
    final loc = locate;
    Widget inner;
    if (loc == null || locating) {
      inner = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 10,
            width: 10,
            child: CircularProgressIndicator(
                strokeWidth: 1.6, color: NkColors.slate400),
          ),
          SizedBox(width: 6),
          Text(
            context.tr('Detecting zone…'),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: NkColors.slate500,
            ),
          ),
        ],
      );
    } else if (!loc.inside) {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr('Outside GCC limits'),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: NkColors.slate600),
          ),
          Text(
            context.tr('No ward boundary here'),
            style: TextStyle(fontSize: 9, color: NkColors.slate400),
          ),
        ],
      );
    } else {
      final ac = loc.constituencies.isEmpty ? null : loc.constituencies.first;
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.business, size: 11, color: NkColors.brand),
              const SizedBox(width: 3),
              Text(
                'Zone ${loc.zone}${loc.zoneName != null ? ' · ${titleCase(loc.zoneName!)}' : ''}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: NkColors.brand,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place, size: 9, color: NkColors.slate500),
              const SizedBox(width: 3),
              Text(
                'Ward ${loc.ward}',
                style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: NkColors.slate500),
              ),
            ],
          ),
          if (ac != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance,
                    size: 9, color: NkColors.slate500),
                const SizedBox(width: 3),
                Text(
                  shortAC(ac),
                  style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: NkColors.slate500),
                ),
              ],
            ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (locate?.inside ?? false)
              ? NkColors.brand.withValues(alpha: 0.2)
              : NkColors.slate200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
          ),
        ],
      ),
      child: inner,
    );
  }
}

