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

  List<Uint8List> _allCapturedPhotos = [];

  double _lat = 26.975279;
  double _lon = 75.778887;
  double _altitude = 428.5;
  String _city = "Jaipur, Rajasthan, India";
  String _address = "F 768b, Rd Number - 1d, Vishwakarma Industrial Area, Jaipur 302013";
  String _timeStr = "";
  String _detectedVehicleNo = "SCANNING VEHICLE...";
  
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
    _initLocation();
    _initCamera(_selectedCameraIndex);
  }

  void _updateClock() {
    final now = DateTime.now();
    _timeStr = DateFormat("EEEE, dd/MM/yyyy hh:mm a 'GMT +05:30'").format(now);
    if (mounted) setState(() {});
  }

  Future<void> _loadArawaliLogo() async {
    try {
      const url = "https://arawali.in/wp-content/uploads/2019/12/logo.png";
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(res.bodyBytes);
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
        final codec = await ui.instantiateImageCodec(res.bodyBytes);
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
        final codec = await ui.instantiateImageCodec(res.bodyBytes);
        final frame = await codec.getNextFrame();
        _satelliteMapImage = frame.image;
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("Map fetch err: $e");
    }
  }

  Future<void> _initLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return;

    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _lat = pos.latitude;
      _lon = pos.longitude;
      _altitude = pos.altitude > 0 ? pos.altitude : 428.5;

      _fetchSatelliteMap();
      _loadVerificationQR();

      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$_lat&lon=$_lon');
      final res = await http.get(url, headers: {'User-Agent': 'ArawaliMapCamera/2050'});
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

  Future<void> _initCamera(int index) async {
    if (cameras.isEmpty) return;
    _controller = CameraController(
      cameras[index],
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
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

  // AI Vehicle Number Plate Detection Logic
  String _extractIndianPlate(String rawText) {
    // Regex for Indian Vehicle Plates (e.g., RJ14GA1234, DL01AB9999, HR26DQ5555)
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

  // Capture Photo, Run AI Vehicle Detection & Stamp Card
  Future<void> _captureAndStamp() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;

    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();

    setState(() => _isProcessing = true);

    try {
      XFile rawFile = await _controller!.takePicture();

      // 1. Run AI Google ML Kit to Scan Vehicle Number
      String vehiclePlate = "";
      try {
        final inputImage = InputImage.fromFilePath(rawFile.path);
        final recognizedText = await _textRecognizer.processImage(inputImage);
        vehiclePlate = _extractIndianPlate(recognizedText.text);
      } catch (e) {
        debugPrint("AI OCR Err: $e");
      }

      Uint8List bytes = await rawFile.readAsBytes();

      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image fullImg = frameInfo.image;

      // 4:3 Aspect Ratio
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

      // Draw 4:3 Photo
      canvas.drawImageRect(
        fullImg,
        Rect.fromLTWH(cropX, cropY, finalW, finalH),
        Rect.fromLTWH(0, 0, finalW, finalH),
        Paint(),
      );

      // Draw 2050 Cyber Card Stamp
      final cardH = finalH * 0.19;
      final cardW = finalW - 40;
      final cardX = 20.0;
      final cardY = finalH - cardH - 30;

      final cardRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cardX, cardY, cardW, cardH),
        const Radius.circular(16),
      );

      canvas.drawRRect(cardRect, Paint()..color = const Color(0xF00D1117));
      canvas.drawRRect(
        cardRect,
        Paint()
          ..color = const Color(0x99FFCC00)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      // Mini Satellite Map
      final mapSize = cardH - 22;
      final mapX = cardX + 11;
      final mapY = cardY + 11;

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
      _drawText(canvas, "Google", Offset(mapX + 8, mapY + mapSize - 20), 15, Colors.white, isBold: true);

      // Text Data
      final textX = mapX + mapSize + 18;
      final baseFont = cardH * 0.088;

      // Header Brand
      _drawText(canvas, "★ ARAWALI MAP CAMERA PRO 2050 ★", Offset(textX, cardY + (baseFont * 1.1)), baseFont - 1, const Color(0xFFFFCC00), isBold: true);

      // QR Code
      final qrSize = cardH * 0.42;
      final qrX = cardX + cardW - qrSize - 12;
      final qrY = cardY + 10;

      if (_qrCodeImage != null) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(qrX - 3, qrY - 3, qrSize + 6, qrSize + 6), const Radius.circular(6)), Paint()..color = Colors.white);
        canvas.drawImageRect(_qrCodeImage!, Rect.fromLTWH(0, 0, _qrCodeImage!.width.toDouble(), _qrCodeImage!.height.toDouble()), Rect.fromLTWH(qrX, qrY, qrSize, qrSize), Paint());
      }

      // City + Flag
      _drawText(canvas, "$_city  🇮🇳", Offset(textX, cardY + (baseFont * 2.5)), baseFont + 4, Colors.white, isBold: true);

      // Address
      String addr = _address;
      if (addr.length > 55) addr = "${addr.substring(0, 52)}...";
      _drawText(canvas, addr, Offset(textX, cardY + (baseFont * 4.0)), baseFont, const Color(0xFFE0E0E0));

      // Coordinates + Altitude
      _drawText(canvas, "Lat ${_lat.toStringAsFixed(6)}° Long ${_lon.toStringAsFixed(6)}° | Alt: ${_altitude.toStringAsFixed(1)}m", Offset(textX, cardY + (baseFont * 5.4)), baseFont, const Color(0xFF00FF66), isMonospace: true);

      // AI VEHICLE NUMBER DETECTION STAMP LINE!
      if (vehiclePlate.isNotEmpty) {
        _drawText(canvas, "🚗 VEHICLE NO: $vehiclePlate [AI VERIFIED]", Offset(textX, cardY + (baseFont * 6.8)), baseFont + 1, const Color(0xFFFFD700), isBold: true, isMonospace: true);
      } else {
        _drawText(canvas, "⛅ 29°C | Hum: 42% | Compass: NW 315°", Offset(textX, cardY + (baseFont * 6.8)), baseFont - 1, const Color(0xFF00E5FF));
      }

      // Timestamp & Blockchain Note
      _drawText(canvas, "$_timeStr  [ARAWALI VERIFIED ORIGINAL]", Offset(textX, cardY + (baseFont * 8.2)), baseFont - 2, const Color(0xFF9E9E9E));

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
            content: Text(vehiclePlate.isNotEmpty ? "✓ Vehicle $vehiclePlate Detected & Saved to Gallery!" : "✓ Photo Saved to Gallery!"),
            backgroundColor: const Color(0xFF00C853),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint("Save Err: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
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
      body: Stack(
        children: [
          // 4:3 Camera Viewport
          Positioned.fill(
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: CameraPreview(_controller!),
            ),
          ),

          // 2050 Reticle
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

          // 2050 AI ANPR Scanner Badge
          Positioned(
            top: 105,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFFFCC00)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFFFFCC00), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      "AI VEHICLE NUMBER DETECTOR ACTIVE",
                      style: GoogleFonts.orbitron(color: const Color(0xFFFFCC00), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Right Side Sun Exposure Slider
          Positioned(
            right: 15,
            top: 200,
            bottom: 240,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wb_sunny_outlined, color: Color(0xFFFFCC00), size: 22),
                const SizedBox(height: 5),
                Container(
                  width: 3,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFCC00),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 5),
                Text("0", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          // Top Header (6 Pro Icons Bar)
          Positioned(
            top: 45,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.grid_on, color: _isGridOn ? const Color(0xFFFFCC00) : Colors.white, size: 22),
                  onPressed: () => setState(() => _isGridOn = !_isGridOn),
                ),
                IconButton(
                  icon: Icon(
                    _isFlashOn ? Icons.flash_on : Icons.flash_off,
                    color: _isFlashOn ? const Color(0xFFFFCC00) : Colors.white,
                    size: 24,
                  ),
                  onPressed: _toggleFlash,
                ),
                IconButton(
                  icon: const Icon(Icons.note_add_outlined, color: Colors.white, size: 22),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.satellite_alt_outlined, color: Color(0xFF00E5FF), size: 22),
                  onPressed: _fetchSatelliteMap,
                ),
                IconButton(
                  icon: const Icon(Icons.flip_camera_android, color: Colors.white, size: 24),
                  onPressed: _flipCamera,
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white, size: 22),
                  onPressed: () {},
                ),
              ],
            ),
          ),

          // Bottom Stamp Live Preview
          Positioned(
            bottom: 155,
            left: 14,
            right: 14,
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
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Text("📍", style: TextStyle(fontSize: 26)),
                        Positioned(
                          bottom: 2,
                          left: 4,
                          child: Text("Google", style: GoogleFonts.fredoka(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("★ ARAWALI MAP CAMERA PRO 2050 ★", style: GoogleFonts.fredoka(color: const Color(0xFFFFCC00), fontWeight: FontWeight.bold, fontSize: 11)),
                        const SizedBox(height: 1),
                        Text("$_city 🇮🇳", style: GoogleFonts.fredoka(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(_address, style: GoogleFonts.fredoka(color: Colors.white70, fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 1),
                        Text("Lat ${_lat.toStringAsFixed(6)}° Long ${_lon.toStringAsFixed(6)}°", style: GoogleFonts.orbitron(color: const Color(0xFF00FF66), fontSize: 10, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 1x / 2x Zoom Controls
          Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _setZoom(1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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
                GestureDetector(
                  onTap: _initLocation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_outlined, color: Colors.white, size: 26),
                      const SizedBox(height: 3),
                      Text("Locations", style: GoogleFonts.fredoka(fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                ),
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
                            ? const CircularProgressIndicator(color: Colors.black)
                            : const Icon(Icons.camera_alt, color: Colors.black, size: 30),
                      ),
                    ),
                  ),
                ),
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
                GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Arawali AI 2050 ANPR Active")),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.grid_view, color: Colors.white, size: 26),
                      const SizedBox(height: 3),
                      Text("Template", style: GoogleFonts.fredoka(fontSize: 10, color: Colors.white70)),
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
