/// One reading section within a lesson — a short heading + body paragraph.
/// LessonContentScreen pages through these before the lesson can be
/// completed (see LearningPathScreen / LessonContentScreen).
class LessonSection {
  final String heading;
  final String body;

  const LessonSection({required this.heading, required this.body});
}

class Lesson {
  final String id;
  final String title;
  final String description;
  final String difficulty; // 'Beginner', 'Intermediate', 'Advanced'
  final int xpReward;
  final String riskProfileMatch; // 'Conservative', 'Balanced', 'Aggressive', 'All'
  final List<LessonSection> content;

  Lesson({
    required this.id,
    required this.title,
    required this.description,
    required this.difficulty,
    required this.xpReward,
    required this.riskProfileMatch,
    this.content = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'difficulty': difficulty,
    'xpReward': xpReward,
    'riskProfileMatch': riskProfileMatch,
  };

  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
    id: json['id'],
    title: json['title'],
    description: json['description'],
    difficulty: json['difficulty'],
    xpReward: json['xpReward'],
    riskProfileMatch: json['riskProfileMatch'],
  );
}