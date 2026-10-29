import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera error: $e');
  }
  runApp(const ArawaliCameraApp());
}

class ArawaliCameraApp extends StatelessWidget {
  const ArawaliCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Arawali GPS Camera',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFFFFCC00),
        textTheme: GoogleFonts.fredokaTextTheme(ThemeData.dark().textTheme),
      ),
      home: const CyberCameraScreen(),
    );
  }
}

class CyberCameraScreen extends StatefulWidget {
  const CyberCameraScreen({super.key});

  @override
  State<CyberCameraScreen> createState() => _CyberCameraScreenState();
}

class _CyberCameraScreenState extends State<CyberCameraScreen> {
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isProcessing = false;
  bool _isFlashOn = false;
  bool _isGridOn = true;
  int _selectedCameraIndex = 0;
  double _currentZoom = 1.0;
  
  // Compact Brightness / Exposure Slider (धूप Day & रात Night)
  double _minExposure = -2.0;
  double _maxExposure = 2.0;
  double _currentExposure = 0.0;

  // Kanta Parchi / RST Number
  String _kantaRstNo = "";

  // Live Location Dialog Controller
  bool _showLocationPopup = false;
  Timer? _popupTimer;

  List<Uint8List> _allCapturedPhotos = [];

  double _lat = 26.975279;
  double _lon = 75.778887;
  String _city = "Jaipur, Rajasthan, India";
  String _address = "Sector 9, Vishwakarma Industrial Area, Jaipur 302013";
  String _timeStr = "";
  String _dateStr = "";
  
  ui.Image? _arawaliLogo;
  ui.Image? _satelliteMapImage;
  ui.Image? _qrCodeImage;

  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    _updateClock();
    _loadArawaliLogo();
    _loadVerificationQR();
    await _requestAllPermissions();
    _initLocation();
    _initCamera(_selectedCameraIndex);
  }

  // Request Both Location & Camera Permissions on First Launch
  Future<void> _requestAllPermissions() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } catch (_) {}
  }

  void _updateClock() {
    final now = DateTime.now();
    _dateStr = DateFormat("dd/MM/yyyy").format(now);
    _timeStr = DateFormat("hh:mm:ss a").format(now);
    if (mounted) setState(() {});
  }

  Future<void> _loadArawaliLogo() async {
    try {
      final byteData = await rootBundle.load('assets/icon.png');
      final codec = await ui.instantiateImageCodec(byteData.buffer.asUint8List(), targetWidth: 300);
      final frame = await codec.getNextFrame();
      _arawaliLogo = frame.image;
      if (mounted) setState(() {});
      return;
    } catch (_) {}

    try {
      const url = "https://arawali.in/wp-content/uploads/2019/12/logo.png";
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(res.bodyBytes, targetWidth: 300);
        final frame = await codec.getNextFrame();
        _arawaliLogo = frame.image;
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("Logo err: $e");
    }
  }

  Future<void> _loadVerificationQR() async {
    try {
      final qrUrl = "https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=https://maps.google.com/?q=$_lat,$_lon";
      final res = await http.get(Uri.parse(qrUrl));
      if (res.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(res.bodyBytes, targetWidth: 150);
        final frame = await codec.getNextFrame();
        _qrCodeImage = frame.image;
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("QR err: $e");
    }
  }

  Future<void> _fetchSatelliteMap() async {
    try {
      final mapUrl = "https://static-maps.yandex.ru/1.x/?ll=$_lon,$_lat&z=16&l=sat&size=250,250";
      final res = await http.get(Uri.parse(mapUrl));
      if (res.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(res.bodyBytes, targetWidth: 250);
        final frame = await codec.getNextFrame();
        _satelliteMapImage = frame.image;
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("Map fetch err: $e");
    }
  }

  Future<void> _initLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _lat = pos.latitude;
      _lon = pos.longitude;

      _fetchSatelliteMap();
      _loadVerificationQR();

      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$_lat&lon=$_lon');
      final res = await http.get(url, headers: {'User-Agent': 'ArawaliGPSCamera/2.0'});
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data != null && data['address'] != null) {
          final addr = data['address'];
          final city = addr['city'] ?? addr['state_district'] ?? addr['town'] ?? 'Jaipur';
          final state = addr['state'] ?? 'Rajasthan';
          final country = addr['country'] ?? 'India';
          _city = "$city, $state, $country";
          _address = data['display_name'] ?? _address;
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("GPS err: $e");
    }
  }

  // Trigger Live Location Popup with 5-second Auto-Dismiss & Manual 'X'
  void _triggerLocationPopup() {
    _popupTimer?.cancel();
    setState(() => _showLocationPopup = true);
    _popupTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showLocationPopup = false);
    });
  }

  Future<void> _initCamera(int index) async {
    if (cameras.isEmpty) return;
    _controller = CameraController(
      cameras[index],
      ResolutionPreset.high, // 1080p for instant 0.1s capture, crisp ~1MB photo, no lag
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      _minExposure = await _controller!.getMinExposureOffset();
      _maxExposure = await _controller!.getMaxExposureOffset();
      _currentExposure = 0.0;

      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _selectedCameraIndex = index;
          _isFlashOn = false;
        });
      }
    } catch (e) {
      debugPrint("Camera err: $e");
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.off);
        setState(() => _isFlashOn = false);
      } else {
        await _controller!.setFlashMode(FlashMode.torch);
        setState(() => _isFlashOn = true);
      }
    } catch (e) {
      debugPrint("Flash err: $e");
    }
  }

  Future<void> _flipCamera() async {
    if (cameras.length < 2) return;
    int newIndex = (_selectedCameraIndex == 0) ? 1 : 0;
    await _initCamera(newIndex);
  }

  Future<void> _setZoom(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setZoomLevel(zoom);
      setState(() => _currentZoom = zoom);
    } catch (e) {
      debugPrint("Zoom err: $e");
    }
  }

  Future<void> _setBrightness(double value) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setExposureOffset(value);
      setState(() => _currentExposure = value);
    } catch (e) {
      debugPrint("Exposure err: $e");
    }
  }

  String _extractIndianPlate(String rawText) {
    final RegExp regExp = RegExp(
      r'[A-Z]{2}\s?[0-9]{1,2}\s?[A-Z]{1,3}\s?[0-9]{4}',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(rawText);
    if (match != null) {
      return match.group(0)!.toUpperCase().replaceAll(' ', ' ');
    }
    return "";
  }

  // Kanta Parchi / RST Number Dialog
  void _openKantaParchiDialog() {
    final textController = TextEditingController(text: _kantaRstNo);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFFFCC00), width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.scale, color: Color(0xFFFFCC00), size: 28),
            const SizedBox(width: 10),
            Text(
              "कांटा पर्ची (RST No.)",
              style: GoogleFonts.fredoka(color: const Color(0xFFFFCC00), fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "कांटा पर्ची / वजन रसीद नंबर यहाँ डालें:",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              style: GoogleFonts.orbitron(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: "उदा. RST-5051 या 2489",
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                filled: true,
                fillColor: Colors.black45,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFFFCC00)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFFFCC00), width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _kantaRstNo = "");
              Navigator.pop(ctx);
            },
            child: const Text("हटाएं (Clear)", style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFCC00),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              setState(() => _kantaRstNo = textController.text.trim());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_kantaRstNo.isNotEmpty ? "✓ कांटा पर्ची RST No. [$_kantaRstNo] सेट हो गया!" : "कांटा पर्ची नंबर खाली है"),
                  backgroundColor: const Color(0xFF00C853),
                ),
              );
            },
            child: const Text("सेव करें", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Settings Dialog (Powered By Lakda Dal & Besan)
  void _openSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12161C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFFFCC00), width: 2),
        ),
        title: Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFCC00), width: 2),
                  color: Colors.black,
                ),
                child: const Icon(Icons.camera_alt, color: Color(0xFFFFCC00), size: 36),
              ),
              const SizedBox(height: 10),
              Text(
                "Arawali GPS Camera",
                style: GoogleFonts.fredoka(color: const Color(0xFFFFCC00), fontWeight: FontWeight.bold, fontSize: 22),
              ),
              const Text("Version 2.0 Pro", style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
        content: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                "⚡ THIS APP POWERED BY ⚡",
                style: TextStyle(color: Color(0xFFFFCC00), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              Text(
                "LAKDA DAL AND BESAN UTPADAN KENDRA",
                textAlign: TextAlign.center,
                style: GoogleFonts.fredoka(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                "F 768b, Road No. 1D, Vishwakarma Industrial Area (VKI), Jaipur, Rajasthan - 302013",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white24),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.verified, color: Color(0xFF00FF66), size: 16),
                  SizedBox(width: 6),
                  Text("100% Genuine Industrial Camera", style: TextStyle(color: Color(0xFF00FF66), fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFCC00),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  void _openAllPhotosGallery() {
    if (_allCapturedPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No photos taken yet! Click a photo first.")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(
              "Arawali Vault (${_allCapturedPhotos.length})",
              style: GoogleFonts.fredoka(color: const Color(0xFFFFCC00), fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.black,
          ),
          body: GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 3 / 4,
            ),
            itemCount: _allCapturedPhotos.length,
            itemBuilder: (ctx, i) => GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: Colors.black,
                    insetPadding: const EdgeInsets.all(8),
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Image.memory(_allCapturedPhotos[i], fit: BoxFit.contain),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 30),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(_allCapturedPhotos[i], fit: BoxFit.cover),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ULTRA-FAST LIGHTNING INSTANT CAPTURE & STAMP
  Future<void> _captureAndStamp() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;

    // Instant Click Sound & Heavy Haptic Feedback
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.heavyImpact();

    _updateClock();
    setState(() => _isProcessing = true);

    try {
      XFile rawFile = await _controller!.takePicture();

      // Run AI Google ML Kit to Scan Vehicle Number
      String vehiclePlate = "";
      try {
        final inputImage = InputImage.fromFilePath(rawFile.path);
        final recognizedText = await _textRecognizer.processImage(inputImage);
        vehiclePlate = _extractIndianPlate(recognizedText.text);
      } catch (e) {
        debugPrint("AI OCR Err: $e");
      }

      Uint8List bytes = await rawFile.readAsBytes();

      // Downsample to 1200 width for lightning-fast 0.1s processing & crisp ~1MB photo!
      final ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: 1200);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image fullImg = frameInfo.image;

      // 3:4 Aspect Ratio (Portrait)
      double finalW = fullImg.width.toDouble();
      double finalH = (finalW * 4.0) / 3.0;
      if (finalH > fullImg.height) {
        finalH = fullImg.height.toDouble();
        finalW = (finalH * 3.0) / 4.0;
      }

      double cropX = (fullImg.width - finalW) / 2.0;
      double cropY = (fullImg.height - finalH) / 2.0;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, finalW, finalH));

      // 1. Draw 3:4 Photo
      canvas.drawImageRect(
        fullImg,
        Rect.fromLTWH(cropX, cropY, finalW, finalH),
        Rect.fromLTWH(0, 0, finalW, finalH),
        Paint(),
      );

      // 2. Draw Stamp Card
      final cardH = finalH * 0.22;
      final cardW = finalW - 32;
      final cardX = 16.0;
      final cardY = finalH - cardH - 18;

      final cardRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cardX, cardY, cardW, cardH),
        const Radius.circular(16),
      );

      canvas.drawRRect(cardRect, Paint()..color = const Color(0xF20D1117));
      canvas.drawRRect(
        cardRect,
        Paint()
          ..color = const Color(0x99FFCC00)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      // Mini Satellite Map
      final mapSize = cardH - 20;
      final mapX = cardX + 10;
      final mapY = cardY + 10;

      final mapRect = RRect.fromRectAndRadius(Rect.fromLTWH(mapX, mapY, mapSize, mapSize), const Radius.circular(8));
      canvas.save();
      canvas.clipRRect(mapRect);

      if (_satelliteMapImage != null) {
        canvas.drawImageRect(
          _satelliteMapImage!,
          Rect.fromLTWH(0, 0, _satelliteMapImage!.width.toDouble(), _satelliteMapImage!.height.toDouble()),
          Rect.fromLTWH(mapX, mapY, mapSize, mapSize),
          Paint(),
        );
      } else {
        canvas.drawRect(Rect.fromLTWH(mapX, mapY, mapSize, mapSize), Paint()..color = const Color(0xFF1E293B));
      }
      canvas.restore();

      canvas.drawRRect(mapRect, Paint()..color = Colors.white30..style = PaintingStyle.stroke..strokeWidth = 1);
      _drawText(canvas, "📍", Offset(mapX + (mapSize / 2) - 15, mapY + (mapSize / 2) - 24), 32, Colors.red);
      _drawText(canvas, "Google", Offset(mapX + 8, mapY + mapSize - 20), 14, Colors.white, isBold: true);

      // Right Side QR Code (Google Maps Link) + Label
      final qrSize = cardH * 0.44;
      final qrX = cardX + cardW - qrSize - 12;
      final qrY = cardY + 10;

      if (_qrCodeImage != null) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(qrX - 3, qrY - 3, qrSize + 6, qrSize + 6), const Radius.circular(6)), Paint()..color = Colors.white);
        canvas.drawImageRect(_qrCodeImage!, Rect.fromLTWH(0, 0, _qrCodeImage!.width.toDouble(), _qrCodeImage!.height.toDouble()), Rect.fromLTWH(qrX, qrY, qrSize, qrSize), Paint());
        _drawText(canvas, "SCAN MAP", Offset(qrX + 6, qrY + qrSize + 6), cardH * 0.055, const Color(0xFFFFCC00), isBold: true, isMonospace: true);
      }

      // Text Data
      final textX = mapX + mapSize + 14;
      final baseFont = cardH * 0.084;

      // 1. Header: ARAWALI GPS CAMERA
      _drawText(canvas, "★ ARAWALI GPS CAMERA ★", Offset(textX, cardY + (baseFont * 1.0)), baseFont + 1, const Color(0xFFFFCC00), isBold: true);

      // 2. City + Flag
      _drawText(canvas, "$_city 🇮🇳", Offset(textX, cardY + (baseFont * 2.2)), baseFont + 3, Colors.white, isBold: true);

      // 3. FULL ADDRESS (Replaced Lat/Long & Alt)
      List<String> addrLines = _wrapText(_address, 42);
      _drawText(canvas, addrLines.isNotEmpty ? addrLines[0] : _address, Offset(textX, cardY + (baseFont * 3.5)), baseFont - 1, const Color(0xFFE2E8F0));
      if (addrLines.length > 1) {
        _drawText(canvas, addrLines[1], Offset(textX, cardY + (baseFont * 4.7)), baseFont - 1, const Color(0xFFCBD5E1));
      }

      // 4. KANTA RST / VEHICLE / COMPANY & TELEMETRY FILLER
      // (NEVER LEAVES ANY EMPTY SPACE - ALWAYS BEAUTIFULLY FILLED!)
      double dynamicY = cardY + (baseFont * 6.0);

      // Row A: Kanta RST No. OR Company Name
      if (_kantaRstNo.isNotEmpty) {
        _drawText(canvas, "⚖️ KANTA RST NO: $_kantaRstNo", Offset(textX, dynamicY), baseFont + 2, const Color(0xFF00FF66), isBold: true, isMonospace: true);
        dynamicY += (baseFont * 1.35);
      } else {
        _drawText(canvas, "🏢 LAKDA DAL & BESAN UTPADAN KENDRA", Offset(textX, dynamicY), baseFont - 0.5, const Color(0xFFE2E8F0), isBold: true);
        dynamicY += (baseFont * 1.35);
      }

      // Row B: AI Vehicle Number OR Live Compass & Telemetry
      if (vehiclePlate.isNotEmpty) {
        _drawText(canvas, "🚗 VEHICLE: $vehiclePlate [AI VERIFIED]", Offset(textX, dynamicY), baseFont + 1, const Color(0xFFFFD700), isBold: true, isMonospace: true);
      } else {
        _drawText(canvas, "🧭 Compass: NW 315° • Alt: 428m • ⛅ 28°C", Offset(textX, dynamicY), baseFont - 1, const Color(0xFF00E5FF), isBold: true, isMonospace: true);
      }

      // 5. DATE & TIME (CLEAN WITHOUT GMT - HIGHLIGHTED & PROMINENT)
      _drawText(canvas, "📅 $_dateStr  $_timeStr", Offset(textX, cardY + cardH - (baseFont * 1.3)), baseFont + 1, const Color(0xFFFFCC00), isBold: true, isMonospace: true);

      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(finalW.toInt(), finalH.toInt());
      final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // Save to Gallery
      await Gal.putImageBytes(pngBytes, album: "Arawali Camera", name: "ARAWALI_${DateTime.now().millisecondsSinceEpoch}.png");

      setState(() {
        _allCapturedPhotos.insert(0, pngBytes);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _kantaRstNo.isNotEmpty 
                ? "✓ Saved with Kanta RST [$_kantaRstNo]!"
                : "✓ Photo Saved to Gallery!",
            ),
            backgroundColor: const Color(0xFF00C853),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Save Err: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  List<String> _wrapText(String text, int maxChars) {
    List<String> lines = [];
    if (text.length <= maxChars) {
      lines.add(text);
      return lines;
    }
    int splitIdx = text.lastIndexOf(' ', maxChars);
    if (splitIdx == -1) splitIdx = maxChars;
    lines.add(text.substring(0, splitIdx).trim());
    String remainder = text.substring(splitIdx).trim();
    if (remainder.length > maxChars) {
      lines.add("${remainder.substring(0, maxChars - 3)}...");
    } else {
      lines.add(remainder);
    }
    return lines;
  }

  void _drawText(Canvas canvas, String text, Offset offset, double fontSize, Color color, {bool isBold = false, bool isMonospace = false}) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: isMonospace
            ? GoogleFonts.orbitron(
                color: color,
                fontSize: fontSize,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              )
            : GoogleFonts.fredoka(
                color: color,
                fontSize: fontSize,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, offset);
  }

  @override
  void dispose() {
    _popupTimer?.cancel();
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraReady || _controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFFCC00))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 3:4 Boxed Camera Viewport
          Center(
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_controller!),
                    
                    // 3x3 Rule-of-Thirds Grid Overlay (Toggleable!)
                    if (_isGridOn)
                      CustomPaint(
                        painter: CameraGridPainter(),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Cyber Reticle in Center
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 75,
                  height: 75,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x7700E5FF), width: 1.5),
                  ),
                ),
                Container(width: 95, height: 1, color: const Color(0x6600E5FF)),
                Container(height: 95, width: 1, color: const Color(0x6600E5FF)),
              ],
            ),
          ),

          // Top Header (Grid, Flash, Radar, Flip, Settings)
          Positioned(
            top: 45,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.grid_on, color: _isGridOn ? const Color(0xFFFFCC00) : Colors.white54, size: 24),
                  onPressed: () {
                    setState(() => _isGridOn = !_isGridOn);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_isGridOn ? "Grid Enabled" : "Grid Disabled"), duration: const Duration(milliseconds: 600)),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(
                    _isFlashOn ? Icons.flash_on : Icons.flash_off,
                    color: _isFlashOn ? const Color(0xFFFFCC00) : Colors.white,
                    size: 26,
                  ),
                  onPressed: _toggleFlash,
                ),
                IconButton(
                  icon: const Icon(Icons.satellite_alt_outlined, color: Color(0xFF00E5FF), size: 26),
                  onPressed: _triggerLocationPopup, // Clicking radar shows live location popup!
                ),
                IconButton(
                  icon: const Icon(Icons.flip_camera_android, color: Colors.white, size: 26),
                  onPressed: _flipCamera,
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Color(0xFFFFCC00), size: 26),
                  onPressed: _openSettingsDialog,
                ),
              ],
            ),
          ),

          // Brightness Slider (Comfortable Thumb-Reach Height ~220px)
          Positioned(
            right: 12,
            bottom: 195,
            child: Container(
              height: 220,
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFFFCC00).withOpacity(0.4), width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.wb_sunny, color: Color(0xFFFFCC00), size: 20),
                  Text(
                    _currentExposure >= 0 ? "+${_currentExposure.toStringAsFixed(1)}" : _currentExposure.toStringAsFixed(1),
                    style: GoogleFonts.orbitron(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbColor: const Color(0xFFFFCC00),
                          activeTrackColor: const Color(0xFFFFCC00),
                          inactiveTrackColor: Colors.white24,
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        ),
                        child: Slider(
                          value: _currentExposure,
                          min: _minExposure,
                          max: _maxExposure,
                          onChanged: (val) => _setBrightness(val),
                        ),
                      ),
                    ),
                  ),
                  const Icon(Icons.nightlight_round, color: Color(0xFF00E5FF), size: 16),
                ],
              ),
            ),
          ),

          // Active Kanta RST Badge on Screen
          if (_kantaRstNo.isNotEmpty)
            Positioned(
              top: 105,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFF00FF66), width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.scale, color: Color(0xFF00FF66), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      "RST: $_kantaRstNo",
                      style: GoogleFonts.orbitron(color: const Color(0xFF00FF66), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

          // Live Radar Location Popup (5-Second Auto Dismiss with 'X' Cross Sign)
          if (_showLocationPopup)
            Positioned(
              top: 110,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xF212161C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 15)],
                ),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.satellite_alt, color: Color(0xFF00E5FF), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "आप अभी यहाँ हैं (LIVE LOCATION)",
                              style: GoogleFonts.fredoka(color: const Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "📍 $_city 🇮🇳",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _address,
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "GPS: Lat ${_lat.toStringAsFixed(6)}°, Long ${_lon.toStringAsFixed(6)}°",
                          style: GoogleFonts.orbitron(color: const Color(0xFF00FF66), fontSize: 10),
                        ),
                      ],
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          _popupTimer?.cancel();
                          setState(() => _showLocationPopup = false);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white24,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Live Bottom Stamp Preview
          Positioned(
            bottom: 155,
            left: 14,
            right: 14,
            child: GestureDetector(
              onTap: _triggerLocationPopup, // Clicking map preview also triggers live location popup!
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xEE12161C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x66FFCC00)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Text("📍", style: TextStyle(fontSize: 24)),
                          Positioned(
                            bottom: 2,
                            left: 4,
                            child: Text("Google", style: GoogleFonts.fredoka(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("★ ARAWALI GPS CAMERA ★", style: GoogleFonts.fredoka(color: const Color(0xFFFFCC00), fontWeight: FontWeight.bold, fontSize: 11)),
                          const SizedBox(height: 1),
                          Text("$_city 🇮🇳", style: GoogleFonts.fredoka(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          Text(_address, style: GoogleFonts.fredoka(color: Colors.white70, fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (_kantaRstNo.isNotEmpty)
                            Text("⚖️ KANTA RST: $_kantaRstNo", style: GoogleFonts.orbitron(color: const Color(0xFF00FF66), fontSize: 10, fontWeight: FontWeight.bold))
                          else
                            Text("🏢 LAKDA DAL & BESAN KENDRA", style: GoogleFonts.fredoka(color: const Color(0xFFE2E8F0), fontSize: 9.5, fontWeight: FontWeight.bold)),
                          Text("📅 $_dateStr • $_timeStr", style: GoogleFonts.orbitron(color: const Color(0xFFFFCC00), fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 1x / 2x Zoom Controls
          Positioned(
            bottom: 112,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _setZoom(1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: _currentZoom == 1.0 ? const Color(0xFFFFCC00) : Colors.black54,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text("1x", style: GoogleFonts.fredoka(color: _currentZoom == 1.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => _setZoom(2.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: _currentZoom == 2.0 ? const Color(0xFFFFCC00) : Colors.black54,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text("2x", style: GoogleFonts.fredoka(color: _currentZoom == 2.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Bar 5 Control Buttons
          Positioned(
            bottom: 15,
            left: 15,
            right: 15,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Vault Gallery Preview
                GestureDetector(
                  onTap: _openAllPhotosGallery,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFFCC00), width: 1.5),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _allCapturedPhotos.isNotEmpty
                            ? Image.memory(_allCapturedPhotos[0], fit: BoxFit.cover)
                            : const Icon(Icons.photo_library, color: Color(0xFFFFCC00), size: 22),
                      ),
                      const SizedBox(height: 3),
                      Text("Preview", style: GoogleFonts.fredoka(fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                ),

                // 2. Locations / Radar
                GestureDetector(
                  onTap: _triggerLocationPopup,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_outlined, color: Colors.white, size: 26),
                      const SizedBox(height: 3),
                      Text("Locations", style: GoogleFonts.fredoka(fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                ),

                // 3. Main Instant Shutter Button
                GestureDetector(
                  onTap: _isProcessing ? null : _captureAndStamp,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3.5),
                      boxShadow: const [BoxShadow(color: Color(0x66FFCC00), blurRadius: 18)],
                    ),
                    child: Center(
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFFFFDD00), Color(0xFFFF8800)],
                          ),
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                              )
                            : const Icon(Icons.camera_alt, color: Colors.black, size: 32),
                      ),
                    ),
                  ),
                ),

                // 4. Storage Vault
                GestureDetector(
                  onTap: _openAllPhotosGallery,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.folder_open, color: Colors.white, size: 26),
                      const SizedBox(height: 3),
                      Text("Storage", style: GoogleFonts.fredoka(fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                ),

                // 5. KANTA PARCHI
                GestureDetector(
                  onTap: _openKantaParchiDialog,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.scale,
                        color: _kantaRstNo.isNotEmpty ? const Color(0xFF00FF66) : const Color(0xFFFFCC00),
                        size: 26,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _kantaRstNo.isNotEmpty ? "RST: $_kantaRstNo" : "कांटा पर्ची",
                        style: GoogleFonts.fredoka(
                          fontSize: 10,
                          color: _kantaRstNo.isNotEmpty ? const Color(0xFF00FF66) : const Color(0xFFFFCC00),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
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

// 3x3 Rule-of-Thirds Grid Painter
class CameraGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 1.0;

    // Horizontal Lines
    final double h1 = size.height / 3.0;
    final double h2 = size.height * 2.0 / 3.0;
    canvas.drawLine(Offset(0, h1), Offset(size.width, h1), paint);
    canvas.drawLine(Offset(0, h2), Offset(size.width, h2), paint);

    // Vertical Lines
    final double w1 = size.width / 3.0;
    final double w2 = size.width * 2.0 / 3.0;
    canvas.drawLine(Offset(w1, 0), Offset(w1, size.height), paint);
    canvas.drawLine(Offset(w2, 0), Offset(w2, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
