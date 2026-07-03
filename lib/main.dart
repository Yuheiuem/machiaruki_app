import 'dart:async';
import 'dart:convert';

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
  String geoJsonText = '';

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

      statusText = point.isTestData
          ? '記録中：テスト座標を追加しました'
          : '記録中：現在地を追加しました';
    });
  }

  void startRecording() {
    setState(() {
      isRecording = true;
      statusText = '記録を開始しました';
      trackPoints.clear();
      geoJsonText = '';
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

  void createGeoJson() {
    if (trackPoints.length < 2) {
      setState(() {
        geoJsonText = 'GeoJSONを作るには2点以上の記録が必要です';
      });
      return;
    }

    final coordinates = trackPoints.map((point) {
      return [
        point.longitude,
        point.latitude,
      ];
    }).toList();

    final geoJson = {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "geometry": {
            "type": "LineString",
            "coordinates": coordinates,
          },
          "properties": {
            "name": "walking route",
            "point_count": trackPoints.length,
            "created_at": DateTime.now().toIso8601String(),
            "is_test_data": trackPoints.any((point) => point.isTestData),
          }
        }
      ]
    };

    setState(() {
      geoJsonText = const JsonEncoder.withIndent('  ').convert(geoJson);
      statusText = 'GeoJSONを作成しました';
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
        body: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 160),
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

                  const SizedBox(height: 16),

                  ElevatedButton(
                    onPressed: isRecording ? null : createGeoJson,
                    child: const Text('GeoJSON作成'),
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

                  const SizedBox(height: 24),

                  if (geoJsonText.isNotEmpty)
                    Container(
                      width: double.infinity,
                      height: 220,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          geoJsonText,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}