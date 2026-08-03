import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../application/academy_state.dart';
import '../../domain/lesson.dart';
import '../../../shared/app_theme_colors.dart';

/// Real reading content for a Lesson — replaces the old behavior where
/// LearningPathScreen's "Start" button awarded XP instantly with nothing in
/// between. Pages through lesson.content section by section; "Mark as
/// Learned" only appears once the last section has actually been reached.
class LessonContentScreen extends StatefulWidget {
  final Lesson lesson;

  const LessonContentScreen({super.key, required this.lesson});

  @override
  State<LessonContentScreen> createState() => _LessonContentScreenState();
}

class _LessonContentScreenState extends State<LessonContentScreen> {
  final PageController _pageController = PageController();
  int _pageIndex = 0;

  bool get _isLastPage => _pageIndex == widget.lesson.content.length - 1;

  void _next() {
    if (_isLastPage) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _markLearned() async {
    final state = Provider.of<AcademyState>(context, listen: false);
    final alreadyCompleted = state.completedLessonIds.contains(widget.lesson.id);
    await state.completeLesson(widget.lesson);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(alreadyCompleted
            ? 'Lesson reviewed.'
            : '✅ Lesson Completed! +${widget.lesson.xpReward} XP'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sections = widget.lesson.content;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        title: Text(widget.lesson.title),
      ),
      body: sections.isEmpty
          ? const Center(child: Text('No content available for this lesson yet.'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: List.generate(sections.length, (i) {
                      final isActive = i <= _pageIndex;
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: i == sections.length - 1 ? 0 : 6),
                          height: 4,
                          decoration: BoxDecoration(
                            color: isActive ? Colors.blueAccent : colors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: sections.length,
                    onPageChanged: (i) => setState(() => _pageIndex = i),
                    itemBuilder: (context, i) {
                      final section = sections[i];
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Section ${i + 1} of ${sections.length}',
                              style: TextStyle(color: colors.textTertiary, fontSize: 12, letterSpacing: 1),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              section.heading,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              section.body,
                              style: TextStyle(color: colors.textSecondary, fontSize: 15, height: 1.5),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Row(
                    children: [
                      if (_pageIndex > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _back,
                            child: const Text('Back'),
                          ),
                        ),
                      if (_pageIndex > 0) const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isLastPage ? Colors.green : Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _isLastPage ? _markLearned : _next,
                          child: Text(_isLastPage ? 'Mark as Learned' : 'Next'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
