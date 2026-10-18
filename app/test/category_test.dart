import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/widgets/category.dart';

void main() {
  test('category is optional in case rows and details (old servers send none)', () {
    final row = CaseRow({'id': 'c001', 'title': 't', 'category': 'medical'});
    expect(row.category, 'medical');
    expect(CaseRow({'id': 'c001', 'title': 't'}).category, '');
    expect(kCategories.keys, containsAll(['medical', 'art', 'family', 'business', 'science', 'travel', 'crime']));
    expect(categoryName('crime'), 'جرم و قانون');
    expect(categoryName('nope'), '');
  });

  testWidgets('the badge shows icon + name, nothing for an unknown key', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(children: [CategoryBadge('family'), CategoryBadge(''), CategoryBadge('zzz')]),
      ),
    ));
    expect(find.text('خانواده و ارث'), findsOneWidget);
    expect(find.byKey(const ValueKey('category-family')), findsOneWidget);
    expect(find.byType(Icon), findsOneWidget);
  });
}
