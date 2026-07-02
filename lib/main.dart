import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode/barcode.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LabelPrinterApp());
}

class LabelPrinterApp extends StatelessWidget {
  const LabelPrinterApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal PDT Station',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        useMaterial3: true,
      ),
      home: const PermissionSplashScreen(),
    );
  }
}

class PermissionSplashScreen extends StatefulWidget {
  const PermissionSplashScreen({Key? key}) : super(key: key);
  @override
  State<PermissionSplashScreen> createState() => _PermissionSplashScreenState();
}

class _PermissionSplashScreenState extends State<PermissionSplashScreen> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkExistingPermissions();
  }

  Future<void> _checkExistingPermissions() async {
    bool btScan = await Permission.bluetoothScan.isGranted;
    bool btConnect = await Permission.bluetoothConnect.isGranted;
    bool location = await Permission.location.isGranted;

    if ((btScan && btConnect) || location) {
      _navigateToHome();
    } else {
      setState(() => _checking = false);
    }
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool btScan = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    bool btConnect = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    bool location = statuses[Permission.location]?.isGranted ?? false;

    if ((btScan && btConnect) || location) {
      _navigateToHome();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Hardware permissions required to use scanner."),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (BuildContext ctx) => const LabelPrinterHomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade900,
      body: Center(
        child: _checking
            ? const CircularProgressIndicator(color: Colors.white)
            : Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.white),
              const SizedBox(height: 24),
              const Text("Setup Required", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),
              const Text("This PDT requires Bluetooth and Location permissions to scan for and connect to your thermal printer hardware.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.white70, height: 1.5)),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: _requestPermissions,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text("Grant Permissions", style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(55), foregroundColor: Colors.blueGrey.shade900, backgroundColor: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SETTINGS PAGE
// ============================================================================
class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _printerMode = 'bluetooth';
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _apiController = TextEditingController();

  bool _isCheckingServer = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _printerMode = prefs.getString('printer_mode') ?? 'bluetooth';
      _ipController.text = prefs.getString('printer_ip') ?? '';
      _portController.text = prefs.getString('printer_port') ?? '9100';
      _apiController.text = prefs.getString('api_url') ?? 'http://192.168.1.76:3000';
    });
  }

  Future<void> _saveSettings() async {
    String apiUrl = _apiController.text.trim();
    if (apiUrl.endsWith('/')) apiUrl = apiUrl.substring(0, apiUrl.length - 1);

    setState(() {
      _isCheckingServer = true;
    });

    bool isReachable = false;

    try {
      final uri = Uri.parse(apiUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode != null) {
        isReachable = true;
      }
    } catch (e) {
      isReachable = false;
    }

    if (!mounted) return;

    setState(() {
      _isCheckingServer = false;
    });

    if (isReachable) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_mode', _printerMode);
      await prefs.setString('printer_ip', _ipController.text.trim());
      await prefs.setString('printer_port', _portController.text.trim());
      await prefs.setString('api_url', apiUrl);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Settings Saved! API Server is reachable ✅"),
          backgroundColor: Colors.green
      ));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Cannot reach server. Check the IP and ensure the Node.js app is running ❌"),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text("Database Server", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _apiController,
            decoration: const InputDecoration(labelText: 'Node.js API URL', border: OutlineInputBorder(), hintText: 'e.g. http://192.168.1.76:3000'),
            keyboardType: TextInputType.url,
          ),

          const Divider(height: 32),

          const Text("Printer Connection Mode", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          RadioListTile<String>(
            title: const Text("Via Bluetooth (Local)"),
            subtitle: const Text("Use Original TSPL protocol for Bluetooth printers."),
            value: 'bluetooth',
            groupValue: _printerMode,
            onChanged: (value) => setState(() => _printerMode = value!),
          ),
          RadioListTile<String>(
            title: const Text("Via Server (WiFi / LAN)"),
            subtitle: const Text("Use ESC/POS protocol directly to an IP address."),
            value: 'server',
            groupValue: _printerMode,
            onChanged: (value) => setState(() => _printerMode = value!),
          ),

          if (_printerMode == 'server') ...[
            const Divider(height: 32),
            const Text("Network Printer Configuration", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(labelText: 'Printer IP Address', border: OutlineInputBorder(), hintText: 'e.g. 192.168.1.100'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(labelText: 'Printer Port', border: OutlineInputBorder(), hintText: 'e.g. 9100'),
              keyboardType: TextInputType.number,
            ),
          ],

          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _isCheckingServer ? null : _saveSettings,
            icon: _isCheckingServer
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_isCheckingServer ? "CHECKING CONNECTION..." : "SAVE SETTINGS"),
            style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white
            ),
          )
        ],
      ),
    );
  }
}

// ============================================================================
// MAIN APPLICATION HOME PAGE
// ============================================================================
class LabelPrinterHomePage extends StatefulWidget {
  const LabelPrinterHomePage({Key? key}) : super(key: key);
  @override
  State<LabelPrinterHomePage> createState() => _LabelPrinterHomePageState();
}

class _LabelPrinterHomePageState extends State<LabelPrinterHomePage> {
  static const platform = MethodChannel('com.example.printer/bluetooth');

  // Network Settings
  String _printerMode = 'bluetooth';
  String _printerIp = '';
  String _printerPort = '';
  String _apiUrl = 'http://192.168.1.76:3000';

  // State Variables
  DateTime _targetDate = DateTime.now(); // Defaults to today
  String _lastScannedCode = '';

  List<Map<dynamic, dynamic>> _devices = [];
  Map<dynamic, dynamic>? _selectedDevice;
  bool _connected = false;
  bool _isScanning = false;
  bool _isLookingUp = false;

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  Map<String, dynamic>? _scannedItem;
  int _quantity = 1;

  String _labelFormat = 'was-now';
  String _labelSize = '76x51';

  @override
  void initState() {
    super.initState();
    platform.setMethodCallHandler(_handleNativeMethodCall);
    _loadNetworkSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocusNode.requestFocus();
    });
  }

  Future<void> _loadNetworkSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _printerMode = prefs.getString('printer_mode') ?? 'bluetooth';
      _printerIp = prefs.getString('printer_ip') ?? '';
      _printerPort = prefs.getString('printer_port') ?? '9100';
      _apiUrl = prefs.getString('api_url') ?? 'http://192.168.1.76:3000';
    });

    if (_printerMode == 'bluetooth') {
      _startInAppScan();
    }
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == "onDeviceFound") {
      final device = Map<dynamic, dynamic>.from(call.arguments);
      setState(() {
        if (!_devices.any((d) => d['address'] == device['address'])) {
          _devices.add(device);
        }
      });
    } else if (call.method == "onScanFinished") {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _startInAppScan() async {
    if (_isScanning) return;
    setState(() { _isScanning = true; _devices = []; _selectedDevice = null; });
    try {
      await platform.invokeMethod('startInAppScan');
    } on PlatformException catch (e) {
      debugPrint("Scan error: ${e.message}");
      setState(() => _isScanning = false);
    }
  }

  Future<void> _connectToPrinter() async {
    if (_selectedDevice == null) return;
    try {
      final bool success = await platform.invokeMethod('connectInApp', {'address': _selectedDevice!['address']});
      setState(() { _connected = success; });
    } catch (e) { debugPrint("Connection fail: $e"); }
  }

  Future<void> _disconnectPrinter() async {
    await platform.invokeMethod('disconnectInApp');
    setState(() { _connected = false; _selectedDevice = null; });
  }

  // ============================================================================
  // DATE PICKER LOGIC
  // ============================================================================
  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && picked != _targetDate) {
      setState(() {
        _targetDate = picked;
      });
      if (_lastScannedCode.isNotEmpty) {
        _handleItemLookup(_lastScannedCode);
      }
    }
  }

  // ============================================================================
  // NODE.JS API LOOKUP
  // ============================================================================
  Future<void> _handleItemLookup(String value) async {
    final cleanCode = value.trim();
    if (cleanCode.isEmpty) return;

    _lastScannedCode = cleanCode;

    setState(() {
      _isLookingUp = true;
      _scannedItem = null;
    });

    try {
      final formattedDate = _targetDate.toIso8601String().split('T')[0];
      final url = Uri.parse('$_apiUrl/api/lookup?sku=$cleanCode&targetDate=$formattedDate');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        setState(() {
          _scannedItem = {
            "id": data['sku'] ?? cleanCode,
            "name": data['article_name'] ?? "Unknown Name",
            "sku": data['sku'] ?? "N/A",
            "price": data['special_price'] != null ? data['special_price'].toString() : data['base_price'].toString(),
            "was_price": data['base_price']?.toString() ?? "0.00",
          };
          _quantity = 1;
        });
      } else if (response.statusCode == 404) {
        setState(() {
          _scannedItem = {
            "id": cleanCode,
            "name": "Item Not Found on Server",
            "sku": "N/A",
            "price": "0.00",
            "was_price": "0.00"
          };
          _quantity = 1;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Server Error: ${response.statusCode}"), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Network Error: Could not connect to API"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLookingUp = false);
      _inputController.clear();
      _inputFocusNode.unfocus();
    }
  }

  // ============================================================================
  // ESC/POS DIRECT TCP PRINTING
  // ============================================================================
  Future<void> _printViaServer(Uint8List monoBytes, int labelWidth, int labelHeight, int qty) async {
    if (_printerIp.isEmpty || _printerPort.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Error: Printer IP or Port is empty in Settings."), backgroundColor: Colors.red));
      return;
    }

    try {
      int port = int.parse(_printerPort);
      // Timeout is just for the initial connection
      Socket socket = await Socket.connect(_printerIp, port, timeout: const Duration(seconds: 5));

      int bytesPerLine = (labelWidth + 7) ~/ 8;

      // 1. Prepare Header
      List<int> header = [
        29, 118, 48, 0, // GS v 0 : Print Raster Image
        bytesPerLine % 256, bytesPerLine ~/ 256,
        labelHeight % 256, labelHeight ~/ 256
      ];

      // 2. Loop for copies
      for (int q = 0; q < qty; q++) {
        socket.add(header);

        // 🛑 THE FIX: Chunking the data.
        // We split the image bytes into 1KB chunks and add a tiny 5ms delay.
        // This prevents the printer's network memory buffer from filling up and dropping
        // packets when printing complex images (like the dense "was-now" format).
        int chunkSize = 1024;
        for (int i = 0; i < monoBytes.length; i += chunkSize) {
          int end = i + chunkSize;
          if (end > monoBytes.length) end = monoBytes.length;

          socket.add(monoBytes.sublist(i, end));
          await socket.flush(); // Push to OS
          await Future.delayed(const Duration(milliseconds: 5)); // Let the thermal head breathe
        }

        // 3. Form feed to next gap
        socket.add([29, 12]);
        await socket.flush();

        // Extra delay between physical labels to prevent roller jamming
        if (qty > 1) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      // Final delay to ensure the OS completes transmitting the last TCP packets over Wi-Fi
      await Future.delayed(const Duration(milliseconds: 500));

      // Forcefully terminate to clear any TIME_WAIT state issues
      await socket.close();
      socket.destroy();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Sent ESC/POS to Printer successfully!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("WiFi Print Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _generateAndPrintGraphics() async {
    if (_scannedItem == null) return;
    if (_printerMode == 'bluetooth' && !_connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please connect to a Bluetooth printer first."), backgroundColor: Colors.red));
      return;
    }

    final int labelWidth = _labelSize == '76x51' ? 576 : (_labelSize == '50x38' ? 400 : 480);
    final int labelHeight = _labelSize == '76x51' ? 408 : (_labelSize == '50x38' ? 304 : 232);

    final int widthMm = _labelSize == '76x51' ? 76 : (_labelSize == '50x38' ? 50 : 60);
    final int heightMm = _labelSize == '76x51' ? 51 : (_labelSize == '50x38' ? 38 : 29);
    final int gapMm = _labelSize == '76x51' ? 3 : 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, labelWidth.toDouble(), labelHeight.toDouble()), bgPaint);

    final linePaint = Paint()..color = Colors.black..strokeWidth = 2.0;
    final crossPaint = Paint()..color = Colors.black..strokeWidth = 1.5;

    // ====================================================================
    // 76x51 MM STANDARD LABEL
    // ====================================================================
    if (_labelSize == '76x51') {
      if (_labelFormat == 'was-now') {
        _drawCenteredText(canvas, _scannedItem!['sku'].toString(), 40, labelWidth, fontSize: 24, fontWeight: FontWeight.bold);
        _drawCenteredText(canvas, _scannedItem!['name'].toString(), 80, labelWidth, fontSize: 22);
        canvas.drawLine(const Offset(20, 125), const Offset(556, 125), linePaint);

        _drawLeftText(canvas, "WAS  -", 130, 145, fontSize: 24);
        _drawCenteredText(canvas, "QR ${_scannedItem!['was_price']}", 145, labelWidth, fontSize: 24);
        _drawRightText(canvas, "قبل", labelWidth - 150, 145, fontSize: 24);

        _drawDashedLine(canvas, const Offset(35, 135), const Offset(541, 175), crossPaint);
        _drawDashedLine(canvas, const Offset(35, 175), const Offset(541, 135), crossPaint);

        canvas.drawLine(const Offset(20, 190), const Offset(556, 190), linePaint);

        _drawLeftText(canvas, "NOW  -", 130, 210, fontSize: 24);
        _drawCenteredText(canvas, "QR ${_scannedItem!['price']}", 205, labelWidth, fontSize: 36, fontWeight: FontWeight.bold);
        _drawRightText(canvas, "بعد", labelWidth - 150, 210, fontSize: 24);

        canvas.drawLine(const Offset(20, 260), const Offset(556, 260), linePaint);

        _drawCenteredText(canvas, "SKU: ${_scannedItem!['id']}", 270, labelWidth, fontSize: 18);
        _drawRealBarcode(canvas, _scannedItem!['id'].toString(), 295, labelWidth, 60);
      } else {
        _drawCenteredText(canvas, _scannedItem!['sku'].toString(), 50, labelWidth, fontSize: 24, fontWeight: FontWeight.bold);
        _drawCenteredText(canvas, _scannedItem!['name'].toString(), 100, labelWidth, fontSize: 22);
        canvas.drawLine(const Offset(20, 145), const Offset(556, 145), linePaint);
        _drawCenteredText(canvas, "QR ${_scannedItem!['price']}", 170, labelWidth, fontSize: 40, fontWeight: FontWeight.bold);
        canvas.drawLine(const Offset(20, 235), const Offset(556, 235), linePaint);

        _drawCenteredText(canvas, "SKU: ${_scannedItem!['id']}", 245, labelWidth, fontSize: 18);
        _drawRealBarcode(canvas, _scannedItem!['id'].toString(), 275, labelWidth, 60);
      }
    }
    // ====================================================================
    // 50x38 MM MEDIUM LABEL
    // ====================================================================
    else if (_labelSize == '50x38') {
      if (_labelFormat == 'was-now') {
        _drawCenteredText(canvas, _scannedItem!['sku'].toString(), 15, labelWidth, fontSize: 18, fontWeight: FontWeight.bold);
        _drawCenteredText(canvas, _scannedItem!['name'].toString(), 45, labelWidth, fontSize: 14);
        canvas.drawLine(const Offset(15, 70), const Offset(385, 70), linePaint);

        _drawLeftText(canvas, "WAS  -", 70, 80, fontSize: 14);
        _drawCenteredText(canvas, "QR ${_scannedItem!['was_price']}", 80, labelWidth, fontSize: 14);
        _drawRightText(canvas, "قبل", labelWidth - 80, 75, fontSize: 18, fontWeight: FontWeight.bold);

        _drawDashedLine(canvas, const Offset(15, 76), const Offset(385, 96), crossPaint);
        _drawDashedLine(canvas, const Offset(15, 96), const Offset(385, 76), crossPaint);

        canvas.drawLine(const Offset(15, 105), const Offset(385, 105), linePaint);

        _drawLeftText(canvas, "NOW  -", 70, 115, fontSize: 14);
        _drawCenteredText(canvas, "QR ${_scannedItem!['price']}", 110, labelWidth, fontSize: 24, fontWeight: FontWeight.bold);
        _drawRightText(canvas, "بعد", labelWidth - 80, 110, fontSize: 18, fontWeight: FontWeight.bold);

        canvas.drawLine(const Offset(15, 150), const Offset(385, 150), linePaint);

        _drawCenteredText(canvas, "SKU: ${_scannedItem!['id']}", 165, labelWidth, fontSize: 14);
        _drawRealBarcode(canvas, _scannedItem!['id'].toString(), 190, labelWidth, 50);
      } else {
        _drawCenteredText(canvas, _scannedItem!['sku'].toString(), 15, labelWidth, fontSize: 18, fontWeight: FontWeight.bold);
        _drawCenteredText(canvas, _scannedItem!['name'].toString(), 45, labelWidth, fontSize: 14);
        canvas.drawLine(const Offset(15, 75), const Offset(385, 75), linePaint);

        _drawCenteredText(canvas, "QR ${_scannedItem!['price']}", 105, labelWidth, fontSize: 32, fontWeight: FontWeight.bold);
        canvas.drawLine(const Offset(15, 155), const Offset(385, 155), linePaint);

        _drawCenteredText(canvas, "SKU: ${_scannedItem!['id']}", 170, labelWidth, fontSize: 14);
        _drawRealBarcode(canvas, _scannedItem!['id'].toString(), 195, labelWidth, 50);
      }
    }
    // ====================================================================
    // 60x29 MM SMALL LABEL
    // ====================================================================
    else {
      if (_labelFormat == 'was-now') {
        _drawCenteredText(canvas, _scannedItem!['sku'].toString(), 10, labelWidth, fontSize: 16, fontWeight: FontWeight.bold);
        _drawCenteredText(canvas, _scannedItem!['name'].toString(), 35, labelWidth, fontSize: 14);
        canvas.drawLine(const Offset(10, 55), const Offset(470, 55), linePaint);

        _drawLeftText(canvas, "WAS  -", 90, 62, fontSize: 14);
        _drawCenteredText(canvas, "QR ${_scannedItem!['was_price']}", 62, labelWidth, fontSize: 14);
        _drawRightText(canvas, "قبل", labelWidth - 100, 58, fontSize: 18, fontWeight: FontWeight.bold);

        _drawDashedLine(canvas, const Offset(15, 58), const Offset(465, 78), crossPaint);
        _drawDashedLine(canvas, const Offset(15, 78), const Offset(465, 58), crossPaint);

        canvas.drawLine(const Offset(10, 84), const Offset(470, 84), linePaint);

        _drawLeftText(canvas, "NOW  -", 90, 95, fontSize: 14);
        _drawCenteredText(canvas, "QR ${_scannedItem!['price']}", 90, labelWidth, fontSize: 22, fontWeight: FontWeight.bold);
        _drawRightText(canvas, "بعد", labelWidth - 100, 91, fontSize: 18, fontWeight: FontWeight.bold);

        canvas.drawLine(const Offset(10, 130), const Offset(470, 130), linePaint);

        _drawCenteredText(canvas, "SKU: ${_scannedItem!['id']}", 135, labelWidth, fontSize: 12);
        _drawRealBarcode(canvas, _scannedItem!['id'].toString(), 155, labelWidth, 40);
      } else {
        _drawCenteredText(canvas, _scannedItem!['sku'].toString(), 10, labelWidth, fontSize: 16, fontWeight: FontWeight.bold);
        _drawCenteredText(canvas, _scannedItem!['name'].toString(), 35, labelWidth, fontSize: 14);
        canvas.drawLine(const Offset(10, 55), const Offset(470, 55), linePaint);

        _drawCenteredText(canvas, "QR ${_scannedItem!['price']}", 75, labelWidth, fontSize: 28, fontWeight: FontWeight.bold);
        canvas.drawLine(const Offset(10, 120), const Offset(470, 120), linePaint);

        _drawCenteredText(canvas, "SKU: ${_scannedItem!['id']}", 130, labelWidth, fontSize: 12);
        _drawRealBarcode(canvas, _scannedItem!['id'].toString(), 150, labelWidth, 45);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(labelWidth, labelHeight);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData != null) {
      final Uint8List rgbaBytes = byteData.buffer.asUint8List();

      if (_printerMode == 'bluetooth') {
        final Uint8List tsplBytes = _convertTo1BitDitheredRaster(rgbaBytes, labelWidth, labelHeight, invert: false);
        try {
          await platform.invokeMethod('printBitmapTSPL', {
            'bytes': tsplBytes, 'width': labelWidth, 'height': labelHeight,
            'widthMm': widthMm, 'heightMm': heightMm, 'gapMm': gapMm, 'qty': _quantity
          });
        } on PlatformException catch (e) {
          debugPrint("Print call crashed: ${e.message}");
        }
      } else {
        final Uint8List escPosBytes = _convertTo1BitDitheredRaster(rgbaBytes, labelWidth, labelHeight, invert: true);
        await _printViaServer(escPosBytes, labelWidth, labelHeight, _quantity);
      }
    }
  }

  Uint8List _convertTo1BitDitheredRaster(Uint8List rgba, int w, int h, {required bool invert}) {
    int bytesPerLine = (w + 7) ~/ 8;
    Uint8List result = Uint8List(bytesPerLine * h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int rgbaIdx = (y * w + x) * 4;
        int r = rgba[rgbaIdx];
        int g = rgba[rgbaIdx + 1];
        int b = rgba[rgbaIdx + 2];

        double luminance = 0.299 * r + 0.587 * g + 0.114 * b;
        bool isPixelActive = invert ? (luminance < 180) : (luminance >= 180);

        if (isPixelActive) {
          int byteIdx = (y * bytesPerLine) + (x ~/ 8);
          int bitIdx = 7 - (x % 8);
          result[byteIdx] |= (1 << bitIdx);
        }
      }
    }
    return result;
  }

  void _drawCenteredText(Canvas canvas, String text, double y, int layoutWidth, {double fontSize = 20, FontWeight fontWeight = FontWeight.normal}) {
    final textPainter = TextPainter(text: TextSpan(style: TextStyle(color: Colors.black, fontSize: fontSize, fontWeight: fontWeight), text: text), textDirection: TextDirection.ltr)..layout();
    textPainter.paint(canvas, Offset((layoutWidth - textPainter.width) / 2, y));
  }

  void _drawLeftText(Canvas canvas, String text, double x, double y, {double fontSize = 20}) {
    final textPainter = TextPainter(text: TextSpan(style: TextStyle(color: Colors.black, fontSize: fontSize), text: text), textDirection: TextDirection.ltr)..layout();
    textPainter.paint(canvas, Offset(x, y));
  }

  void _drawRightText(Canvas canvas, String text, double xRight, double y, {double fontSize = 20, FontWeight fontWeight = FontWeight.normal}) {
    final textPainter = TextPainter(text: TextSpan(style: TextStyle(color: Colors.black, fontSize: fontSize, fontWeight: fontWeight), text: text), textDirection: TextDirection.rtl)..layout();
    textPainter.paint(canvas, Offset(xRight - textPainter.width, y));
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, {double dashWidth = 6.0, double dashSpace = 4.0}) {
    double dx = p2.dx - p1.dx; double dy = p2.dy - p1.dy; double magnitude = Offset(dx, dy).distance;
    if (magnitude == 0) return;
    double dirX = dx / magnitude; double dirY = dy / magnitude; double start = 0.0;
    while (start < magnitude) {
      double end = start + dashWidth; if (end > magnitude) end = magnitude;
      canvas.drawLine(Offset(p1.dx + dirX * start, p1.dy + dirY * start), Offset(p1.dx + dirX * end, p1.dy + dirY * end), paint);
      start += dashWidth + dashSpace;
    }
  }

  void _drawRealBarcode(Canvas canvas, String code, double y, int layoutWidth, double height) {
    final bc = Barcode.code128();
    double barcodeWidth = 320; double startX = (layoutWidth - barcodeWidth) / 2;
    final recipe = bc.make(code, width: barcodeWidth, height: height, drawText: false);
    final barPaint = Paint()..color = Colors.black;

    for (var elem in recipe) {
      if (elem is BarcodeBar && elem.black) {
        canvas.drawRect(Rect.fromLTWH(startX + elem.left, y + elem.top, elem.width, elem.height), barPaint);
      }
    }
    final textPainter = TextPainter(text: TextSpan(style: const TextStyle(fontFamily: 'monospace', fontSize: 14, letterSpacing: 4, color: Colors.black), text: code), textDirection: TextDirection.ltr)..layout();
    textPainter.paint(canvas, Offset((layoutWidth - textPainter.width) / 2, y + height + 4));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Label Station'),
        actions: [
          IconButton(
              icon: const Icon(Icons.settings),
              tooltip: "Settings",
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())).then((_) => _loadNetworkSettings())
          ),
          if (_printerMode == 'bluetooth')
            Icon(Icons.circle, color: _connected ? Colors.green : Colors.red),
          const SizedBox(width: 15),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: _printerMode == 'bluetooth'
                    ? Row(
                  children: [
                    Expanded(
                      child: DropdownButton<Map<dynamic, dynamic>>(
                        isExpanded: true,
                        hint: Text(_isScanning ? "Scanning layout..." : 'Select Discovered Printer'),
                        value: _selectedDevice,
                        items: _devices.map((device) {
                          return DropdownMenuItem<Map<dynamic, dynamic>>(value: device, child: Text("${device['name']} (${device['address']})"));
                        }).toList(),
                        onChanged: _connected ? null : (device) => setState(() => _selectedDevice = device),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _connected ? null : _startInAppScan,
                      icon: _isScanning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _selectedDevice == null ? null : (_connected ? _disconnectPrinter : _connectToPrinter),
                      style: ElevatedButton.styleFrom(backgroundColor: _connected ? Colors.red.shade100 : Colors.green.shade100),
                      child: Text(_connected ? 'Disconnect' : 'Connect'),
                    ),
                  ],
                )
                    : ListTile(
                  leading: const Icon(Icons.wifi, color: Colors.blueGrey, size: 36),
                  title: const Text("WiFi / LAN Server Mode Active", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_printerIp.isNotEmpty ? "IP: $_printerIp:$_printerPort" : "No IP configured in Settings.", style: const TextStyle(color: Colors.grey)),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // --- UPDATED CLICKABLE DATE PICKER UI ---
            Card(
              color: Colors.white,
              elevation: 0,
              clipBehavior: Clip.antiAlias, // Keeps the InkWell ripple inside the rounded corners
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.blueGrey.shade200, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: InkWell(
                onTap: () => _pickDate(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, color: Colors.blueGrey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Target Date: ${_targetDate.toIso8601String().split('T')[0]}",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Text(
                        "CHANGE",
                        style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // -----------------------------

            TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              decoration: InputDecoration(
                  labelText: 'Scan Barcode or Enter Serial Manually',
                  prefixIcon: const Icon(Icons.qr_code_scanner),
                  suffixIcon: _isLookingUp ? const Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator(strokeWidth: 2)) : null,
                  border: const OutlineInputBorder()
              ),
              onSubmitted: _isLookingUp ? null : _handleItemLookup,
            ),
            const SizedBox(height: 16),

            _scannedItem == null
                ? const Padding(padding: EdgeInsets.symmetric(vertical: 40.0), child: Center(child: Text("Ready for barcode or serial entry...")))
                : Card(
              color: Colors.blueGrey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("ITEM DETAILS", style: Theme.of(context).textTheme.titleSmall),
                    const Divider(),
                    Text(_scannedItem!['name'].toString(), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("Serial/ID: ${_scannedItem!['id']}", style: const TextStyle(fontSize: 16)),
                    Text("SKU Number: ${_scannedItem!['sku']}", style: const TextStyle(fontSize: 16)),
                    Text("Was Price: QR ${_scannedItem!['was_price']}", style: const TextStyle(fontSize: 16, color: Colors.grey)),
                    Text("Now Price: QR ${_scannedItem!['price']}", style: const TextStyle(fontSize: 18, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      value: _labelFormat,
                      decoration: const InputDecoration(labelText: 'Select Print Format', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                      items: const [
                        DropdownMenuItem(value: 'normal', child: Text('Normal (Standard Price)')),
                        DropdownMenuItem(value: 'was-now', child: Text('Was-Now (Discounted Format)')),
                      ],
                      onChanged: (value) => setState(() { _labelFormat = value!; }),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _labelSize,
                      decoration: const InputDecoration(labelText: 'Select Label Size', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                      items: const [
                        DropdownMenuItem(value: '76x51', child: Text('76x51 mm (Large)')),
                        DropdownMenuItem(value: '60x29', child: Text('60x29 mm (Small)')),
                        DropdownMenuItem(value: '50x38', child: Text('50x38 mm (Medium)')),
                      ],
                      onChanged: (value) => setState(() { _labelSize = value!; }),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null, icon: const Icon(Icons.remove)),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 24.0), child: Text("$_quantity", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold))),
                        IconButton.filledTonal(onPressed: () => setState(() => _quantity++), icon: const Icon(Icons.add)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: (_printerMode == 'bluetooth' && !_connected) ? null : _generateAndPrintGraphics,
                      icon: const Icon(Icons.print),
                      label: const Text('PRINT LABELS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}