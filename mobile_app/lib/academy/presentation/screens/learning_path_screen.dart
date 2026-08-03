import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../application/academy_state.dart';
import '../../../shared/app_theme_colors.dart';
import 'lesson_content_screen.dart';

class LearningPathScreen extends StatefulWidget {
  const LearningPathScreen({super.key});

  @override
  State<LearningPathScreen> createState() => _LearningPathScreenState();
}

class _LearningPathScreenState extends State<LearningPathScreen> {

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AcademyState>(context);
    final lessons = state.getPersonalizedLessons();
    final completedLessonIds = state.completedLessonIds;
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📚 Learning Path'),
            Text(
              'Personalized for ${state.riskProfile} investor',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      body: lessons.isEmpty
          ? const Center(
              child: Text('No lessons available. Check back later!'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: lessons.length,
              itemBuilder: (context, index) {
                final lesson = lessons[index];
                final isCompleted = completedLessonIds.contains(lesson.id);

                return Card(
                  color: isCompleted
                      ? Colors.green.withOpacity(0.1)
                      : colors.surface,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? Colors.green.withOpacity(0.2)
                            : Colors.blueAccent.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCompleted ? Icons.check_circle : Icons.school,
                        color: isCompleted ? Colors.green : Colors.blueAccent,
                      ),
                    ),
                    title: Text(
                      lesson.title,
                      style: TextStyle(
                        color: isCompleted ? Colors.green : colors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          lesson.description,
                          style: TextStyle(color: colors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _buildDifficultyTag(lesson.difficulty),
                            const SizedBox(width: 8),
                            _buildXPTag(lesson.xpReward),
                            const SizedBox(width: 8),
                            _buildProfileMatchTag(lesson.riskProfileMatch),
                          ],
                        ),
                      ],
                    ),
                    trailing: ElevatedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => LessonContentScreen(lesson: lesson)),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCompleted ? Colors.green : Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: Text(isCompleted ? 'Review' : 'Start'),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildDifficultyTag(String difficulty) {
    Color color;
    switch (difficulty) {
      case 'Beginner':
        color = Colors.green;
        break;
      case 'Intermediate':
        color = Colors.orange;
        break;
      case 'Advanced':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        difficulty,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildXPTag(int xp) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$xp XP',
        style: const TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildProfileMatchTag(String profile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        profile == 'All' ? '🌍 All' : '🎯 $profile',
        style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}