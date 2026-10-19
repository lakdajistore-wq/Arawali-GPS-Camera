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
import 'dart:convert';

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
  bool _isFlashOn = false;
  int _selectedCameraIndex = 0;
  
  List<Uint8List> _capturedPhotos = [];

  double _lat = 26.974355;
  double _lon = 75.779012;
  String _city = "Jaipur, Rajasthan, India";
  String _address = "Road Number 1, Malhotra Nagar, विश्वकर्मा इंडस्ट्री...";
  String _timeStr = "";
  ui.Image? _arawaliLogo;
  ui.Image? _satelliteMapImage;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    _updateClock();
    _loadArawaliLogo();
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

      _fetchSatelliteMap();

      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$_lat&lon=$_lon');
      final res = await http.get(url, headers: {'User-Agent': 'ArawaliMapCamera/1.0'});
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

  // Gallery Screen with All Captured Photos
  void _openGallery() {
    if (_capturedPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No photos captured yet!")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text("Arawali Gallery", style: TextStyle(color: Color(0xFFFFCC00), fontWeight: FontWeight.bold)),
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
            itemCount: _capturedPhotos.length,
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
                        Image.memory(_capturedPhotos[i], fit: BoxFit.contain),
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
                child: Image.memory(_capturedPhotos[i], fit: BoxFit.cover),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Capture, 4:3 Crop, Draw Satellite Map & Arawali Stamp
  Future<void> _captureAndStamp() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;

    // Mechanical Click Sound & Haptic Vibration
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();

    setState(() => _isProcessing = true);

    try {
      XFile rawFile = await _controller!.takePicture();
      Uint8List bytes = await rawFile.readAsBytes();

      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image fullImg = frameInfo.image;

      // 4:3 Aspect Ratio Calculation
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

      // Draw 4:3 Cropped Image
      canvas.drawImageRect(
        fullImg,
        Rect.fromLTWH(cropX, cropY, finalW, finalH),
        Rect.fromLTWH(0, 0, finalW, finalH),
        Paint(),
      );

      // Draw Glass Card Stamp
      final cardH = finalH * 0.175;
      final cardW = finalW - 40;
      final cardX = 20.0;
      final cardY = finalH - cardH - 30;

      final cardRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cardX, cardY, cardW, cardH),
        const Radius.circular(16),
      );

      canvas.drawRRect(cardRect, Paint()..color = const Color(0xEE12161C));
      canvas.drawRRect(
        cardRect,
        Paint()
          ..color = const Color(0x99FFCC00)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      // Draw Satellite Map Image inside Stamp
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
      final baseFont = cardH * 0.10;

      // Header
      _drawText(canvas, "★ ARAWALI MAP CAMERA ★", Offset(textX, cardY + (baseFont * 1.3)), baseFont - 1, const Color(0xFFFFCC00), isBold: true);

      // Company Logo on Stamp (Top Right)
      if (_arawaliLogo != null) {
        final logoH = baseFont * 2.2;
        final logoW = logoH * 3.2;
        final logoX = cardX + cardW - logoW - 14;
        final logoY = cardY + 10;

        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(logoX - 5, logoY - 2, logoW + 10, logoH + 4), const Radius.circular(6)), Paint()..color = Colors.white);
        canvas.drawImageRect(_arawaliLogo!, Rect.fromLTWH(0, 0, _arawaliLogo!.width.toDouble(), _arawaliLogo!.height.toDouble()), Rect.fromLTWH(logoX, logoY, logoW, logoH), Paint());
      }

      // City + Flag
      _drawText(canvas, "$_city  🇮🇳", Offset(textX, cardY + (baseFont * 2.8)), baseFont + 4, Colors.white, isBold: true);

      // Address
      String addr = _address;
      if (addr.length > 55) addr = "${addr.substring(0, 52)}...";
      _drawText(canvas, addr, Offset(textX, cardY + (baseFont * 4.4)), baseFont, const Color(0xFFE0E0E0));

      // Coordinates
      _drawText(canvas, "Lat ${_lat.toStringAsFixed(6)}° Long ${_lon.toStringAsFixed(6)}°", Offset(textX, cardY + (baseFont * 6.0)), baseFont, const Color(0xFF00FF66), isMonospace: true);

      // Date Time Note
      _drawText(canvas, "$_timeStr\nNote : Captured by Arawali Map Camera", Offset(textX, cardY + (baseFont * 7.4)), baseFont - 2, const Color(0xFF9E9E9E));

      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(finalW.toInt(), finalH.toInt());
      final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // Save directly to Phone Gallery!
      await Gal.putImageBytes(pngBytes, album: "Arawali Camera", name: "ARAWALI_${DateTime.now().millisecondsSinceEpoch}.png");

      setState(() {
        _capturedPhotos.insert(0, pngBytes);
      });

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
      textDirection: ui.TextDirection.ltr,
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

          // Top Header (Flash, Brand, Flip Buttons)
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _toggleFlash,
                  icon: Icon(
                    _isFlashOn ? Icons.flash_on : Icons.flash_off,
                    color: _isFlashOn ? const Color(0xFFFFCC00) : Colors.white,
                    size: 28,
                  ),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                ),
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
                IconButton(
                  onPressed: _flipCamera,
                  icon: const Icon(Icons.flip_camera_android, color: Colors.white, size: 28),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                ),
              ],
            ),
          ),

          // Bottom Stamp Live Preview
          Positioned(
            bottom: 125,
            left: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x66FFCC00)),
              ),
              child: Row(
                children: [
                  // Mini Preview Map
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: const [
                        Text("📍", style: TextStyle(fontSize: 26)),
                        Positioned(bottom: 2, left: 4, child: Text("Google", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("★ ARAWALI MAP CAMERA ★", style: TextStyle(color: Color(0xFFFFCC00), fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text("$_city 🇮🇳", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(_address, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text("Lat ${_lat.toStringAsFixed(6)}° Long ${_lon.toStringAsFixed(6)}°", style: const TextStyle(color: Color(0xFF00FF66), fontSize: 11, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Controls (Gallery, Shutter Button)
          Positioned(
            bottom: 25,
            left: 30,
            right: 30,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 🖼️ Multi-Photo Gallery Thumbnail
                GestureDetector(
                  onTap: _openGallery,
                  child: Container(
                    width: 55,
                    height: 55,
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFCC00), width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _capturedPhotos.isNotEmpty
                        ? Image.memory(_capturedPhotos[0], fit: BoxFit.cover)
                        : const Icon(Icons.photo_library, color: Color(0xFFFFCC00), size: 28),
                  ),
                ),

                // Golden Glowing Shutter Button
                GestureDetector(
                  onTap: _isProcessing ? null : _captureAndStamp,
                  child: Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: const [BoxShadow(color: Color(0x66FFCC00), blurRadius: 20)],
                    ),
                    child: Center(
                      child: Container(
                        width: 66,
                        height: 66,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFFFFDD00), Color(0xFFFF8800)],
                          ),
                        ),
                        child: _isProcessing
                            ? const CircularProgressIndicator(color: Colors.black)
                            : const Icon(Icons.camera_alt, color: Colors.black, size: 34),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 55),
              ],
            ),
          ),
        ],
      ),
    );
  }
}