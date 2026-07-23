import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Port of lib/departments.js — display metadata for the 7 municipal
/// departments grievances route to. Keys MUST match the canonical names the
/// backend Gemini router returns.
class DepartmentMeta {
  const DepartmentMeta({
    required this.short,
    required this.slaDays,
    required this.phone,
    required this.chipBg,
    required this.chipFg,
  });

  final String short;
  final int slaDays;
  final String phone;
  final Color chipBg;
  final Color chipFg;
}

const Map<String, DepartmentMeta> kDepartments = {
  'Solid Waste Management Department': DepartmentMeta(
    short: 'Solid Waste', slaDays: 2, phone: '+91 90031 00001',
    chipBg: NkColors.emerald50, chipFg: NkColors.emerald700),
  'Electrical Department': DepartmentMeta(
    short: 'Electrical', slaDays: 3, phone: '+91 90031 00002',
    chipBg: Color(0xFFFEFCE8), chipFg: Color(0xFFA16207)),
  'Works & Roads Department': DepartmentMeta(
    short: 'Works & Roads', slaDays: 14, phone: '+91 90031 00003',
    chipBg: Color(0xFFF5F5F4), chipFg: Color(0xFF44403C)),
  'Storm Water Drain Department': DepartmentMeta(
    short: 'Storm Water', slaDays: 7, phone: '+91 90031 00004',
    chipBg: Color(0xFFECFEFF), chipFg: Color(0xFF0E7490)),
  'Public Health Department': DepartmentMeta(
    short: 'Public Health', slaDays: 3, phone: '+91 90031 00005',
    chipBg: NkColors.rose50, chipFg: NkColors.rose700),
  'Parks & Playfields Department': DepartmentMeta(
    short: 'Parks & Playfields', slaDays: 10, phone: '+91 90031 00006',
    chipBg: Color(0xFFF7FEE7), chipFg: Color(0xFF4D7C0F)),
  'Allied Utilities': DepartmentMeta(
    short: 'Allied Utilities', slaDays: 5, phone: '+91 90031 00007',
    chipBg: Color(0xFFEEF2FF), chipFg: Color(0xFF4338CA)),
};

const _fallback = DepartmentMeta(
  short: 'Unassigned', slaDays: 7, phone: '+91 90031 00000',
  chipBg: NkColors.slate100, chipFg: NkColors.slate600);

DepartmentMeta departmentMeta(String? name) => kDepartments[name] ?? _fallback;

/// SLA deadline = created_at + the department's SLA window.
DateTime slaDeadline(DateTime? createdAt, String? department) {
  final base = createdAt ?? DateTime.now();
  return base.add(Duration(days: departmentMeta(department).slaDays));
}

/// Reasons offered in the "Mark as False Petition" sheet.
const kFalseReasons = [
  'Duplicate of an existing grievance',
  'Fabricated / not a real issue',
  'Personal dispute, not a public grievance',
  'Outside constituency jurisdiction',
  'Malicious / harassing report',
  'Other',
];

/// Target-audience chips in the post/poll composer.
const kAudiences = [
  'Ward Residents', 'Constituency Residents', 'All Chennai',
  'Youth (18-35)', 'Senior Citizens', "Women's Groups",
  'Local Businesses', 'Media & Press',
];
