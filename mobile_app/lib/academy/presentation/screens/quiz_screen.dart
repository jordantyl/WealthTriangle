import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../application/academy_state.dart';
import '../../application/badge_service.dart';
import '../../../shared/app_theme_colors.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _currentQuestionIndex = 0;
  int _score = 0;
  bool _isAnswered = false;
  int _selectedAnswerIndex = -1; // Tracks which button you clicked

  // Frozen once populated — getQuestionsForUser() shuffles on every call,
  // so re-deriving it in build() would reshuffle (and change the question
  // under the user's feet) on every setState-triggered rebuild.
  List<Map<String, dynamic>>? _questions;

  void _answerQuestion(int index, Map<String, dynamic> question) {
    if (_isAnswered) return;
    
    setState(() {
      _isAnswered = true;
      _selectedAnswerIndex = index;
      
      if (index == question['answer']) {
        _score += 100; // 100 XP per correct answer
      }
    });
  }

  void _nextQuestion(int totalQuestions) {
    final academyState = Provider.of<AcademyState>(context, listen: false);

    setState(() {
      if (_currentQuestionIndex < totalQuestions - 1) {
        // Go to next question
        _currentQuestionIndex++;
        _isAnswered = false;
        _selectedAnswerIndex = -1;
      } else {
        academyState.saveQuizResult(_score);
        
        BadgeService.award(context, 'first_steps');
        if (_score >= 500) BadgeService.award(context, 'quiz_master');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Quiz Complete! You earned $_score XP."),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 1. Listen to Database
    final academyState = Provider.of<AcademyState>(context);
    if (_questions == null && academyState.quizzes.isNotEmpty) {
      _questions = academyState.getQuestionsForUser();
    }
    final questions = _questions ?? [];

    // 2. Loading State (If no data found)
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Financial IQ Quiz")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text("Loading Questions..."),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => academyState.fetchGameContent(), 
                icon: const Icon(Icons.refresh), 
                label: const Text("Retry Connection")
              )
            ],
          ),
        ),
      );
    }

    // 3. The Quiz UI
    final question = questions[_currentQuestionIndex];
    
    // Safety check: Ensure 'options' is actually a List
    List<dynamic> options = question['options'] ?? [];

    return Scaffold(
      appBar: AppBar(title: Text("Question ${_currentQuestionIndex + 1}/${questions.length}")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Progress Bar
            LinearProgressIndicator(
              value: (_currentQuestionIndex + 1) / questions.length,
              backgroundColor: Colors.grey.withOpacity(0.2),
              color: Colors.blueAccent,
            ),
            const SizedBox(height: 40),
            
            // Question Text
            Text(
              question['question'] ?? "Error loading question", 
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 30),

            // Options Buttons
            ...List.generate(options.length, (index) {
              bool isCorrect = index == question['answer'];
              Color btnColor = Colors.blueGrey.withOpacity(0.1); // Default color
              
              if (_isAnswered) {
                if (isCorrect) btnColor = Colors.green.withOpacity(0.5); // Show correct
                else if (index == _selectedAnswerIndex) btnColor = Colors.red.withOpacity(0.5); // Show your wrong choice
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: btnColor,
                    padding: const EdgeInsets.all(15),
                    alignment: Alignment.centerLeft
                  ),
                  onPressed: () => _answerQuestion(index, question),
                  child: Text(
                    options[index].toString(),
                    style: TextStyle(fontSize: 16, color: context.appColors.textPrimary)
                  ),
                ),
              );
            }),

            const Spacer(),
            
            // Explanation & Next Button (Only shows after answering)
            if (_isAnswered) ...[
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb, color: Colors.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        question['explanation'] ?? "No explanation available.",
                        style: TextStyle(color: context.appColors.textSecondary)
                      )
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => _nextQuestion(questions.length), 
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  child: Text(
                    _currentQuestionIndex == questions.length - 1 ? "FINISH QUIZ" : "NEXT QUESTION ->", 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                  )
                ),
              )
            ]
          ],
        ),
      ),
    );
  }
}