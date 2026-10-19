import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

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
      title: 'Arawali Map Camera',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFFFFCC00),
      ),
      home: const CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isProcessing = false;

  double _lat = 26.976795;
  double _lon = 75.780594;
  String _city = "Jaipur, Rajasthan, India";
  String _address = "Vishwakarma Industrial Area, Jaipur 302013";
  String _timeStr = "";
  ui.Image? _arawaliLogo;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    _updateClock();
    _loadArawaliLogo();
    _initLocation();
    _initCamera();
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

      List<Placemark> placemarks = await placemarkFromCoordinates(_lat, _lon);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        _city = "${place.locality ?? 'Jaipur'}, ${place.administrativeArea ?? 'Rajasthan'}, ${place.country ?? 'India'}";
        _address = "${place.street ?? ''}, ${place.subLocality ?? ''}, ${place.locality ?? ''} ${place.postalCode ?? ''}";
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("GPS err: $e");
    }
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    _controller = CameraController(
      cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint("Camera err: $e");
    }
  }

  Future<void> _captureAndStamp() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      XFile rawFile = await _controller!.takePicture();
      Uint8List bytes = await rawFile.readAsBytes();

      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image capturedImage = frameInfo.image;

      final width = capturedImage.width.toDouble();
      final height = capturedImage.height.toDouble();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

      // Draw photo
      canvas.drawImage(capturedImage, Offset.zero, Paint());

      // Draw Arawali Stamp Card
      final cardH = height * 0.18;
      final cardW = width - 40;
      final cardX = 20.0;
      final cardY = height - cardH - 30;

      final cardRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cardX, cardY, cardW, cardH),
        const Radius.circular(20),
      );

      canvas.drawRRect(cardRect, Paint()..color = const Color(0xEE0E1116));
      canvas.drawRRect(
        cardRect,
        Paint()
          ..color = const Color(0x99FFCC00)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );

      // Mini Map box
      final mapSize = cardH - 24;
      final mapX = cardX + 12;
      final mapY = cardY + 12;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(mapX, mapY, mapSize, mapSize), const Radius.circular(10)),
        Paint()..color = const Color(0xFF1E293B),
      );
      _drawText(canvas, "📍", Offset(mapX + (mapSize / 2) - 15, mapY + (mapSize / 2) - 25), 34, Colors.red);
      _drawText(canvas, "Google", Offset(mapX + 8, mapY + mapSize - 22), 16, Colors.white, isBold: true);

      // Text Fields
      final textX = mapX + mapSize + 20;
      final baseFont = cardH * 0.10;

      _drawText(canvas, "★ ARAWALI MAP CAMERA ★", Offset(textX, cardY + (baseFont * 1.2)), baseFont - 1, const Color(0xFFFFCC00), isBold: true);

      if (_arawaliLogo != null) {
        final logoH = baseFont * 2.2;
        final logoW = logoH * 3.2;
        final logoX = cardX + cardW - logoW - 16;
        final logoY = cardY + 12;

        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(logoX - 5, logoY - 2, logoW + 10, logoH + 4), const Radius.circular(6)), Paint()..color = Colors.white);
        canvas.drawImageRect(_arawaliLogo!, Rect.fromLTWH(0, 0, _arawaliLogo!.width.toDouble(), _arawaliLogo!.height.toDouble()), Rect.fromLTWH(logoX, logoY, logoW, logoH), Paint());
      }

      _drawText(canvas, "$_city  🇮🇳", Offset(textX, cardY + (baseFont * 2.6)), baseFont + 4, Colors.white, isBold: true);
      _drawText(canvas, _address, Offset(textX, cardY + (baseFont * 4.2)), baseFont, const Color(0xFFE0E0E0));
      _drawText(canvas, "Lat ${_lat.toStringAsFixed(6)}°  Long ${_lon.toStringAsFixed(6)}°", Offset(textX, cardY + (baseFont * 5.8)), baseFont, const Color(0xFF00FF66), isMonospace: true);
      _drawText(canvas, "$_timeStr\nNote : Captured by Arawali Map Camera", Offset(textX, cardY + (baseFont * 7.2)), baseFont - 2, const Color(0xFF9E9E9E));

      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // Save directly to Phone Gallery!
      await Gal.putImageBytes(pngBytes, album: "Arawali Camera", name: "ARAWALI_${DateTime.now().millisecondsSinceEpoch}.png");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✓ Photo Saved directly to Gallery!"),
            backgroundColor: Color(0xFF00C853),
            duration: Duration(seconds: 2),
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
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          fontFamily: isMonospace ? 'monospace' : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, offset);
  }

  @override
  void dispose() {
    _controller?.dispose();
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
          Positioned.fill(child: CameraPreview(_controller!)),

          // Top Header
          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFFCC00)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.gps_fixed, color: Color(0xFF00FF66), size: 16),
                      SizedBox(width: 8),
                      Text("ARAWALI PRO", style: TextStyle(color: Color(0xFFFFCC00), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom Stamp Live Preview
          Positioned(
            bottom: 120,
            left: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x66FFCC00)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("★ ARAWALI MAP CAMERA ★", style: TextStyle(color: Color(0xFFFFCC00), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text("$_city 🇮🇳", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(_address, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 2),
                  const SizedBox(height: 2),
                  Text("Lat ${_lat.toStringAsFixed(6)}° Long ${_lon.toStringAsFixed(6)}°", style: const TextStyle(color: Color(0xFF00FF66), fontSize: 12, fontFamily: 'monospace')),
                ],
              ),
            ),
          ),

          // Shutter Button
          Positioned(
            bottom: 25,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isProcessing ? null : _captureAndStamp,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: const [BoxShadow(color: Color(0x66FFCC00), blurRadius: 20)],
                  ),
                  child: Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFDD00), Color(0xFFFF8800)],
                        ),
                      ),
                      child: _isProcessing
                          ? const CircularProgressIndicator(color: Colors.black)
                          : const Icon(Icons.camera_alt, color: Colors.black, size: 32),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}