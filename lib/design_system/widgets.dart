import 'package:flutter/material.dart';

import 'theme.dart';

/// The approved Sideband icon (brand/icon-192.png). Decorative.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset('brand/icon-192.png',
            width: size, height: size, excludeFromSemantics: true),
      );
}

enum Tone { neutral, accent, warning, danger }

/// Small rounded status label. Colour is never the only signal: the text
/// always states the status.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label,
      {super.key, this.tone = Tone.neutral, this.icon});
  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg) = switch (tone) {
      Tone.neutral => (s.surfaceContainerHigh, s.onSurfaceVariant),
      Tone.accent => (s.primaryContainer, s.onPrimaryContainer),
      Tone.warning => (
          dark ? const Color(0xFF3A2E10) : const Color(0xFFFBEBC4),
          dark ? const Color(0xFFFFD27A) : const Color(0xFF6B4500)
        ),
      Tone.danger => (s.error.withValues(alpha: 0.14), s.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(label,
              style: TextStyle(
                  color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// Uppercase section label used above cards.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary)),
      );
}

/// Informational callout (e.g. demo mode, disclosures).
class Notice extends StatelessWidget {
  const Notice(
      {super.key, required this.child, this.icon = Icons.info_outline});
  final Widget child;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: s.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: SidebandColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: s.primary),
        const SizedBox(width: 10),
        Expanded(
            child: DefaultTextStyle.merge(
                style: TextStyle(color: s.onSurface, height: 1.35),
                child: child)),
      ]),
    );
  }
}

/// Tabular-figure amount for money values.
class AmountText extends StatelessWidget {
  const AmountText(this.value, {super.key, this.size = 32, this.unit});
  final String value;
  final double size;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(children: [
        TextSpan(
            text: value,
            style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                fontFeatures: const [FontFeature.tabularFigures()])),
        if (unit != null)
          TextSpan(
              text: '  $unit',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: s.onSurfaceVariant)),
      ]),
    );
  }
}
