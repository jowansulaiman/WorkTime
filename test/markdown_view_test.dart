import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worktime_app/widgets/markdown_view.dart';

void main() {
  testWidgets('rendert Überschriften, Absätze, Listen, Callout und Codeblock',
      (tester) async {
    const md = '# Titel\n'
        '\n'
        'Ein Absatz mit **fett** und einem [Verweis](article:ziel-slug).\n'
        '\n'
        '## Abschnitt\n'
        '\n'
        '- Punkt eins\n'
        '- Punkt zwei\n'
        '\n'
        '> [!WARNING]\n'
        '> Achtung hier.\n'
        '\n'
        '```dart\n'
        'final x = 1;\n'
        '```\n';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownView(data: md, onOpenArticle: (_) {}),
          ),
        ),
      ),
    );

    expect(find.textContaining('Titel', findRichText: true), findsWidgets);
    expect(find.textContaining('Abschnitt', findRichText: true), findsWidgets);
    expect(find.textContaining('Punkt eins', findRichText: true), findsWidgets);
    expect(find.textContaining('Punkt zwei', findRichText: true), findsWidgets);
    expect(find.textContaining('Achtung hier', findRichText: true), findsWidgets);
    expect(find.textContaining('final x = 1;', findRichText: true), findsWidgets);
  });

  testWidgets('leerer Inhalt wirft nicht', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MarkdownView(data: ''))),
    );
    expect(find.byType(MarkdownView), findsOneWidget);
  });
}
