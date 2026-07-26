# google_mlkit_text_recognition's plugin code references the optional
# Chinese/Devanagari/Japanese/Korean script recognizer classes, but this app
# only depends on the Latin recognizer (see add_transaction_screen.dart —
# TextRecognitionScript.latin only). R8 can't find those other script
# classes at minify time and fails the release build entirely without this;
# -dontwarn is safe here because that code path is never actually invoked.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
