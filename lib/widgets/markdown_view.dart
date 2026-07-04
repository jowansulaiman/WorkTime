import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/theme_extensions.dart';

/// Schlanker, hausgemachter Markdown-Renderer fuer die In-App-Doku (Bereich
/// „Wissen"). **Kein** externes Paket — der Renderer unterstuetzt bewusst nur
/// die Teilmenge, die unsere Doku verwendet, dafuer aber vollstaendig
/// theme-integriert (Tokens, `appColors`, NotoSans, Dunkelmodus, Dynamic Type).
///
/// Unterstuetzt: `#`/`##`/`###`-Ueberschriften, Absaetze, `-`/`1.`-Listen,
/// Zaun-Codebloecke ```` ``` ````, Pipe-Tabellen, Zitate/Callouts
/// (`> [!TIP|NOTE|WARNING|IMPORTANT|CAUTION]`), Trennlinien `---` sowie inline
/// **fett**, *kursiv*, `code` und Links `[Text](url)`. Interne Verweise nutzen
/// das `article:<slug>`-Schema und rufen [onOpenArticle]; externe `http(s)`-
/// Links oeffnen den Browser.
class MarkdownView extends StatefulWidget {
  const MarkdownView({
    super.key,
    required this.data,
    this.onOpenArticle,
    this.selectable = false,
  });

  final String data;
  final void Function(String slug)? onOpenArticle;

  /// Absatz-/Ueberschriften-Text markierbar machen (Kopieren). Standard aus,
  /// da markierbarer Text mit Link-Recognizern teurer ist.
  final bool selectable;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  late List<_Block> _blocks;
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _blocks = _parseBlocks(widget.data);
  }

  @override
  void didUpdateWidget(covariant MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _blocks = _parseBlocks(widget.data);
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _handleLink(String href) async {
    if (href.startsWith('article:')) {
      widget.onOpenArticle?.call(href.substring('article:'.length));
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri == null) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Kein Browser verfuegbar (z. B. Test/Headless) — still ignorieren.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Recognizer bei jedem (seltenen) Rebuild neu aufbauen, alte freigeben.
    _disposeRecognizers();
    final theme = Theme.of(context);
    final spacing = context.spacing;
    final children = <Widget>[];
    for (var i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      if (i > 0) {
        children.add(SizedBox(height: _gapBefore(block, spacing)));
      }
      children.add(_renderBlock(context, theme, block));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  double _gapBefore(_Block block, AppSpacing spacing) {
    return switch (block) {
      _Heading(:final level) => level <= 1 ? spacing.lg : spacing.md,
      _Rule() => spacing.md,
      _ => spacing.s12,
    };
  }

  Widget _renderBlock(BuildContext context, ThemeData theme, _Block block) {
    switch (block) {
      case _Heading(:final level, :final spans):
        final style = switch (level) {
          1 => theme.textTheme.headlineSmall,
          2 => theme.textTheme.titleLarge,
          _ => theme.textTheme.titleMedium,
        };
        return Text.rich(
          _inlineSpan(context, theme, spans,
              style?.copyWith(fontWeight: FontWeight.w800) ?? const TextStyle()),
        );
      case _Paragraph(:final spans):
        final base = theme.textTheme.bodyLarge ?? const TextStyle();
        final span = _inlineSpan(context, theme, spans,
            base.copyWith(height: 1.5, color: theme.colorScheme.onSurface));
        return widget.selectable
            ? SelectableText.rich(span)
            : Text.rich(span);
      case _ListBlock(:final ordered, :final items):
        return _buildList(context, theme, ordered, items);
      case _Code(:final text):
        return _CodeBlock(text: text);
      case _Callout(:final kind, :final lines):
        return _buildCallout(context, theme, kind, lines);
      case _TableBlock(:final header, :final rows):
        return _buildTable(context, theme, header, rows);
      case _Rule():
        return Divider(color: theme.colorScheme.outlineVariant, height: 1);
    }
  }

  Widget _buildList(BuildContext context, ThemeData theme, bool ordered,
      List<List<_Inline>> items) {
    final spacing = context.spacing;
    final base = theme.textTheme.bodyLarge ?? const TextStyle();
    final markerStyle = base.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w700,
      fontFeatures: kTabularFigures,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : spacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: ordered ? 26 : 20,
                  child: Text(ordered ? '${i + 1}.' : '•', style: markerStyle),
                ),
                Expanded(
                  child: Text.rich(
                    _inlineSpan(context, theme, items[i],
                        base.copyWith(height: 1.45, color: theme.colorScheme.onSurface)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCallout(BuildContext context, ThemeData theme, String kind,
      List<List<_Inline>> lines) {
    final colors = theme.appColors;
    final spacing = context.spacing;
    final (Color bg, Color fg, Color accent, IconData icon) = switch (kind) {
      'TIP' => (colors.successContainer, colors.onSuccessContainer, colors.success, Icons.lightbulb_outline),
      'WARNING' || 'CAUTION' => (colors.warningContainer, colors.onWarningContainer, colors.warning, Icons.warning_amber_rounded),
      'IMPORTANT' => (colors.infoContainer, colors.onInfoContainer, colors.info, Icons.priority_high_rounded),
      'NOTE' => (colors.infoContainer, colors.onInfoContainer, colors.info, Icons.info_outline),
      _ => (
          theme.colorScheme.surfaceContainerHigh,
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.outline,
          Icons.format_quote_rounded
        ),
    };
    final base = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(color: fg, height: 1.45);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.s12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: context.iconSizes.sm, color: accent),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lines.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : spacing.xs),
                    child: Text.rich(_inlineSpan(context, theme, lines[i], base)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context, ThemeData theme,
      List<List<_Inline>> header, List<List<List<_Inline>>> rows) {
    final scheme = theme.colorScheme;
    final base = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(color: scheme.onSurface, height: 1.4);
    final headStyle = base.copyWith(fontWeight: FontWeight.w800);
    final border = TableBorder.all(color: scheme.outlineVariant, width: 1);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.sizeOf(context).width - 40,
        ),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: border,
          children: [
            TableRow(
              decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
              children: [
                for (final cell in header)
                  _tableCell(context, theme, cell, headStyle),
              ],
            ),
            for (final row in rows)
              TableRow(
                children: [
                  for (var c = 0; c < header.length; c++)
                    _tableCell(
                        context, theme, c < row.length ? row[c] : const [], base),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _tableCell(
      BuildContext context, ThemeData theme, List<_Inline> cell, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text.rich(_inlineSpan(context, theme, cell, style)),
    );
  }

  TextSpan _inlineSpan(BuildContext context, ThemeData theme,
      List<_Inline> nodes, TextStyle base) {
    final scheme = theme.colorScheme;
    final children = <InlineSpan>[];
    for (final node in nodes) {
      var style = base;
      if (node.bold) {
        style = style.copyWith(fontWeight: FontWeight.w700);
      }
      if (node.italic) {
        style = style.copyWith(fontStyle: FontStyle.italic);
      }
      if (node.code) {
        style = style.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Courier New', 'monospace'],
          backgroundColor: scheme.surfaceContainerHighest,
          letterSpacing: 0,
        );
      }
      if (node.href != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _handleLink(node.href!);
        _recognizers.add(recognizer);
        children.add(TextSpan(
          text: node.text,
          style: style.copyWith(
            color: scheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: scheme.primary.withValues(alpha: 0.4),
          ),
          recognizer: recognizer,
        ));
      } else {
        children.add(TextSpan(text: node.text, style: style));
      }
    }
    return TextSpan(children: children);
  }
}

/// Kopierbarer Codeblock (horizontal scrollbar + „Kopieren"-Button).
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier New', 'monospace'],
      color: scheme.onSurface,
      height: 1.45,
    );
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(context.radii.md),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(text, style: style),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: IconButton(
            tooltip: 'Kopieren',
            iconSize: context.iconSizes.sm,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.copy_rounded,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('In die Zwischenablage kopiert')),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

// ============================ Parser (pure) ============================

sealed class _Block {}

class _Heading extends _Block {
  _Heading(this.level, this.spans);
  final int level;
  final List<_Inline> spans;
}

class _Paragraph extends _Block {
  _Paragraph(this.spans);
  final List<_Inline> spans;
}

class _ListBlock extends _Block {
  _ListBlock(this.ordered, this.items);
  final bool ordered;
  final List<List<_Inline>> items;
}

class _Code extends _Block {
  _Code(this.text);
  final String text;
}

class _Callout extends _Block {
  _Callout(this.kind, this.lines);
  final String kind; // TIP | NOTE | WARNING | IMPORTANT | CAUTION | QUOTE
  final List<List<_Inline>> lines;
}

class _TableBlock extends _Block {
  _TableBlock(this.header, this.rows);
  final List<List<_Inline>> header;
  final List<List<List<_Inline>>> rows;
}

class _Rule extends _Block {}

class _Inline {
  _Inline(this.text, {this.bold = false, this.italic = false, this.code = false, this.href});
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final String? href;
}

final RegExp _headingRe = RegExp(r'^(#{1,3})\s+(.*)$');
final RegExp _ulRe = RegExp(r'^\s*[-*]\s+(.*)$');
final RegExp _olRe = RegExp(r'^\s*\d+\.\s+(.*)$');
final RegExp _tableSepRe = RegExp(r'^\s*\|?[\s:|-]+\|?\s*$');
final RegExp _calloutRe = RegExp(r'^\[!(TIP|NOTE|WARNING|IMPORTANT|CAUTION)\]\s*(.*)$');

List<_Block> _parseBlocks(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_Block>[];
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      i++;
      continue;
    }

    // Zaun-Codeblock.
    if (trimmed.startsWith('```')) {
      final buffer = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        buffer.add(lines[i]);
        i++;
      }
      i++; // schliessendes ```
      blocks.add(_Code(buffer.join('\n')));
      continue;
    }

    // Trennlinie.
    if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
      blocks.add(_Rule());
      i++;
      continue;
    }

    // Ueberschrift.
    final heading = _headingRe.firstMatch(line);
    if (heading != null) {
      blocks.add(_Heading(heading.group(1)!.length, _parseInline(heading.group(2)!.trim())));
      i++;
      continue;
    }

    // Zitat / Callout.
    if (trimmed.startsWith('>')) {
      final raw = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        raw.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
        i++;
      }
      var kind = 'QUOTE';
      if (raw.isNotEmpty) {
        final m = _calloutRe.firstMatch(raw.first.trim());
        if (m != null) {
          kind = m.group(1)!;
          final rest = m.group(2)!.trim();
          raw[0] = rest;
          if (rest.isEmpty) {
            raw.removeAt(0);
          }
        }
      }
      final paragraphs = _joinSoftLines(raw);
      blocks.add(_Callout(kind, [for (final p in paragraphs) _parseInline(p)]));
      continue;
    }

    // Tabelle: Kopfzeile mit '|' + Separator in der naechsten Zeile.
    if (trimmed.contains('|') &&
        i + 1 < lines.length &&
        _tableSepRe.hasMatch(lines[i + 1]) &&
        lines[i + 1].contains('-')) {
      final header = _tableCells(line);
      i += 2; // Kopf + Separator
      final rows = <List<List<_Inline>>>[];
      while (i < lines.length &&
          lines[i].trim().contains('|') &&
          lines[i].trim().isNotEmpty) {
        rows.add(_tableCells(lines[i]));
        i++;
      }
      blocks.add(_TableBlock(header, rows));
      continue;
    }

    // Aufzaehlung (unsortiert).
    if (_ulRe.hasMatch(line)) {
      final items = <List<_Inline>>[];
      while (i < lines.length && _ulRe.hasMatch(lines[i])) {
        items.add(_parseInline(_ulRe.firstMatch(lines[i])!.group(1)!.trim()));
        i++;
      }
      blocks.add(_ListBlock(false, items));
      continue;
    }

    // Aufzaehlung (nummeriert).
    if (_olRe.hasMatch(line)) {
      final items = <List<_Inline>>[];
      while (i < lines.length && _olRe.hasMatch(lines[i])) {
        items.add(_parseInline(_olRe.firstMatch(lines[i])!.group(1)!.trim()));
        i++;
      }
      blocks.add(_ListBlock(true, items));
      continue;
    }

    // Absatz: aufeinanderfolgende „gewoehnliche" Zeilen zusammenfassen.
    final para = <String>[];
    while (i < lines.length) {
      final l = lines[i];
      final t = l.trim();
      if (t.isEmpty ||
          t.startsWith('```') ||
          t.startsWith('>') ||
          t == '---' ||
          _headingRe.hasMatch(l) ||
          _ulRe.hasMatch(l) ||
          _olRe.hasMatch(l)) {
        break;
      }
      para.add(t);
      i++;
    }
    if (para.isNotEmpty) {
      blocks.add(_Paragraph(_parseInline(para.join(' '))));
    }
  }

  return blocks;
}

/// Fasst „weiche" Zeilen innerhalb eines Zitats zu Absaetzen zusammen
/// (Leerzeile trennt Absaetze).
List<String> _joinSoftLines(List<String> raw) {
  final out = <String>[];
  final current = <String>[];
  for (final line in raw) {
    if (line.trim().isEmpty) {
      if (current.isNotEmpty) {
        out.add(current.join(' '));
        current.clear();
      }
    } else {
      current.add(line.trim());
    }
  }
  if (current.isNotEmpty) {
    out.add(current.join(' '));
  }
  return out;
}

List<List<_Inline>> _tableCells(String line) {
  var t = line.trim();
  if (t.startsWith('|')) {
    t = t.substring(1);
  }
  if (t.endsWith('|')) {
    t = t.substring(0, t.length - 1);
  }
  return t.split('|').map((c) => _parseInline(c.trim())).toList();
}

final RegExp _inlineRe = RegExp(
  r'(`[^`]+`)|(\[[^\]]+\]\([^)]+\))|(\*\*[^*]+\*\*)|(\*[^*\n]+\*)',
);
final RegExp _linkRe = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)$');

List<_Inline> _parseInline(String text) {
  if (text.isEmpty) {
    return const <_Inline>[];
  }
  final out = <_Inline>[];
  var last = 0;
  for (final m in _inlineRe.allMatches(text)) {
    if (m.start > last) {
      out.add(_Inline(text.substring(last, m.start)));
    }
    final token = m.group(0)!;
    if (token.startsWith('`')) {
      out.add(_Inline(token.substring(1, token.length - 1), code: true));
    } else if (token.startsWith('[')) {
      final link = _linkRe.firstMatch(token);
      if (link != null) {
        out.add(_Inline(link.group(1)!, href: link.group(2)!.trim()));
      } else {
        out.add(_Inline(token));
      }
    } else if (token.startsWith('**')) {
      out.add(_Inline(token.substring(2, token.length - 2), bold: true));
    } else {
      out.add(_Inline(token.substring(1, token.length - 1), italic: true));
    }
    last = m.end;
  }
  if (last < text.length) {
    out.add(_Inline(text.substring(last)));
  }
  return out;
}
