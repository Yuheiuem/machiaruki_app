import 'dart:async';
import 'dart:convert';

// Flutter Webでファイルダウンロードを使うため
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

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

class MemoPoint {
  final DateTime time;
  final double latitude;
  final double longitude;
  final String memo;
  final bool isTestData;

  MemoPoint({
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.memo,
    required this.isTestData,
  });
}

class _MachiarukiAppState extends State<MachiarukiApp> {
  String statusText = '記録を開始してください';
  String latitudeText = '未取得';
  String longitudeText = '未取得';
  String geoJsonText = '';
  String recorderName = '';

  // 保存方法
  // download: 端末にダウンロード
  // googleDrive: 将来Google Drive送信用
  String saveMethod = 'download';

  bool isRecording = false;
  int testCount = 0;

  Timer? timer;
  List<TrackPoint> trackPoints = [];
  List<MemoPoint> memoPoints = [];

  final TextEditingController memoController = TextEditingController();

  double roundTo6(double value) {
    return double.parse(value.toStringAsFixed(6));
  }

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
      // PCでGPSが使えない場合のテスト座標
      // 新宿駅付近から少しずつ動く
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

      latitudeText = roundTo6(point.latitude).toString();
      longitudeText = roundTo6(point.longitude).toString();

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
      memoPoints.clear();
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

  Future<void> addMemoPoint() async {
    final memoText = memoController.text.trim();

    if (memoText.isEmpty) {
      setState(() {
        statusText = 'メモを入力してください';
      });
      return;
    }

    TrackPoint point = await getCurrentTrackPoint();

    setState(() {
      memoPoints.add(
        MemoPoint(
          time: DateTime.now(),
          latitude: point.latitude,
          longitude: point.longitude,
          memo: memoText,
          isTestData: point.isTestData,
        ),
      );

      latitudeText = roundTo6(point.latitude).toString();
      longitudeText = roundTo6(point.longitude).toString();

      memoController.clear();
      statusText = 'メモ地点を記録しました';
    });
  }

  void createGeoJson() {
    if (trackPoints.length < 2) {
      setState(() {
        geoJsonText = 'ルート記録を作るには2点以上の記録が必要です';
      });
      return;
    }

    final routeCoordinates = trackPoints.map((point) {
      return [
        roundTo6(point.longitude),
        roundTo6(point.latitude),
      ];
    }).toList();

    final routeFeature = {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": routeCoordinates,
      },
      "properties": {
        "feature_type": "route",
        "name": "walking route",
        "recorder_name": recorderName.isEmpty ? "unknown" : recorderName,
        "point_count": trackPoints.length,
        "created_at": DateTime.now().toIso8601String(),
        "is_test_data": trackPoints.any((point) => point.isTestData),
      }
    };

    final memoFeatures = memoPoints.map((memoPoint) {
      return {
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [
            roundTo6(memoPoint.longitude),
            roundTo6(memoPoint.latitude),
          ],
        },
        "properties": {
          "feature_type": "memo",
          "memo": memoPoint.memo,
          "recorder_name": recorderName.isEmpty ? "unknown" : recorderName,
          "recorded_at": memoPoint.time.toIso8601String(),
          "is_test_data": memoPoint.isTestData,
        }
      };
    }).toList();

    final geoJson = {
      "type": "FeatureCollection",
      "features": [
        routeFeature,
        ...memoFeatures,
      ]
    };

    setState(() {
      geoJsonText = const JsonEncoder.withIndent('  ').convert(geoJson);
      statusText = 'ルート記録を作成しました';
    });
  }

  void downloadGeoJson() {
    if (geoJsonText.isEmpty) {
      setState(() {
        statusText = '先にルート記録を作成してください';
      });
      return;
    }

    final now = DateTime.now();

    final safeRecorderName =
        recorderName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    final namePart = safeRecorderName.isEmpty ? 'unknown' : safeRecorderName;

    final fileName =
        'route_${namePart}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.geojson';

    final bytes = utf8.encode(geoJsonText);
    final blob = html.Blob(
      [bytes],
      'application/geo+json',
    );

    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();

    html.Url.revokeObjectUrl(url);

    setState(() {
      statusText = 'ルート記録ファイルをダウンロードしました';
    });
  }

  void saveRouteRecord() {
    if (saveMethod == 'download') {
      downloadGeoJson();
      return;
    }

    if (saveMethod == 'googleDrive') {
      setState(() {
        statusText = 'Google Driveへのルート記録送信はまだ未実装です';
      });
      return;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    memoController.dispose();
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
                  const SizedBox(height: 80),

                  Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),

                  const SizedBox(height: 24),

                  TextField(
                    decoration: const InputDecoration(
                      labelText: '記録者名',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      recorderName = value;
                    },
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

                  const SizedBox(height: 24),

                  TextField(
                    controller: memoController,
                    decoration: const InputDecoration(
                      labelText: 'メモ',
                      hintText: '例：歩道が狭い、休憩場所、見通しが悪い',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),

                  const SizedBox(height: 12),

                  ElevatedButton(
                    onPressed: addMemoPoint,
                    child: const Text('メモ記録'),
                  ),

                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: isRecording ? null : createGeoJson,
                    child: const Text('ルート記録作成'),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    '保存方法',
                    style: TextStyle(fontSize: 16),
                  ),

                  const SizedBox(height: 8),

                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'download',
                        label: Text('DL保存'),
                      ),
                      ButtonSegment<String>(
                        value: 'googleDrive',
                        label: Text('Drive送信'),
                      ),
                    ],
                    selected: {saveMethod},
                    onSelectionChanged: (Set<String> selected) {
                      setState(() {
                        saveMethod = selected.first;
                      });
                    },
                  ),

                  const SizedBox(height: 12),

                  ElevatedButton(
                    onPressed: isRecording ? null : saveRouteRecord,
                    child: const Text('ルート記録保存'),
                  ),

                  const SizedBox(height: 32),

                  Text(
                    '記録点数：${trackPoints.length}',
                    style: const TextStyle(fontSize: 22),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'メモ件数：${memoPoints.length}',
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