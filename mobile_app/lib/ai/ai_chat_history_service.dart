import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// One saved AI conversation's metadata, for the "pick a chat" list — never
/// carries the full message list (see loadMessages for that), so listing
/// many chats stays cheap.
class ChatSummary {
  final String id;
  final String title;
  final DateTime? updatedAt;

  const ChatSummary({required this.id, required this.title, this.updatedAt});
}

/// Multi-conversation AI chat history, shared by the in-app AI Assistant
/// screen and the floating bubble ("Quick Ask") — both read/write the same
/// `users/{uid}/ai_chats/{chatId}` collection, so switching between "pick a
/// past chat" on either surface sees the same list. Replaces the older
/// single fixed-doc `users/{uid}/ai_chat/history` layout, which only ever
/// held one conversation with no way to start a fresh one or revisit an
/// older one.
class AIChatHistoryService {
  // Keeps any one conversation from growing forever in Firestore — same
  // idea as PaperTradingEngine's maxPersistedTradeLog.
  static const maxSavedMessages = 50;

  CollectionReference<Map<String, dynamic>>? get _chatsRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('ai_chats');
  }

  Future<List<ChatSummary>> listChats() async {
    final ref = _chatsRef;
    if (ref == null) return [];
    final snapshot = await ref.orderBy('updatedAt', descending: true).limit(50).get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return ChatSummary(
        id: doc.id,
        title: (data['title'] as String?)?.trim().isNotEmpty == true
            ? data['title'] as String
            : 'New chat',
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      );
    }).toList();
  }

  Future<List<Map<String, String>>> loadMessages(String chatId) async {
    final ref = _chatsRef;
    if (ref == null) return [];
    final doc = await ref.doc(chatId).get();
    final saved = doc.data()?['messages'] as List<dynamic>?;
    if (saved == null) return [];
    return saved.map((m) => Map<String, String>.from(m as Map)).toList();
  }

  /// Creates an empty chat doc and returns its id — call once when the user
  /// starts a new conversation, then use [saveMessages] with that id from
  /// then on.
  Future<String?> createChat() async {
    final ref = _chatsRef;
    if (ref == null) return null;
    final doc = await ref.add({
      'title': '',
      'messages': [],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// [titleHint] is only used the first time a chat gets a title (usually
  /// the first user message, truncated) — later calls leave an
  /// already-set title alone rather than overwriting it with a later
  /// message.
  Future<void> saveMessages(String chatId, List<Map<String, String>> messages, {String? titleHint}) async {
    final ref = _chatsRef;
    if (ref == null) return;
    final toSave = messages.length > maxSavedMessages
        ? messages.sublist(messages.length - maxSavedMessages)
        : messages;

    final docRef = ref.doc(chatId);
    final update = <String, dynamic>{
      'messages': toSave,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (titleHint != null && titleHint.trim().isNotEmpty) {
      final existing = await docRef.get();
      final hasTitle = (existing.data()?['title'] as String?)?.trim().isNotEmpty == true;
      if (!hasTitle) {
        final trimmed = titleHint.trim();
        update['title'] = trimmed.length > 40 ? '${trimmed.substring(0, 40)}…' : trimmed;
      }
    }
    await docRef.set(update, SetOptions(merge: true));
  }

  Future<void> deleteChat(String chatId) async {
    await _chatsRef?.doc(chatId).delete();
  }
}
