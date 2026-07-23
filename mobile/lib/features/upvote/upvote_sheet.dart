import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/glass.dart';
import '../../core/theme.dart';
import '../../domain/daily_limit.dart';
import '../../domain/models/issue.dart';
import '../../state/providers.dart';
import '../report/widgets/success_overlay.dart';
import '../report/widgets/swipe_to_confirm.dart';

const _kDailyMax = 5;

/// "Support this grievance" sheet (port of UpvoteModal.js): grievance summary,
/// 5-supports/day fair-use banner and an emerald swipe-to-confirm, ending in
/// the full-screen success overlay.
class UpvoteSheet extends ConsumerStatefulWidget {
  const UpvoteSheet({super.key, required this.issue, required this.onConfirm});

  final Issue issue;

  /// Performs the actual upvote; throws on failure (error shown inline).
  final Future<void> Function() onConfirm;

  static Future<void> open(
    BuildContext context, {
    required Issue issue,
    required Future<void> Function() onConfirm,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.45),
      builder: (_) => UpvoteSheet(issue: issue, onConfirm: onConfirm),
    );
  }

  @override
  ConsumerState<UpvoteSheet> createState() => _UpvoteSheetState();
}

class _UpvoteSheetState extends ConsumerState<UpvoteSheet> {
  bool _busy = false;
  String? _error;
  int _resetToken = 0;
  late DailyState _limit;

  @override
  void initState() {
    super.initState();
    _limit = ref.read(dailyLimitProvider).state(kSupportLimitKey, _kDailyMax);
  }

  Future<void> _confirm() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await widget.onConfirm();
      await ref.read(dailyLimitProvider).consume(kSupportLimitKey, _kDailyMax);
      if (!mounted) return;
      Navigator.of(context).pop();
      await SuccessOverlay.show(
        context,
        title: 'Support Added',
        message:
            'Thanks for amplifying this grievance. The coordinator sees higher-supported issues first.',
      );
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
        _resetToken++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: GlassContainer(
        variant: Glass.strong,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: NkColors.slate900.withValues(alpha: 0.55),
            blurRadius: 80,
            offset: const Offset(0, 30),
            spreadRadius: -20,
          ),
        ],
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: NkColors.slate300.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Support this grievance',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: NkColors.slate900,
                        ),
                      ),
                      Text(
                        'Add your voice — no sign-in needed',
                        style: TextStyle(
                            fontSize: 12, color: NkColors.slate500),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close,
                      size: 18, color: NkColors.slate400),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Grievance summary
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: NkColors.slate50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NkColors.slate100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.issue.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: NkColors.slate800,
                    ),
                  ),
                  if (widget.issue.areaName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.issue.areaName!,
                      style: const TextStyle(
                          fontSize: 12, color: NkColors.slate500),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.thumb_up_outlined,
                          size: 12, color: NkColors.brand),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.issue.upvotes} current supports',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: NkColors.brand,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Fair-use banner
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: NkColors.emerald50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NkColors.emerald100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user,
                      size: 16, color: NkColors.emerald700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: '${_limit.remaining}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                          color: NkColors.emerald700,
                        ),
                        children: [
                          TextSpan(
                            text:
                                ' of $_kDailyMax supports left today · fair-use limit',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: NkColors.rose50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style:
                      const TextStyle(fontSize: 12, color: NkColors.rose600),
                ),
              ),
            ],

            const SizedBox(height: 16),
            SwipeToConfirm(
              label: 'Swipe to support',
              busyLabel: 'Adding your support…',
              emerald: true,
              busy: _busy,
              resetToken: _resetToken,
              onConfirm: _confirm,
            ),
          ],
        ),
      ),
    );
  }
}
