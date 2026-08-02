import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Port of lib/status.js — the single source of truth mapping backend status
/// enums to user-facing labels + colors. Keeps badges/pins consistent.
class StatusMeta {
  const StatusMeta({
    required this.label,
    required this.badgeBg,
    required this.badgeFg,
    required this.badgeBorder,
    required this.pin,
    required this.open,
  });

  final String label;
  final Color badgeBg;
  final Color badgeFg;
  final Color badgeBorder;
  final Color pin;
  final bool open;
}

const Map<String, StatusMeta> kStatusMeta = {
  'SUBMITTED': StatusMeta(
    label: 'Pending Verification',
    badgeBg: NkColors.slate100,
    badgeFg: NkColors.slate600,
    badgeBorder: NkColors.slate200,
    pin: Color(0xFF64748B),
    open: true,
  ),
  'ACTIVE': StatusMeta(
    label: 'Assigned',
    badgeBg: NkColors.brand100,
    badgeFg: NkColors.brand700,
    badgeBorder: NkColors.brand200,
    pin: NkColors.brand,
    open: true,
  ),
  'FORWARDED': StatusMeta(
    // Coordinator's "Dept. Transfer" → combined "In Progress" working state.
    label: 'In Progress',
    badgeBg: Color(0xFFE2EAF7),
    badgeFg: NkColors.refBlue,
    badgeBorder: Color(0xFFCBD9F0),
    pin: NkColors.refBlue,
    open: true,
  ),
  'IN_PROGRESS': StatusMeta(
    label: 'In Progress',
    badgeBg: Color(0xFFE2EAF7),
    badgeFg: NkColors.refBlue,
    badgeBorder: Color(0xFFCBD9F0),
    pin: NkColors.refBlue,
    open: true,
  ),
  'PENDING_VERIFICATION': StatusMeta(
    label: 'Verification Pending',
    badgeBg: NkColors.amber50,
    badgeFg: NkColors.amber700,
    badgeBorder: NkColors.amber100,
    pin: Color(0xFFC99A3A),
    open: true,
  ),
  'CLOSED': StatusMeta(
    label: 'Resolved',
    badgeBg: NkColors.emerald50,
    badgeFg: NkColors.emerald700,
    badgeBorder: NkColors.emerald100,
    pin: Color(0xFF0D9488),
    open: false,
  ),
  'FALSE': StatusMeta(
    label: 'Marked as false petition',
    badgeBg: NkColors.rose50,
    badgeFg: NkColors.rose700,
    badgeBorder: NkColors.rose100,
    pin: Color(0xFFE11D48),
    open: false,
  ),
};

StatusMeta statusMeta(String? status) =>
    kStatusMeta[status] ?? kStatusMeta['ACTIVE']!;

/// Lifecycle tracker steps (merged Inspection + Repair → "In Progress").
const kLifecycle = [
  'Submitted',
  'Pending Verification',
  'Assigned',
  'In Progress',
  'Verification',
  'Completed',
];

/// Port of the home page's progressIndex(status).
int progressIndex(String? status) => switch (status) {
      'SUBMITTED' => 1,
      'ACTIVE' => 2,
      'FORWARDED' => 3,
      'IN_PROGRESS' => 3,
      'PENDING_VERIFICATION' => 4,
      'CLOSED' => 5,
      'FALSE' => -1,
      _ => 0,
    };
