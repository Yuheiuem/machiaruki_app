import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const MachiarukiApp());
}

class MachiarukiApp extends StatefulWidget {
  const MachiarukiApp({super.key});

  @override
  State<MachiarukiApp> createState() => _MachiarukiAppState();
}

class TrackPoint {
  final DateTime time;
  final double latitude;
  final double longitude;
  final bool isTestData;

  TrackPoint({
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.isTestData,
  });
}

class _MachiarukiAppState extends State<MachiarukiApp> {
  String statusText = '記録を開始してください';
  String latitudeText = '未取得';
  String longitudeText = '未取得';

  bool isRecording = false;
  int testCount = 0;

  Timer? timer;
  List<TrackPoint> trackPoints = [];

  Future<TrackPoint> getCurrentTrackPoint() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        throw Exception('位置情報サービスがオフです');
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('位置情報が許可されていません');
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return TrackPoint(
        time: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
        isTestData: false,
      );
    } catch (e) {
      // PCでGPSが取れないとき用のテスト座標
      // 新宿駅付近から少しずつ動くようにしている
      testCount++;

      return TrackPoint(
        time: DateTime.now(),
        latitude: 35.690921 + (testCount * 0.00005),
        longitude: 139.700258 + (testCount * 0.00005),
        isTestData: true,
      );
    }
  }

  Future<void> addTrackPoint() async {
    TrackPoint point = await getCurrentTrackPoint();

    setState(() {
      trackPoints.add(point);

      latitudeText = point.latitude.toString();
      longitudeText = point.longitude.toString();

      if (point.isTestData) {
        statusText = '記録中：テスト座標を追加しました';
      } else {
        statusText = '記録中：現在地を追加しました';
      }
    });
  }

  void startRecording() {
    setState(() {
      isRecording = true;
      statusText = '記録を開始しました';
      trackPoints.clear();
      testCount = 0;
      latitudeText = '未取得';
      longitudeText = '未取得';
    });

    addTrackPoint();

    timer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) {
        addTrackPoint();
      },
    );
  }

  void stopRecording() {
    timer?.cancel();

    setState(() {
      isRecording = false;
      statusText = '記録を停止しました';
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'まち歩きアプリ',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('まち歩きアプリ'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: isRecording ? null : startRecording,
                      child: const Text('記録開始'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: isRecording ? stopRecording : null,
                      child: const Text('記録停止'),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                Text(
                  '記録点数：${trackPoints.length}',
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(height: 16),

                Text(
                  '緯度：$latitudeText',
                  style: const TextStyle(fontSize: 20),
                ),
                Text(
                  '経度：$longitudeText',
                  style: const TextStyle(fontSize: 20),
                ),

                const SizedBox(height: 24),

                if (trackPoints.isNotEmpty)
                  Text(
                    trackPoints.last.isTestData
                        ? '現在はテスト座標で記録しています'
                        : '本物のGPS座標で記録しています',
                    style: const TextStyle(fontSize: 16),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}