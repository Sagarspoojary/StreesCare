import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import '../config/api_config.dart';

class ChatService {
  static const String baseUrl = ApiConfig.baseUrl;

  static Future<String?> getFreshFirebaseToken() async {
    final user = FirebaseAuth.instance.currentUser;
    String? token = user != null ? await user.getIdToken(true) : null;
    
    // Fallback to SharedPreferences if FirebaseAuth is null (e.g. hackathon test login)
    if (token == null) {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString("auth_token");
    }
    return token;
  }

  // 📤 SEND MESSAGE TO BACKEND
  static Future<Map<String, dynamic>> sendMessage({
    required String message,
    bool ghostMode = false,
    String session_id = "default",
    String inputType = "text",
  }) async {
    // 🔥 Get a FRESH token directly from Firebase to prevent 1-hour expiration 401 errors
    final token = await getFreshFirebaseToken();

    final res = await http.post(
      Uri.parse("$baseUrl/chat/message"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({
        "message": message,
        "session_id": session_id,
        "ghost_mode": ghostMode,
        "input_type": inputType,
      }),
    );
    
    final decodedBody = utf8.decode(res.bodyBytes);
    final data = jsonDecode(decodedBody);
    print("API RESPONSE: $data");
    
    // 🔥 Firebase Integration (Save chat history)
    try {
      if (!ghostMode) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final textToSave = data["masked_text"] ?? message;
          await FirestoreService.saveChatHistory(user.uid, textToSave, true);
          if (data["ai_response"] != null) {
            await FirestoreService.saveChatHistory(user.uid, data["ai_response"], false);
          }
        }
      }
    } catch (e) {
      print("Firebase Save Chat Error: $e");
    }

    return data;
  }

  // 🔒 UPDATE PRIVACY STATUS
  static Future<Map<String, dynamic>> updatePrivacy({
    required String chatId,
    required bool isPrivate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token");

    final res = await http.put(
      Uri.parse("$baseUrl/chat/privacy"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({
        "chat_id": chatId,
        "is_private": isPrivate,
      }),
    );
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  // 💾 GET CHAT HISTORY
  static Future<List<dynamic>> getChatHistory() async {
    final token = await getFreshFirebaseToken();

    final res = await http.get(
      Uri.parse("$baseUrl/chat/history"),
      headers: {
        "Authorization": "Bearer $token",
      },
    );
    
    final decodedBody = utf8.decode(res.bodyBytes);
    final data = jsonDecode(decodedBody);
    return data["messages"] ?? [];
  }

  // 🗑️ CLEAR CHAT HISTORY
  static Future<Map<String, dynamic>> clearChatHistory() async {
    final token = await getFreshFirebaseToken();

    final res = await http.delete(
      Uri.parse("$baseUrl/chat/history"),
      headers: {
        "Authorization": "Bearer $token",
      },
    );
    final decodedBody = utf8.decode(res.bodyBytes);
    return jsonDecode(decodedBody);
  }

  // 📊 GET STRESS TRENDS
  static Future<List<dynamic>> getStressTrends() async {
    final token = await getFreshFirebaseToken();

    final res = await http.get(
      Uri.parse("$baseUrl/chat/stress-trends"),
      headers: {
        "Authorization": "Bearer $token",
      },
    );
    
    final decodedBody = utf8.decode(res.bodyBytes);
    final data = jsonDecode(decodedBody);
    final trends = data["trends"] ?? [];
    
    // 🔥 Firebase Integration (Save stress reports)
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && trends.isNotEmpty) {
        for (var trend in trends) {
          if (trend is Map<String, dynamic>) {
            await FirestoreService.saveStressReport(user.uid, trend);
          }
        }
      }
    } catch (e) {
      print("Firebase Save Stress Report Error: $e");
    }

    return trends;
  }
}