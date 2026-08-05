/// Describes the editable fields for one academy_* collection, so the
/// Content Editor can render a form without a hand-written screen per
/// collection. Kept in sync with the field names AcademyState.seedDatabase()
/// writes, since Firestore docs from either path (bulk seed or per-doc
/// editor) must look identical to the mobile app reading them.
enum FieldType { text, multilineText, number, boolean, stringList, numberMap }

class FieldSpec {
  final String key;
  final String label;
  final FieldType type;
  final String? hint;

  const FieldSpec(this.key, this.label, this.type, {this.hint});
}

class ContentSchema {
  final String label;
  final List<FieldSpec> fields;
  final String Function(Map<String, dynamic> data) titleOf;

  const ContentSchema({required this.label, required this.fields, required this.titleOf});
}

final Map<String, ContentSchema> contentSchemas = {
  'academy_scenarios': ContentSchema(
    label: 'Scenarios',
    titleOf: (d) => (d['title'] as String?)?.isNotEmpty == true ? d['title'] : '(untitled)',
    fields: const [
      FieldSpec('id', 'Scenario ID', FieldType.text, hint: 'stable ID, e.g. scn_007 — required'),
      FieldSpec('title', 'Title', FieldType.text),
      FieldSpec('newsHeadline', 'News Headline', FieldType.text),
      FieldSpec('newsDescription', 'News Description', FieldType.multilineText),
      FieldSpec('aiFeedback', 'AI Feedback', FieldType.multilineText),
      FieldSpec('assetImpact', 'Asset Impact', FieldType.numberMap,
          hint: 'one per line, e.g. Tech: 1.3 (1.0 = no change) — required, at least one line'),
    ],
  ),
  'academy_quizzes': ContentSchema(
    label: 'Quizzes',
    titleOf: (d) => (d['question'] as String?)?.isNotEmpty == true ? d['question'] : '(untitled)',
    fields: const [
      FieldSpec('question', 'Question', FieldType.text),
      FieldSpec('options', 'Options', FieldType.stringList, hint: 'one per line, 4 total'),
      FieldSpec('answer', 'Correct Option Index', FieldType.number, hint: '0-based, e.g. 1'),
      FieldSpec('explanation', 'Explanation', FieldType.multilineText),
      FieldSpec('minLevel', 'Min Level', FieldType.number),
    ],
  ),
  'academy_flash': ContentSchema(
    label: 'Flashcards',
    titleOf: (d) => (d['news'] as String?)?.isNotEmpty == true ? d['news'] : '(untitled)',
    fields: const [
      FieldSpec('news', 'News Headline', FieldType.text),
      FieldSpec('shouldBuy', 'Should Buy?', FieldType.boolean),
      FieldSpec('type', 'Type', FieldType.text, hint: 'e.g. company, tech, market'),
      FieldSpec('minLevel', 'Min Level', FieldType.number),
    ],
  ),
  'academy_trade_items': ContentSchema(
    label: 'Trade Items',
    titleOf: (d) => (d['name'] as String?)?.isNotEmpty == true ? d['name'] : '(untitled)',
    fields: const [
      FieldSpec('id', 'Item ID', FieldType.text, hint: 'stable ID, e.g. t_13'),
      FieldSpec('name', 'Name', FieldType.text),
      FieldSpec('category', 'Category', FieldType.text, hint: 'tech, food, resource, luxury'),
      FieldSpec('basePrice', 'Base Price', FieldType.number),
    ],
  ),
  'academy_trade_events': ContentSchema(
    label: 'Trade Events',
    titleOf: (d) => (d['text'] as String?)?.isNotEmpty == true ? d['text'] : '(untitled)',
    fields: const [
      FieldSpec('text', 'Event Text', FieldType.text),
      FieldSpec('type', 'Type', FieldType.text, hint: 'e.g. price_change'),
      FieldSpec('impact', 'Impact', FieldType.numberMap, hint: 'one per line, e.g. tech: 1.5'),
      FieldSpec('isGlobal', 'Is Global?', FieldType.boolean),
      FieldSpec('turnsDelay', 'Turns Delay', FieldType.number),
    ],
  ),
};
