import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:image_picker/image_picker.dart';
import '../core/constants/app_colors.dart';
import '../utils/camera_helper.dart';
import '../services/chat_service.dart';
import 'trends_screen.dart';
import '../config/api_config.dart';
import '../utils/web_helper.dart';
import '../widgets/waveform_player.dart';
import 'face_detection_screen.dart';
import 'session_history_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  
  List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  bool _ghostMode = false;
  
  // Voice input
  stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechEnabled = false;
  bool _listening = false;
  String _selectedLocale = "en_IN"; // Default mixed language
  
  final ImagePicker _picker = ImagePicker();

  // 📷 CAMERA LOGIC
  Future<void> _openCamera() async {
    try {
      if (kIsWeb) {
        // Dual handling for web: Try in-app capture, fallback to picker
        try {
          await openWebCamera(context, (msg) {
            if (mounted) {
              final emotion = _parseEmotionFromResult(msg);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Face Scanner Detected: $emotion. Analyzing mood...")),
              );
              _sendFaceEmotionMessage(emotion);
            }
          });
        } catch (e) {
          _openFilePicker();
        }
      } else {
        // Mobile behavior: Navigate to FaceDetectionScreen
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const FaceDetectionScreen()),
        );
        
        if (result != null && result is String) {
          if (mounted) {
            final emotion = _parseEmotionFromResult(result);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Face Scanner Detected: $emotion. Analyzing mood...")),
            );
            _sendFaceEmotionMessage(emotion);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Camera error")),
        );
      }
    }
  }

  String _parseEmotionFromResult(String result) {
    if (result.contains("Live Emotion Detected: ")) {
      return result.replaceAll("Live Emotion Detected: ", "").trim();
    }
    return result.trim();
  }

  void _openFilePicker() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery);
      if (file != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Selected file: ${file.name}")),
          );
        }
      }
    } catch (e) {
      print("Error picking file: $e");
    }
  }

  Color get bgColor => _ghostMode ? const Color(0xFF121212) : AppColors.background;
  Color get surfaceColor => _ghostMode ? const Color(0xFF1E1E1E) : AppColors.surface;
  Color get textColor => _ghostMode ? Colors.white : AppColors.textDark;
  Color get primaryColor => _ghostMode ? Colors.tealAccent.shade400 : AppColors.primary;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isLocked = false;
  String? _pinCode;
  String _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
  
  // Selection mode for privacy locking
  bool _isSelectionMode = false;
  Set<String> _selectedChatIds = {};

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadSettings(); // 🛠️ Load persisted settings
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt("app_start_time_ms") == null) {
      await prefs.setInt("app_start_time_ms", DateTime.now().millisecondsSinceEpoch);
    }
    const storage = FlutterSecureStorage();
    final pin = await storage.read(key: "app_pin");
    
    setState(() {
      _ghostMode = prefs.getBool("ghostMode") ?? false;
      _isLocked = prefs.getBool("privacyLock") ?? false;
      _pinCode = pin;
    });
    
    // If locked and PIN exists, trigger unlock!
    if (_isLocked && pin != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPinDialog(title: "Enter PIN to Unlock", isSetup: false);
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("ghostMode", _ghostMode);
    await prefs.setBool("privacyLock", _isLocked);
  }

  Future<void> _toggleGhostMode(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("ghostMode", val);
    setState(() {
      _ghostMode = val;
    });
    if (val) {
      _showSnack("Ghost Mode Active 👻", isError: false);
    } else {
      _showSnack("Ghost Mode Disabled 👤", isError: false);
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("auth_token");
    if (mounted) {
      Navigator.pushReplacementNamed(context, "/signup"); // Ensure this route exists
    }
  }

  // 🛡️ Helper to hide masked tokens from UI
  String _unmaskText(String text) {
    return text
      .replaceAll(RegExp(r'USER_\d+'), 'you')
      .replaceAll(RegExp(r'CITY_\d+'), 'your city')
      .replaceAll(RegExp(r'PHONE_\d+'), 'your number')
      .replaceAll(RegExp(r'ENTITY_\d+'), 'someone')
      .replaceAll(RegExp(r'AADHAAR_\d+'), 'your ID')
      .replaceAll(RegExp(r'PAN_\d+'), 'your tax ID')
      .replaceAll(RegExp(r'GENDER_\d+'), 'your gender')
      .replaceAll(RegExp(r'EMAIL_\d+'), 'your email');
  }
  
  Future<void> _loadHistory() async {
    try {
      final history = await ChatService.getChatHistory();
      setState(() {
        _messages = history.map((m) {
          final content = (m["user_message"] != null) 
              ? m["user_message"].toString()
              : _unmaskText(m["ai_response"] ?? "");
          
          // 🛡️ FRONTEND FALLBACK for history
          String detectedEmotion = m["emotion"] ?? "neutral";
          if (detectedEmotion == "neutral" && m["user_message"] != null) {
            final lowerInput = m["user_message"].toString().toLowerCase();
            final positiveKeywords = ["happy", "great", "good", "awesome", "excited", "wonderful", "amazing"];
            final negationKeywords = ["not happy", "not good", "not great", "unhappy"];
            
            bool hasPositive = positiveKeywords.any((k) => lowerInput.contains(k));
            bool hasNegation = negationKeywords.any((k) => lowerInput.contains(k));
            
            if (hasPositive && !hasNegation) {
              detectedEmotion = "happiness";
            }
          }

          return {
            "chat_id": m["chat_id"],
            "role": (m["user_message"] != null) ? "user" : "assistant",
            "content": content,
            "stress_level": m["stress_level"],
            "emotion": detectedEmotion,
            "stress_score": m["score"] ?? m["stress_score"],
            "timestamp": m["timestamp"] ?? m["created_at"] ?? DateTime.now().toIso8601String(),
            "analysis": m["analysis"] ?? "",
            "is_private": m["is_private"] ?? false,
            "emergency": m["emergency"] == true,
          };
        }).toList();

        // 📅 FEATURE 1: ORDERED SESSION HISTORY (Latest First)
        _messages.sort((a, b) {
          try {
            DateTime timeA = DateTime.parse(a["timestamp"]);
            DateTime timeB = DateTime.parse(b["timestamp"]);
            return timeB.compareTo(timeA); // Descending
          } catch (e) {
            return 0;
          }
        });
      });
      _scrollToBottom();
    } catch (e) {
      print("Error loading history: $e");
    }
  }

  // 🔒 Lock selected chats
  Future<void> _lockSelectedChats() async {
    if (_selectedChatIds.isEmpty) return;
    
    setState(() => _loading = true);
    try {
      for (String id in _selectedChatIds) {
        await ChatService.updatePrivacy(chatId: id, isPrivate: true);
      }
      _showSnack("Selected chats locked successfully", isError: false);
      _selectedChatIds.clear();
      _isSelectionMode = false;
      _loadHistory(); // Refresh
    } catch (e) {
      _showSnack("Error locking chats: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  void _toggleSelection(String? chatId) {
    setState(() {
      if (chatId == null) {
        _isSelectionMode = !_isSelectionMode;
        _selectedChatIds.clear();
      } else {
        if (_selectedChatIds.contains(chatId)) {
          _selectedChatIds.remove(chatId);
        } else {
          _selectedChatIds.add(chatId);
        }
      }
    });
  }
  
  void _initSpeech() async {
    _speechEnabled = await _speech.initialize(
      onError: (error) => print("Speech error: $error"),
      onStatus: (status) => print("Speech status: $status"),
    );
    
    // Register Waveform Factory for Web
    registerGlobalWaveformView();
    
    setState(() {});
  }


  void _showSnack(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : primaryColor,
      ),
    );
  }

  // 📤 SEND MESSAGE
  Future<void> _sendMessage({String inputType = "text"}) async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    // STEP 1: Immediately add user message to list and update UI
    setState(() {
      _messages.add({"role": "user", "content": text});
      _loading = true;
    });

    // STEP 2: Clear input field
    _msgCtrl.clear();
    
    // STEP 3: Auto-scroll to bottom after user message
    _scrollToBottom();

    try {
      // STEP 4: Call backend API
      final res = await ChatService.sendMessage(
        message: text,
        session_id: _currentSessionId,
        ghostMode: _ghostMode,
        inputType: inputType,
      );

      setState(() => _loading = false);

      if (res["error"] != null || res["detail"] != null) {
        _showSnack(res["error"] ?? res["detail"]);
      } else {
        print("API RESPONSE: $res");
        
        // STEP 5: Update user message to masked version & add AI message
        setState(() {
          // Find the last user message and update it with the masked version from backend
          for (int i = _messages.length - 1; i >= 0; i--) {
            if (_messages[i]["role"] == "user") {
              _messages[i]["content"] = res["masked_text"] ?? res["masked_message"] ?? _messages[i]["content"];
              break;
            }
          }

          // 🛡️ FRONTEND FALLBACK: Correct "neutral" to "happiness" for clearly positive input
          String detectedEmotion = res["emotion"] ?? "neutral";
          final lowerInput = text.toLowerCase();
          
          if (detectedEmotion == "neutral") {
            final positiveKeywords = ["happy", "great", "good", "awesome", "excited", "wonderful", "amazing"];
            final negationKeywords = ["not happy", "not good", "not great", "unhappy"];
            
            bool hasPositive = positiveKeywords.any((k) => lowerInput.contains(k));
            bool hasNegation = negationKeywords.any((k) => lowerInput.contains(k));
            
            if (hasPositive && !hasNegation) {
              detectedEmotion = "happiness";
            }
          }

          _messages.add({
            "chat_id": res["chat_id"],
            "role": "assistant",
            "content": _unmaskText(res["ai_response"] ?? ""),
            "stress_score": res["stress_score"],
            "stress_level": res["stress_level"] ?? "low",
            "emotion": res["emotion"],
            "confidence": res["confidence"],
            "analysis": res["analysis"],
            "wellness_tip": res["wellness_tip"],
            "emergency": res["emergency"] == true,
          });
        });
        
        // 🚨 EMERGENCY DETECTION & PRIORITY LOGIC (Robust Suicide/Self-Harm Detection)
        // Note: Modal popup triggers were removed to avoid UI interruption
        
        // Final scroll to bottom for AI response
        _scrollToBottom();
      }
    } catch (e) {
      setState(() => _loading = false);
      _showSnack("Connection error");
    }
  }

  // 🎭 SEND FACE EMOTION TO GEMINI
  Future<void> _sendFaceEmotionMessage(String emotion) async {
    final text = "My face scanner detected my current facial expression as: $emotion. Can you analyze this?";
    
    // STEP 1: Immediately add user message to list and update UI
    setState(() {
      _messages.add({"role": "user", "content": text});
      _loading = true;
    });

    // STEP 2: Auto-scroll to bottom after user message
    _scrollToBottom();

    try {
      // STEP 3: Call backend API
      final res = await ChatService.sendMessage(
        message: text,
        session_id: _currentSessionId,
        ghostMode: _ghostMode,
        inputType: "face_emotion",
      );

      setState(() => _loading = false);

      if (res["error"] != null || res["detail"] != null) {
        _showSnack(res["error"] ?? res["detail"]);
      } else {
        print("API RESPONSE: $res");
        
        // STEP 4: Update user message & add AI response
        setState(() {
          // Find the last user message and update it with the masked version
          for (int i = _messages.length - 1; i >= 0; i--) {
            if (_messages[i]["role"] == "user") {
              _messages[i]["content"] = res["masked_text"] ?? res["masked_message"] ?? _messages[i]["content"];
              break;
            }
          }

          _messages.add({
            "chat_id": res["chat_id"],
            "role": "assistant",
            "content": _unmaskText(res["ai_response"] ?? ""),
            "stress_score": res["stress_score"],
            "stress_level": res["stress_level"] ?? "low",
            "emotion": emotion.toLowerCase(), // Save and display the scanned face emotion
            "confidence": res["confidence"],
            "analysis": res["analysis"],
            "wellness_tip": res["wellness_tip"],
            "emergency": res["emergency"] == true,
          });
        });
        
        // Final scroll to bottom for AI response
        _scrollToBottom();
      }
    } catch (e) {
      setState(() => _loading = false);
      _showSnack("Connection error");
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildActionCard(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      width: MediaQuery.of(context).size.width * 0.65,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.arrow_forward_ios, size: 14, color: primaryColor),
            onPressed: () => _showSnack("Starting $title action...", isError: false),
          )
        ],
      ),
    );
  }

  String _getEmotionEmoji(dynamic emotion) {
    if (emotion == null) return "😐";
    final emo = emotion.toString().toLowerCase();
    const map = {
      "stress": "😓",
      "fatigue": "😴",
      "neutral": "😐",
      "happiness": "😊",
      "sadness": "😢",
      "anger": "😠",
      "fear": "😨",
      "surprise": "😲",
      "disgust": "🤢",
      "anxiety": "😟",
      "frustration": "😤",
      "calmness": "😌",
      "engagement": "🤔",
    };
    return map[emo] ?? "😐";
  }

  Widget _buildEmergencyAction(IconData icon, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7), fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _getStressEmoji(dynamic level) {
    if (level == null) return "🟢";
    final l = level.toString().toLowerCase();
    if (l == "high") return "🔴";
    if (l == "medium") return "🟡";
    return "🟢";
  }

  String _calculateStressLevel(dynamic score) {
    if (score == null) return "LOW";
    final s = score is num ? score.toInt() : int.tryParse(score.toString()) ?? 0;
    if (s <= 20) return "LOW";
    if (s <= 40) return "MILD";
    if (s <= 60) return "MODERATE";
    if (s <= 80) return "HIGH";
    return "SEVERE";
  }

  Color _getStressColor(dynamic level) {
    if (level == null) return Colors.green;
    final l = level.toString().toUpperCase();
    if (l == "LOW" || l == "CALM") return Colors.green;
    if (l == "MILD") return Colors.blue;
    if (l == "MODERATE") return Colors.orange;
    if (l == "HIGH") return Colors.red;
    if (l == "SEVERE") return Colors.red[900] ?? Colors.red;
    return Colors.green;
  }

  // 🎤 VOICE INPUT (NEW: WAVEFORM PROCESSING)
  Future<void> _voiceInput() async {
    if (_listening) {
      stopWebRecording();
      setState(() => _listening = false);
      return;
    }

    startWebRecording(
      onStart: () {
        setState(() => _listening = true);
        _showSnack("Recording voice...", isError: false);
      },
      onStop: (bytes, url) {
        _handleAudioMessage(url, bytes);
      },
      onError: (error) {
        print("Recording error: $error");
        _showSnack("Could not start recording: $error");
        setState(() => _listening = false);
      },
    );
  }

  void _handleAudioMessage(String audioUrl, Uint8List bytes) {
    setState(() {
      _messages.add({
        "role": "user",
        "content": "Voice Message",
        "inputType": "voice",
        "audioUrl": audioUrl,
      });
    });
    _scrollToBottom();
    _sendAudioToBackend(bytes);
  }

  Future<void> _sendAudioToBackend(Uint8List bytes) async {
    setState(() => _loading = true);
    try {
      final token = await ChatService.getFreshFirebaseToken();
      
      // 2. Prepare Multipart Request
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/audio/analyze'
        '?ghost_mode=$_ghostMode'
        '&session_id=$_currentSessionId'
      );
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'voice_message.webm',
        ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode != 200) {
        throw Exception("Backend error: ${response.statusCode}");
      }

      final data = jsonDecode(response.body);
      print("AUDIO API RESPONSE: $data");

      setState(() {
        _loading = false;
        
        // Update the user's voice message with the transcription
        if (_messages.isNotEmpty && _messages.last["role"] == "user" && _messages.last["inputType"] == "voice") {
          _messages.last["content"] = data["transcription"] ?? "Voice Message";
          _messages.last["masked_text"] = data["masked_text"] ?? data["transcription"];
        }
        
        _messages.add({
          "role": "assistant",
          "content": data["ai_response"] ?? "I've analyzed your voice message.",
          "emotion": data["emotion"] ?? data["voice_emotion"] ?? "neutral",
          "stress_level": _calculateStressLevel(data["stress_score"] ?? data["burnout_score"]),
          "stress_score": data["stress_score"] ?? data["burnout_score"],
          "analysis": data["analysis"] ?? "",
          "wellness_tip": data["wellness_tip"] ?? "",
          "emergency": data["stress_score"] != null && data["stress_score"] >= 80,
          "audio_features": data["audio_features"],
        });
      });
      _scrollToBottom();
      
    } catch (e) {
      print("Audio Upload Error: $e");
      _showSnack("Failed to process voice message");
      setState(() => _loading = false);
    }
  }

  // 🔒 PRIVACY LOCK
  void _togglePrivacyLock() {
    if (_pinCode == null) {
      // Set new PIN
      _showPinDialog(title: "Set Privacy PIN", isSetup: true);
    } else if (_isLocked) {
      // Unlock
      _showPinDialog(title: "Enter PIN to Unlock", isSetup: false);
    } else {
      // Lock
      setState(() => _isLocked = true);
      _showSnack("Privacy Lock Activated", isError: false);
    }
  }

  void _showPinDialog({required String title, required bool isSetup}) {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text(title, style: TextStyle(color: textColor)),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: "4-digit PIN",
            hintStyle: const TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: primaryColor)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              final pin = pinCtrl.text.trim();
              if (pin.length != 4) {
                _showSnack("PIN must be 4 digits");
                return;
              }
              Navigator.pop(ctx);
              setState(() {
                if (isSetup) {
                  _pinCode = pin;
                  _isLocked = true;
                  _showSnack("Privacy PIN Set & Locked", isError: false);
                } else {
                  if (pin == _pinCode) {
                    _isLocked = false;
                    _showSnack("History Unlocked", isError: false);
                  } else {
                    _showSnack("Incorrect PIN");
                  }
                }
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            child: Text(isSetup ? "Save PIN" : "Unlock", style: const TextStyle(color: Colors.white)),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: surfaceColor.withOpacity(0.7),
              elevation: 0,
              centerTitle: false,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "StressCare 💙",
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    _isLocked ? "Privacy Locked" : "Emotional Wellness",
                    style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 12),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.person_outline_rounded, color: primaryColor),
                  onPressed: () => Navigator.pushNamed(context, '/profile'),
                ),
                IconButton(
                  icon: Icon(Icons.bar_chart_rounded, color: primaryColor),
                  onPressed: () => Navigator.pushNamed(context, '/usage_patterns'),
                ),
                IconButton(
                  icon: Icon(
                    _ghostMode ? Icons.visibility_off_rounded : Icons.visibility_rounded, 
                    color: primaryColor,
                  ),
                  onPressed: () => _toggleGhostMode(!_ghostMode),
                ),
              ],
            ),
          ),
        ),
      ),
      drawer: _buildModernDrawer(),
      body: Stack(
        children: [
          // 🌈 Mesh Background
          const _PremiumBackground(),
          
          Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + 70),
              
              if (_messages.isNotEmpty && _messages.any((m) => m["emergency"] == true))
                _buildEmergencyBanner(),
                
              Expanded(
                child: _messages.isEmpty ? _buildWelcomeState() : _buildMessageList(),
              ),
              
              if (_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: primaryColor.withOpacity(0.1), blurRadius: 10)
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            "StressCare is thinking...",
                            style: TextStyle(color: primaryColor, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              
              _buildModernInputBar(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade400, Colors.red.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.security_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "High emotional risk detected. We're here for you.",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            onPressed: () => setState(() {
              for (var m in _messages) m["emergency"] = false;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeState() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryColor.withOpacity(0.1), primaryColor.withOpacity(0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: primaryColor.withOpacity(0.1), blurRadius: 40, spreadRadius: 10),
                  ],
                ),
                child: Icon(Icons.favorite_rounded, size: 80, color: primaryColor),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              "I'm here for you",
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textColor, letterSpacing: -1),
            ),
            const SizedBox(height: 12),
            Text(
              "How are you feeling today, Sagar?",
              style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 18, fontWeight: FontWeight.w500),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard(IconData icon, String text, [VoidCallback? onTap]) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: surfaceColor.withOpacity(0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: primaryColor, size: 28),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) {
        final msg = _messages[i];
        final isUser = msg["role"] == "user";
        return _buildModernMessageBubble(msg, isUser);
      },
    );
  }

  Widget _buildModernMessageBubble(Map<String, dynamic> msg, bool isUser) {
    final Color stressColor = isUser ? Colors.transparent : _getStressColor(_calculateStressLevel(msg["stress_score"]));
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
              decoration: BoxDecoration(
                gradient: isUser 
                  ? LinearGradient(
                      colors: [primaryColor, primaryColor.withBlue(255)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
                color: isUser ? null : surfaceColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(24),
                  topRight: const Radius.circular(24),
                  bottomLeft: Radius.circular(isUser ? 24 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isUser ? primaryColor.withOpacity(0.2) : stressColor.withOpacity(0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: isUser ? null : Border.all(color: stressColor.withOpacity(0.3), width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isUser) _buildAIBubbleHeader(msg),
                    
                    if (msg["inputType"] == "voice" && msg["audioUrl"] != null)
                      Column(
                        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          buildWaveformPlayer(msg["audioUrl"], primaryColor, surfaceColor),
                          const SizedBox(height: 8),
                          Text(
                            msg["content"] == "Voice Message" ? "Transcribing..." : '"${msg["content"]}"',
                            style: TextStyle(
                              color: isUser ? Colors.white.withOpacity(0.9) : textColor.withOpacity(0.8),
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        msg["content"],
                        style: TextStyle(
                          color: isUser ? Colors.white : textColor,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      
                    if (!isUser) ...[
                      if (msg["analysis"] != null && msg["analysis"].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Text(
                            "Analysis: ${msg["analysis"]}",
                            style: TextStyle(
                              color: textColor.withOpacity(0.6),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      _buildStressIndicator(msg),
                      if (msg["audio_features"] != null)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: primaryColor.withOpacity(0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Vocal Analysis Metrics", style: TextStyle(color: primaryColor, fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildAudioMetric("Energy", "${(msg["audio_features"]["energy"] * 100).toStringAsFixed(1)}%"),
                                  _buildAudioMetric("Pitch Var", "${msg["audio_features"]["pitch_variation"].toStringAsFixed(2)}"),
                                  _buildAudioMetric("Pace", "${msg["audio_features"]["speech_rate"].toStringAsFixed(0)} bpm"),
                                ],
                              ),
                            ],
                          ),
                        ),
                      if (msg["wellness_tip"] != null && msg["wellness_tip"].toString().isNotEmpty)
                        _buildAIsuggestion(msg["wellness_tip"]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildAIBubbleHeader(Map<String, dynamic> msg) {
    final color = _getStressColor(_calculateStressLevel(msg["stress_score"]));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Text(_getEmotionEmoji(msg["emotion"]), style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(
                  msg["emotion"]?.toString().toUpperCase() ?? "NEUTRAL",
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "Stress: ${_calculateStressLevel(msg["stress_score"])}",
            style: TextStyle(color: textColor.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStressIndicator(Map<String, dynamic> msg) {
    if (msg["stress_score"] == null) return const SizedBox();
    final color = _getStressColor(_calculateStressLevel(msg["stress_score"]));
    final score = msg["stress_score"] is num ? (msg["stress_score"] as num).toInt() : 0;
    
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Stress Score", style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w600)),
              Text("$score", style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                height: 6,
                width: (MediaQuery.of(context).size.width * 0.6) * (score / 100.0),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.4), blurRadius: 4, spreadRadius: 1),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAIsuggestion(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, size: 18, color: primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernInputBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: surfaceColor.withOpacity(0.8),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
              ],
            ),
            child: Row(
              children: [
                _buildInputIconButton(Icons.camera_alt_rounded, _openCamera),
                _buildInputIconButton(
                  _listening ? Icons.mic_rounded : Icons.mic_none_rounded, 
                  _voiceInput,
                  color: _listening ? Colors.red : primaryColor,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _listening 
                    ? _buildRecordingAnimation()
                    : TextField(
                        controller: _msgCtrl,
                        style: TextStyle(color: textColor, fontSize: 15),
                        decoration: const InputDecoration(
                          hintText: "How can I support you?",
                          hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _listening ? _voiceInput : _sendMessage,
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _listening 
                            ? [Colors.redAccent, Colors.red] 
                            : [primaryColor, primaryColor.withBlue(255)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: (_listening ? Colors.red : primaryColor).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Icon(_listening ? Icons.stop_rounded : Icons.arrow_upward_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingAnimation() {
    return const _RecordingWaveform();
  }

  Widget _buildInputIconButton(IconData icon, VoidCallback onTap, {Color? color}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color ?? textColor.withOpacity(0.6), size: 22),
        ),
      ),
    );
  }

  Widget _buildModernDrawer() {
    return Drawer(
      backgroundColor: surfaceColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
            width: double.infinity,
            color: primaryColor.withOpacity(0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("STRESSCARE", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12, color: AppColors.primary)),
                const SizedBox(height: 8),
                Text("Health & Wellness", style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          
          // 👻 GHOST MODE INDICATOR (Inside Sidebar)
          if (_ghostMode)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Text("👻", style: TextStyle(fontSize: 20)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Ghost Mode is ON. Messages will not be saved.",
                      style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                _buildDrawerItem(Icons.add_circle_outline_rounded, "New Session", () {
                  setState(() {
                    _messages = [];
                    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
                  });
                  Navigator.pop(context);
                }, color: primaryColor),
                
                _buildDrawerItem(Icons.history_rounded, "Session History", () {
                  Navigator.pop(context); // Close drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SessionHistoryScreen(
                        isGhostMode: _ghostMode,
                        onSessionSelected: (sessionId, messages) {
                          setState(() {
                            _currentSessionId = sessionId;
                            _messages = List<Map<String, dynamic>>.from(messages);
                          });
                          _scrollToBottom();
                        },
                      ),
                    ),
                  );
                }),
                  
                const Divider(indent: 24, endIndent: 24, height: 32),
                
                _buildDrawerItem(
                  _ghostMode ? Icons.visibility_off_rounded : Icons.visibility_rounded, 
                  _ghostMode ? "Ghost Mode: ON" : "Ghost Mode: OFF", 
                  () {
                    _toggleGhostMode(!_ghostMode);
                  }
                ),
              ],
            ),
          ),
          

        ],
      ),
    );
  }

  Widget _buildLockedHistoryState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_person_rounded, size: 32, color: Colors.grey),
          const SizedBox(height: 12),
          const Text(
            "History Locked",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() => _isLocked = false);
              _saveSettings();
            },
            child: const Text("Tap to Unlock", style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? textColor.withOpacity(0.7), size: 22),
      title: Text(title, style: TextStyle(color: color ?? textColor, fontWeight: FontWeight.w600, fontSize: 15)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }

  // Note: Replace call to _buildWaveformMessage with:
  // buildWaveformPlayer(msg["audioUrl"], primaryColor, surfaceColor)
}

class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -100,
          right: -100,
          child: _BlurBlob(color: AppColors.primary.withOpacity(0.08), size: 400),
        ),
        Positioned(
          bottom: 100,
          left: -150,
          child: _BlurBlob(color: AppColors.secondary.withOpacity(0.08), size: 500),
        ),
        Positioned(
          top: 300,
          left: 100,
          child: _BlurBlob(color: AppColors.primary.withOpacity(0.04), size: 300),
        ),
      ],
    );
  }
}

class _BlurBlob extends StatelessWidget {
  final Color color;
  final double size;

  const _BlurBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: const SizedBox(),
      ),
    );
  }
}

class _RecordingWaveform extends StatefulWidget {
  const _RecordingWaveform({Key? key}) : super(key: key);

  @override
  State<_RecordingWaveform> createState() => _RecordingWaveformState();
}

class _RecordingWaveformState extends State<_RecordingWaveform> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const Text("Recording...", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            ...List.generate(12, (index) {
              return TweenAnimationBuilder<double>(
                key: ValueKey(index),
                tween: Tween<double>(begin: 0.1, end: math.Random().nextDouble() * 0.8 + 0.2),
                duration: Duration(milliseconds: 200 + math.Random().nextInt(300)),
                curve: Curves.easeInOut,
                builder: (context, value, child) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 3,
                    height: 30 * value,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                },
                onEnd: () {
                  if (mounted) {
                    setState(() {});
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}