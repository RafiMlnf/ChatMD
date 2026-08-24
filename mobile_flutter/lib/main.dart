import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'crypto_helper.dart';

void main() {
  runApp(const ChatMDApp());
}

class ChatMDApp extends StatelessWidget {
  const ChatMDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChatMD Mobile',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardColor: const Color(0xFF1E293B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const ConnectScreen(),
    );
  }
}

// ─── CONNECT SCREEN ───
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _usernameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: "8765");
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _usernameController.text = prefs.getString('chatmd_username') ?? '';
      _ipController.text = prefs.getString('chatmd_ip') ?? '';
    });
  }

  Future<void> _connect() async {
    final username = _usernameController.text.trim();
    final ip = _ipController.text.trim();
    final port = _portController.text.trim();

    if (username.isEmpty || ip.isEmpty) {
      setState(() => _errorMessage = "Username dan IP Server PC wajib diisi!");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chatmd_username', username);
    await prefs.setString('chatmd_ip', ip);

    final wsUrl = Uri.parse('ws://$ip:$port');

    try {
      final channel = WebSocketChannel.connect(wsUrl);
      channel.sink.add(jsonEncode({"type": "register", "username": username}));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MainChatScreen(
            username: username,
            serverIp: ip,
            channel: channel,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Gagal terhubung ke $wsUrl: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(28.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF334155)),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 10))
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF60A5FA), Color(0xFFA855F7)],
                  ).createShader(bounds),
                  child: const Text(
                    'ChatMD Mobile',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Volatile Intranet Chat (Dart Client)',
                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Pengguna (Username)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'IP Server PC',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.computer),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port WebSocket',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.settings_input_component),
                  ),
                ),
                const SizedBox(height: 20),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _connect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Hubungkan ke PC', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── MAIN CHAT & CONTACTS SCREEN ───
class MainChatScreen extends StatefulWidget {
  final String username;
  final String serverIp;
  final WebSocketChannel channel;

  const MainChatScreen({
    super.key,
    required this.username,
    required this.serverIp,
    required this.channel,
  });

  @override
  State<MainChatScreen> createState() => _MainChatScreenState();
}

class _MainChatScreenState extends State<MainChatScreen> {
  List<String> _userList = [];
  String? _activePartner;
  final Map<String, List<Map<String, String>>> _histories = {};
  final Map<String, int> _unread = {};
  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.channel.stream.listen((raw) {
      try {
        final data = jsonDecode(raw.toString());
        final type = data['type'];

        if (type == 'user_list') {
          final users = List<String>.from(data['users']);
          setState(() {
            _userList = users.where((u) => u != widget.username).toList();
          });
        } else if (type == 'message') {
          _handleIncomingMessage(data['sender'], data['payload']);
        }
      } catch (_) {}
    });
  }

  void _handleIncomingMessage(String sender, String payloadHex) {
    final decrypted = CryptoHelper.decrypt(payloadHex);
    final now = TimeOfDay.now().format(context);

    setState(() {
      _histories.putIfAbsent(sender, () => []);
      _histories[sender]!.add({
        'sender': sender,
        'text': decrypted,
        'time': now,
      });

      if (_activePartner != sender) {
        _unread[sender] = (_unread[sender] ?? 0) + 1;
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty || _activePartner == null) return;

    final encryptedHex = CryptoHelper.encrypt(text);
    final payload = jsonEncode({
      'type': 'message',
      'target': _activePartner,
      'payload': encryptedHex,
    });

    widget.channel.sink.add(payload);

    final now = TimeOfDay.now().format(context);
    setState(() {
      _histories.putIfAbsent(_activePartner!, () => []);
      _histories[_activePartner!]!.add({
        'sender': widget.username,
        'text': text,
        'time': now,
      });
      _messageController.clear();
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      final fileMsg = "[FILE: ${file.name}] (${(file.size / 1024).toStringAsFixed(1)} KB)";
      _messageController.text = fileMsg;
      _sendMessage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(_activePartner == null ? 'ChatMD — Kontak' : _activePartner!),
        leading: _activePartner != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _activePartner = null),
              )
            : null,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(radius: 4, backgroundColor: Colors.green),
                    const SizedBox(width: 6),
                    Text(widget.username, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
      body: _activePartner == null ? _buildContactsView() : _buildChatView(),
    );
  }

  Widget _buildContactsView() {
    if (_userList.isEmpty) {
      return const Center(
        child: Text('Belum ada pengguna lain yang online di Intranet', style: TextStyle(color: Color(0xFF94A3B8))),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _userList.length,
      itemBuilder: (context, index) {
        final user = _userList[index];
        final unread = _unread[user] ?? 0;

        return Card(
          color: const Color(0xFF1E293B),
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF3B82F6),
              child: Text(user[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            title: Text(user, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: unread > 0
                ? CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.blue,
                    child: Text('$unread', style: const TextStyle(fontSize: 12, color: Colors.white)),
                  )
                : null,
            onTap: () {
              setState(() {
                _activePartner = user;
                _unread[user] = 0;
              });
            },
          ),
        );
      },
    );
  }

  Widget _buildChatView() {
    final messages = _histories[_activePartner] ?? [];

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final m = messages[index];
              final isMe = m['sender'] == widget.username;

              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                      bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(m['text'] ?? '', style: const TextStyle(fontSize: 15, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(m['time'] ?? '', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          color: const Color(0xFF1E293B),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.attach_file), onPressed: _pickFile),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Tulis pesan...',
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              IconButton(icon: const Icon(Icons.send, color: Color(0xFF3B82F6)), onPressed: _sendMessage),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    widget.channel.sink.close();
    super.dispose();
  }
}
