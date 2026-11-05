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
import '../../../domain/models/corporation.dart';
import '../../../domain/models/issue.dart';
import '../../../domain/models/locate_result.dart';
import '../../../domain/status_meta.dart';
import '../../../domain/ticket.dart';
import '../../shared/status_chip.dart';

/// Gentle desaturate + LIFT matrix for the basemap.
///
/// Built from the luma weights (0.2126 / 0.7152 / 0.0722) at saturation 0.72:
/// row = (1 - s) * luma + s * identity, which is only a light pull away from
/// the tiles' own colour.
///
/// It started at 0.18 with a +16/+12/+6 lift, which flattened parks, water and
/// arterials into one putty tone — the map read as a grey placeholder. 0.40
/// brought them back but still looked washed. At 0.72 the greens are green and
/// the arterials are properly yellow, and the brightness lift is what keeps
/// the whole thing light enough to sit UNDER the pins, the ward boundary and
/// the white sheet without competing with them. Going further is full-strength
/// OSM, which does compete.
///
/// The lift is deliberately modest (+13/+11/+6, down from +22/+20/+14): every
/// point of it is added to the street NAMES as well as the paper they sit on,
/// so a heavy lift buys brightness by washing the labels out. Colour carries
/// the brightness now; the offsets only take the grey out of the paper.
const List<double> _kPaleTileMatrix = <double>[
  0.7795, 0.2003, 0.0202, 0, 13, //
  0.0595, 0.9203, 0.0202, 0, 11, //
  0.0595, 0.2003, 0.7402, 0, 6, //
  0, 0, 0, 1, 0, //
];

/// The grievance map card — OSM tiles + the live corporation's boundaries + status pins,
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
    this.showSearch = true,
    this.showControls = true,
    this.paleTiles = false,
    this.lockBounds,
    this.lockPadding = EdgeInsets.zero,
    this.lockMinZoom = 12,
    this.citizenPins = false,
    this.onInteract,
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

  /// Show the inline search bar. The citizen home hides it — search lives in
  /// the floating app bar and opens a full-screen overlay instead.
  final bool showSearch;

  /// Show the zoom +/- and locate buttons.
  final bool showControls;

  /// Desaturate + blue-tint the basemap tiles for the pale reference look.
  final bool paleTiles;

  /// When set, the map is LOCKED to this boundary: it opens fitted to it and
  /// the camera can never be dragged or zoomed so its edges leave these bounds
  /// (flutter_map's [CameraConstraint.contain]). Panning + zoom stay live
  /// inside it. Null → the map roams freely (coordinator + pre-ward citizen).
  /// Fired the moment the user starts moving the map themselves (a pan, a
  /// pinch, a double-tap zoom) — never for a programmatic recenter or the
  /// opening camera fit. The home screens use it to get the bottom sheet out
  /// of the way so the map is actually usable.
  final VoidCallback? onInteract;

  final LatLngBounds? lockBounds;

  /// Padding applied when fitting [lockBounds], so the boundary lands in the
  /// visible band above the bottom sheet rather than dead-centre of the screen.
  final EdgeInsets lockPadding;

  /// Zoom floor while locked — the level at which the whole ward fills the
  /// visible band. Zooming out below this is blocked so the user can't reveal
  /// neighbouring wards. Computed by the caller from the ward span + viewport.
  final double lockMinZoom;

  /// Citizen palette: pins use only the three statuses the home filter pills
  /// expose (pending / in-progress / resolved) and anything else — notably
  /// FALSE petitions — is not plotted at all. The coordinator map keeps the
  /// full operational palette.
  final bool citizenPins;

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
    // While locked the map uses its own internal controller (so a ward change
    // rebuilds it fitted + constrained without tripping flutter_map's
    // options-change assert) — the external [_map] is not attached, so never
    // drive it here. Recenter only in the free-roaming (unlocked) mode.
    if (widget.lockBounds == null &&
        _mapReady &&
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
            // The selected ward: a navy edge heavy enough to read over a
            // coloured basemap, and a LIGHTER fill than before — the fill is
            // there to say "this one", not to grey out the street names
            // inside it. Every other ward drops back further than it used to,
            // so the selected polygon is unmistakably the subject.
            color: isHi
                ? NkColors.brand.withValues(alpha: 0.14)
                : base.withValues(alpha: 0.04),
            borderColor: isHi
                ? NkColors.brand
                : base.withValues(alpha: 0.28),
            borderStrokeWidth: isHi ? 3.2 : 0.6,
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
            borderColor: c.withValues(alpha: 0.95),
            borderStrokeWidth: 2.6,
          ),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.center ?? kDefaultCorporationCenter;
    final filtered = _filtered;
    final hasQuery = _query.text.trim().isNotEmpty;

    final lock = widget.lockBounds;
    final locked = lock != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              // Locked mode rebuilds a FRESH map (new key → its own internal
              // controller) whenever the ward changes, so it starts already
              // fitted + constrained. Free mode reuses [_map] and never
              // recreates, so GPS drift just recenters.
              key: ValueKey(
                  locked ? 'map-lock-${widget.currentWard}' : 'map-free'),
              mapController: locked ? null : _map,
              options: MapOptions(
                // Start inside the boundary at a valid zoom so the constraint
                // is satisfied from frame one (the fit below refines it).
                initialCenter: locked ? lock.center : center,
                initialZoom: locked ? widget.lockMinZoom : 15,
                // [minZoom] caps zoom-OUT at "the whole ward fills the visible
                // band" — you can't pull back to reveal neighbouring wards.
                minZoom: locked ? widget.lockMinZoom : 0,
                maxZoom: locked ? 19 : double.infinity,
                // Open showing the whole ward, biased up into the band left
                // visible above the sheet.
                initialCameraFit: locked
                    ? CameraFit.bounds(
                        bounds: lock,
                        padding: widget.lockPadding,
                      )
                    : null,
                // Keep the camera CENTRE inside the ward: you can pan around it
                // and zoom in freely, but never drift the map off the ward.
                // (containCenter rather than contain so gestures stay live —
                // contain would freeze the map once the padded full-screen view
                // exceeds the bounds.)
                cameraConstraint: locked
                    ? CameraConstraint.containCenter(bounds: lock)
                    : const CameraConstraint.unconstrained(),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom |
                      InteractiveFlag.drag |
                      InteractiveFlag.doubleTapZoom,
                ),
                onMapReady: () => _mapReady = true,
                onTap: (_, __) => widget.onSelect(null),
                // hasGesture is the whole point: a recenter after a GPS fix,
                // or the initial fit to the ward, must NOT read as the user
                // reaching for the map.
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture) widget.onInteract?.call();
                },
              ),
              children: [
                if (widget.paleTiles)
                  ColorFiltered(
                    colorFilter: const ColorFilter.matrix(_kPaleTileMatrix),
                    child: TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.nammakural.app',
                    ),
                  )
                else
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
                      // Citizen map: statuses outside the three filter pills
                      // (FALSE petitions, verification-pending) yield no colour
                      // and are skipped entirely.
                      if (!widget.citizenPins ||
                          citizenPinColor(issue.status) != null)
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
                              color: widget.citizenPins
                                  ? citizenPinColor(issue.status)
                                  : null,
                            ),
                          ),
                        ),
                  ],
                ),
              ],
            ),
          ),

          // ── Search bar + results dropdown ──
          if (widget.showSearch)
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
              child: const MapStatusLegend(),
            ),

          // ── Zoom controls ──
          if (widget.showControls)
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
          if (widget.onJumpEgmore != null && widget.showControls)
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
  const _StatusPin({
    required this.status,
    required this.highlight,
    this.color,
  });

  final String status;
  final bool highlight;

  /// Overrides the operational palette — the citizen map passes the three-way
  /// pending/in-progress/resolved colour here.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(26, 34),
      painter: _PinPainter(
        color: color ?? statusMeta(status).pin,
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
            context.tr('Outside corporation limits'),
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
                  compactAC(ac),
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


/// The status-dot legend drawn over the map. Extracted from [MapCard] so a
/// screen that needs to drive its opacity (the coordinator home fades it as
/// its sheet rises) can position it itself, without every opacity tick
/// rebuilding the whole map. Content and colours are unchanged.
class MapStatusLegend extends StatelessWidget {
  const MapStatusLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}
