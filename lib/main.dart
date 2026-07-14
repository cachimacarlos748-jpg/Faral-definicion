import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'config/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.assertConfigured();
  
  final databasesPath = await getDatabasesPath();
  final path = p.join(databasesPath, 'faral_ia.db');
  
  final database = await openDatabase(
    path,
    onCreate: (db, version) {
      return db.execute(
        'CREATE TABLE chats(id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT, isUser INTEGER, timestamp TEXT, imagePath TEXT, audioPath TEXT)',
      );
    },
    version: 1,
  );

  runApp(FaralAIApp(database: database));
}

class FaralAIApp extends StatelessWidget {
  final Database database;
  const FaralAIApp({super.key, required this.database});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Faral IA',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F13),
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFAB64FF),
          secondary: Color(0xFF6B4EFF),
          surface: Color(0xFF1E1E24),
          onSurface: Colors.white,
          outline: Color(0xFF2E2E38),
        ),
      ),
      home: LoginScreen(database: database),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final Database database;
  const LoginScreen({super.key, required this.database});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isSigningIn = false;

  Future<void> _handleSignIn() async {
    setState(() => _isSigningIn = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final account = await googleSignIn.signIn();
      if (!mounted) return;
      if (account != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => MainDashboard(
              database: widget.database,
              userName: account.displayName ?? "Estudiante",
              userEmail: account.email,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudo iniciar sesión: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFAB64FF), Color(0xFF6B4EFF)],
                  ),
                ),
                child: const Icon(CupertinoIcons.sparkles, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 24),
              const Text(
                "Faral IA",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                "Tu asistente de estudio, incluso sin conexión.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.5)),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSigningIn ? null : _handleSignIn,
                  icon: _isSigningIn
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                        )
                      : const Icon(CupertinoIcons.person_crop_circle, size: 20),
                  label: Text(_isSigningIn ? "Conectando..." : "Continuar con Google"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum FaralModel {
  faral35Flash,
  faral31Lite,
  faralLocalMini,
  faralLocalPro,
}

class ChatMessage {
  final int? id;
  final String text;
  final bool isUser;
  final String? audioPath;
  final String? filePath;
  final String? base64Image;
  final DateTime timestamp;

  ChatMessage({
    this.id,
    required this.text,
    required this.isUser,
    this.audioPath,
    this.filePath,
    this.base64Image,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'isUser': isUser ? 1 : 0,
      'timestamp': timestamp.toIso8601String(),
      'imagePath': filePath,
      'audioPath': audioPath,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      text: map['text'],
      isUser: map['isUser'] == 1,
      timestamp: DateTime.parse(map['timestamp']),
      filePath: map['imagePath'],
      audioPath: map['audioPath'],
    );
  }
}

class MainDashboard extends StatefulWidget {
  final Database database;
  final String userName;
  final String userEmail;

  const MainDashboard({
    super.key,
    required this.database,
    required this.userName,
    required this.userEmail,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _orbController;
  
  FaralModel _selectedModel = FaralModel.faral35Flash;
  bool _isOfflineMode = false;
  bool _isLowEndDevice = true; 
  bool _isRecording = false;
  bool _isProcessing = false;

  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _localAudioPath;

  final List<ChatMessage> _messages = [];
  final List<String> _recentChats = [
    "Solución Error Gradle Android Flutter",
    "Aclaración de Pago y Facturación",
    "El final de Brightburn explicado",
    "Terremotos y Aviación: Seguridad",
    "KaliDroid: Realidad vs. Hype",
  ];

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _loadChatHistory();
  }

  @override
  void dispose() {
    _orbController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    final List<Map<String, dynamic>> maps = await widget.database.query('chats');
    if (maps.isNotEmpty) {
      setState(() {
        _messages.addAll(maps.map((m) => ChatMessage.fromMap(m)).toList());
      });
    } else {
      setState(() {
        _messages.add(ChatMessage(
          text: "¡Hola! Bienvenido a Faral IA. Tu entorno está listo y conectado a Gemini 3.5. ¿Qué deseas analizar o diseñar hoy?",
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    }
    _scrollToBottom();
  }

  Future<void> _saveMessage(ChatMessage message) async {
    await widget.database.insert(
      'chats',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _callGeminiApi(String prompt, {String? base64Img, String? mimeType}) async {
    setState(() {
      _isProcessing = true;
    });

    final modelEndpoint = _selectedModel == FaralModel.faral31Lite 
        ? 'gemini-3.1-flash-lite' 
        : 'gemini-3.5-flash';

    final url = 'https://generativelanguage.googleapis.com/v1beta/models/$modelEndpoint:generateContent?key=${AppConfig.geminiApiKey}';

    try {
      final List<Map<String, dynamic>> parts = [];
      
      if (base64Img != null && mimeType != null) {
        parts.add({
          "inlineData": {
            "mimeType": mimeType,
            "data": base64Img
          }
        });
      }
      
      parts.add({"text": prompt});

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": parts
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String textResponse = data['candidates'][0]['content']['parts'][0]['text'] ?? "No se recibió respuesta del servidor.";
        
        final aiMessage = ChatMessage(
          text: textResponse,
          isUser: false,
          timestamp: DateTime.now(),
        );

        setState(() {
          _messages.add(aiMessage);
        });
        await _saveMessage(aiMessage);
      } else {
        _addErrorMessage("Error de comunicación con Faral Core (${response.statusCode}).");
      }
    } catch (e) {
      _addErrorMessage("Error de conexión: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _callBananaImageApi(String prompt) async {
    setState(() {
      _isProcessing = true;
    });

    final url = 'https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict?key=${AppConfig.geminiApiKey}';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "instances": [
            {"prompt": prompt}
          ],
          "parameters": {
            "sampleCount": 1,
            "aspectRatio": "1:1",
            "outputMimeType": "image/jpeg"
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String base64Image = data['predictions'][0]['bytesBase64Encoded'];
        
        final directory = await Directory.systemTemp.createTemp();
        final filePath = '${directory.path}/faral_art_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(filePath);
        await file.writeAsBytes(base64Decode(base64Image));

        final aiMessage = ChatMessage(
          text: "🎨 ¡Tu obra ha sido procesada con éxito por Faral Art (Nano Banana 2)!",
          isUser: false,
          filePath: filePath,
          timestamp: DateTime.now(),
        );

        setState(() {
          _messages.add(aiMessage);
        });
        await _saveMessage(aiMessage);
      } else {
        _addErrorMessage("Faral Art: Límite del servidor excedido. Intenta cambiar de prompt.");
      }
    } catch (e) {
      _addErrorMessage("Error al generar imagen: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
      _scrollToBottom();
    }
  }

  void _addErrorMessage(String error) {
    final errMsg = ChatMessage(
      text: error,
      isUser: false,
      timestamp: DateTime.now(),
    );
    setState(() {
      _messages.add(errMsg);
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _localAudioPath == null) return;

    _messageController.clear();
    final userMsg = ChatMessage(
      text: text,
      isUser: true,
      audioPath: _localAudioPath,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _localAudioPath = null;
    });

    await _saveMessage(userMsg);
    _scrollToBottom();

    if (_isOfflineMode) {
      await Future.delayed(const Duration(milliseconds: 700));
      final offlineReply = ChatMessage(
        text: "Faral Offline (Mini):\n\nEstás en modo local y privado.",
        isUser: false,
        timestamp: DateTime.now(),
      );
      setState(() {
        _messages.add(offlineReply);
      });
      await _saveMessage(offlineReply);
      _scrollToBottom();
    } else {
      if (text.toLowerCase().contains("crea una imagen") || text.toLowerCase().contains("dibuja")) {
        _callBananaImageApi(text);
      } else {
        _callGeminiApi(text);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickAndAnalyzeImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final bytes = await File(path).readAsBytes();
      final base64Image = base64Encode(bytes);
      final mimeType = 'image/${p.extension(path).replaceFirst('.', '')}';

      final userMsg = ChatMessage(
        text: "Analizando imagen seleccionada...",
        isUser: true,
        filePath: path,
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.add(userMsg);
      });
      await _saveMessage(userMsg);
      _scrollToBottom();

      _callGeminiApi(
        "Analiza detalladamente esta foto.",
        base64Img: base64Image,
        mimeType: mimeType,
      );
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _localAudioPath = path;
      });
      _sendMessage(); 
    } else {
      final hasPermission = await _audioRecorder.hasPermission();
      if (hasPermission) {
        final directory = await Directory.systemTemp.createTemp();
        final path = '${directory.path}/faral_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() {
          _isRecording = true;
        });
      }
    }
  }

  String _getModelDisplayName(FaralModel model) {
    switch (model) {
      case FaralModel.faral35Flash: return "Faral 3.5 Flash";
      case FaralModel.faral31Lite: return "Faral 3.1 Lite";
      case FaralModel.faralLocalMini: return "Faral Local Mini";
      case FaralModel.faralLocalPro: return "Faral Local Pro";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildCustomSidebar(),
      body: Stack(
        children: [
          Container(color: const Color(0xFF0C0C0F)),
          AnimatedBuilder(
            animation: _orbController,
            builder: (context, child) {
              return Stack(
                children: [
                  Positioned(
                    top: -120 + (60 * math.sin(_orbController.value * 2 * math.pi)),
                    left: -120 + (60 * math.cos(_orbController.value * 2 * math.pi)),
                    child: Container(
                      width: 320,
                      height: 320,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF6B4EFF).withOpacity(0.18),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -80 + (50 * math.cos(_orbController.value * 2 * math.pi)),
                    right: -80 + (70 * math.sin(_orbController.value * 2 * math.pi)),
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFAB64FF).withOpacity(0.15),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ColorFilter.mode(
                Colors.black.withOpacity(0.2),
                BlendMode.srcOver,
              ),
              child: Container(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopNavigationBar(),
                _buildConnectionBanner(),
                Expanded(child: _buildChatArea()),
                if (_isProcessing) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: SpinKitThreeBounce(
                      color: Color(0xFFAB64FF),
                      size: 24.0,
                    ),
                  )
                ],
                _buildInteractiveInputBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopNavigationBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(CupertinoIcons.bars, color: Colors.white),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          GestureDetector(
            onTap: _showModelSelectorDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Text(
                    _getModelDisplayName(_selectedModel),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 6),
                  const Icon(CupertinoIcons.chevron_down, size: 14, color: Colors.white60),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _isOfflineMode ? CupertinoIcons.wifi_slash : CupertinoIcons.wifi,
              color: _isOfflineMode ? Colors.orangeAccent : const Color(0xFFAB64FF),
            ),
            onPressed: () {
              setState(() {
                _isOfflineMode = !_isOfflineMode;
                if (_isOfflineMode) {
                  _selectedModel = FaralModel.faralLocalMini;
                } else {
                  _selectedModel = FaralModel.faral35Flash;
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionBanner() {
    if (!_isOfflineMode) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.orangeAccent.withOpacity(0.12),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 13, color: Colors.orangeAccent),
          SizedBox(width: 8),
          Text(
            "Modo Local Activo: Operando de forma 100% Offline",
            style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isUser = msg.isUser;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  margin: const EdgeInsets.only(right: 8, top: 4),
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF6B4EFF),
                  ),
                  child: const Icon(CupertinoIcons.sparkles, size: 14, color: Colors.white),
                ),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isUser 
                        ? const Color(0xFF2E2E38).withOpacity(0.7) 
                        : const Color(0xFF1E1E24).withOpacity(0.9),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
                      bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
                    ),
                    border: Border.all(
                      color: isUser ? Colors.white.withOpacity(0.04) : const Color(0xFFAB64FF).withOpacity(0.12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.filePath != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(msg.filePath!),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        msg.text,
                        style: const TextStyle(fontSize: 14.5, height: 1.4, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInteractiveInputBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F13),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.04))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(CupertinoIcons.paperclip, color: Colors.white.withOpacity(0.6)),
            onPressed: _pickAndAnalyzeImage,
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: TextField(
                controller: _messageController,
                maxLines: null,
                style: const TextStyle(color: Colors.white, fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: _isRecording ? "Grabando audio..." : "Pregunta a Faral IA...",
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onLongPress: _toggleVoiceRecording,
            onLongPressEnd: (_) => _toggleVoiceRecording(),
            child: FloatingActionButton.small(
              backgroundColor: _isRecording ? Colors.redAccent : const Color(0xFFAB64FF),
              onPressed: _sendMessage,
              child: Icon(
                _messageController.text.isNotEmpty 
                    ? CupertinoIcons.arrow_up 
                    : (_isRecording ? CupertinoIcons.stop : CupertinoIcons.mic),
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showModelSelectorDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text("Seleccionar Inteligencia", style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildModelOptionTile(
                    title: "Faral 3.5 Flash",
                    description: "Asistencia general ultra rápida (Gemini 3.5)",
                    model: FaralModel.faral35Flash,
                    isEnabled: !_isOfflineMode,
                    setDialogState: setDialogState,
                  ),
                  _buildModelOptionTile(
                    title: "Faral 3.1 Lite",
                    description: "Optimizada para respuestas concisas (Gemini 3.1)",
                    model: FaralModel.faral31Lite,
                    isEnabled: !_isOfflineMode,
                    setDialogState: setDialogState,
                  ),
                  const Divider(color: Colors.white12),
                  _buildModelOptionTile(
                    title: "Faral Local Mini",
                    description: "Ideal offline para gama básica (Gemma 2B)",
                    model: FaralModel.faralLocalMini,
                    isEnabled: true,
                    setDialogState: setDialogState,
                  ),
                  _buildModelOptionTile(
                    title: "Faral Local Pro",
                    description: "Modelo extendido local (Gama Alta)",
                    model: FaralModel.faralLocalPro,
                    isEnabled: !_isLowEndDevice, 
                    setDialogState: setDialogState,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModelOptionTile({
    required String title,
    required String description,
    required FaralModel model,
    required bool isEnabled,
    required StateSetter setDialogState,
  }) {
    final isSelected = _selectedModel == model;
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.4,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFFAB64FF) : Colors.white)),
        subtitle: Text(description, style: const TextStyle(fontSize: 12, color: Colors.white60)),
        trailing: isSelected 
            ? const Icon(CupertinoIcons.check_mark_circled_solid, color: Color(0xFFAB64FF)) 
            : (!isEnabled ? const Icon(CupertinoIcons.lock_fill, size: 16) : null),
        onTap: isEnabled
            ? () {
                setState(() {
                  _selectedModel = model;
                });
                Navigator.pop(context);
              }
            : null,
      ),
    );
  }

  Widget _buildCustomSidebar() {
    return Drawer(
      child: Container(
        color: const Color(0xFF121215),
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Colors.transparent),
              currentAccountPicture: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFAB64FF), Color(0xFF6B4EFF)],
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : "U",
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
              accountName: Text(widget.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: Text(widget.userEmail, style: TextStyle(color: Colors.white.withOpacity(0.5))),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.book, color: Color(0xFFAB64FF)),
              title: const Text("Mis Cuadernos", style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Badge(label: Text("3")),
              onTap: () {},
            ),
            const Divider(color: Colors.white12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Recientes", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
                  IconButton(
                    icon: const Icon(CupertinoIcons.add, size: 16, color: Colors.white54),
                    onPressed: () {
                      setState(() {
                        _messages.clear();
                        _messages.add(ChatMessage(
                          text: "¡Nueva conversación iniciada!",
                          isUser: false,
                          timestamp: DateTime.now(),
                        ));
                      });
                      Navigator.pop(context);
                    },
                  )
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _recentChats.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: const Icon(CupertinoIcons.chat_bubble_text, size: 18, color: Colors.white38),
                    title: Text(
                      _recentChats[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(CupertinoIcons.arrow_right_square, color: Colors.redAccent),
              title: const Text("Cerrar Sesión", style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                final GoogleSignIn googleSignIn = GoogleSignIn();
                await googleSignIn.signOut();
                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => LoginScreen(database: widget.database)),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
