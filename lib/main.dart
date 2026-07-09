import 'dart:async';
import 'dart:convert';

// Flutter Webでファイルダウンロードを使うため
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';


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

enum AppStep {
  departureCheck,
  recording,
  saveRecord,
  finishCheck,
}

class _MachiarukiAppState extends State<MachiarukiApp> {
  String statusText = '記録を開始してください';
  String latitudeText = '未取得';
  String longitudeText = '未取得';
  String geoJsonText = '';
  String recorderName = '';
  String checkType = '出発';
  bool hasStartedCheck = false;
  bool hasFinishedCheck = false;
  AppStep currentStep = AppStep.departureCheck;


  final String checkAppsScriptUrl =
     'https://script.google.com/macros/s/AKfycbyQNlGg8OTttkZob4rRSmSclN0M4krX3jboT0mk4IZrSOc5C3YEXL-XeqgFUBcx3CQh/exec';
  final String checkKey = 'machiaruki-check-key';
  //出発終了確認
  final String googleAppsScriptUrl = 
     'https://script.google.com/macros/s/AKfycbzgUobwgg5klknNQXKx_8wtXxJ2GoPsmwavZL4VFNobq6Lty0WdYmVkkW4gxMr2RgL60w/exec';
  final String uploadKey = 'machiaruki-test-key';
  //GoosleDrive送信用
  final String routeMapPageUrl =
    'https://script.google.com/macros/s/AKfycbzi92-RH7XEufG2Rjv5HJsdjj5W0yw6UGFBOa6xb00Gz020GsT_BeLO0HHIUFhOnNg9wA/exec';
  //参加者の歩いたルート表示用
  // 動作モード
  // test: PCテスト用。GPS失敗時にテスト座標を使う
  // production: 実運用。GPS失敗時や精度不良時は記録しない
  String operationMode = 'test';

  bool isRecording = false;
  int testCount = 0;

  Timer? timer;
  List<TrackPoint> trackPoints = [];
  List<MemoPoint> memoPoints = [];

  List<TrackPoint> mapTrackPoints = [];
  List<MemoPoint> mapMemoPoints = [];
   int mapUpdateCount = 0;

  final TextEditingController memoController = TextEditingController();

  final GlobalKey checkSectionKey = GlobalKey();

  double roundTo6(double value) {
    return double.parse(value.toStringAsFixed(6));
  }

  String formatDateTime(DateTime dateTime) {
  String twoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }

  final year = dateTime.year.toString();
  final month = twoDigits(dateTime.month);
  final day = twoDigits(dateTime.day);
  final hour = twoDigits(dateTime.hour);
  final minute = twoDigits(dateTime.minute);
  final second = twoDigits(dateTime.second);

  return '$year-$month-$day $hour:$minute:$second';
}

  String escapeCsvValue(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

String createMemoCsvText() {
  final lines = <String>[];

  lines.add('memo,time,latitude,longitude');

  for (final memoPoint in memoPoints) {
    lines.add([
      escapeCsvValue(memoPoint.memo),
      escapeCsvValue(formatDateTime(memoPoint.time)),
      memoPoint.latitude.toStringAsFixed(6),
      memoPoint.longitude.toStringAsFixed(6),
    ].join(','));
  }

  return lines.join('\n');
}

  Future<TrackPoint?> getCurrentTrackPoint() async {
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

      // 実運用では、accuracy が25mより悪い点は記録しない
      if (operationMode == 'production' && position.accuracy > 25) {
        return null;
      }

      return TrackPoint(
        time: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
        isTestData: false,
      );
    } catch (e) {
      // PCテスト用なら、GPS取得失敗時にテスト座標を返す
      if (operationMode == 'test') {
        testCount++;

        return TrackPoint(
          time: DateTime.now(),
          latitude: 35.690921 + (testCount * 0.00005),
          longitude: 139.700258 + (testCount * 0.00005),
          isTestData: true,
        );
      }

      // 実運用では、GPS取得失敗時は記録しない
      return null;
    }
  }

  Future<void> addTrackPoint() async {
    TrackPoint? point = await getCurrentTrackPoint();

    if (point == null) {
      setState(() {
        statusText = '位置情報を取得できなかったため、この点は記録しませんでした';
      });
      return;
    }

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
      mapTrackPoints.clear();
      mapMemoPoints.clear();
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
    currentStep = AppStep.saveRecord;
    statusText = '記録を停止しました。保存/送信用データを作成してください';
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

    TrackPoint? point = await getCurrentTrackPoint();

    if (point == null) {
      setState(() {
        statusText = '位置情報を取得できなかったため、メモを記録できませんでした';
      });
      return;
    }

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
 
  void updateMapPreview() {
  setState(() {
    mapTrackPoints = List.from(trackPoints);
    mapMemoPoints = List.from(memoPoints);
    mapUpdateCount++;

    statusText = '地図プレビューを更新しました';
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
        "operation_mode": operationMode,
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
          "operation_mode": operationMode,
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

  void downloadMemoCsv() {
  final csvText = createMemoCsvText();

  final now = DateTime.now();

  final safeRecorderName =
      recorderName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  final namePart = safeRecorderName.isEmpty ? 'unknown' : safeRecorderName;

  final fileName =
      'memo_${namePart}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.csv';

  final blob = html.Blob(
    ['\uFEFF$csvText'],
    'text/csv;charset=utf-8',
  );

  final url = html.Url.createObjectUrlFromBlob(blob);

  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();

  html.Url.revokeObjectUrl(url);

  setState(() {
    statusText = 'メモ一覧CSVをダウンロードしました';
  });
}

void scrollToCheckSection() {
  final targetContext = checkSectionKey.currentContext;

  if (targetContext == null) {
    return;
  }

  Scrollable.ensureVisible(
    targetContext,
    duration: const Duration(milliseconds: 500),
    curve: Curves.easeInOut,
    alignment: 0.1,
  );
}

Future<void> sendToGoogleDrive() async {
  if (geoJsonText.isEmpty) {
    setState(() {
      statusText = '先にルート記録を作成してください';
    });
    return;
  }

  setState(() {
    statusText = 'Google Driveへ送信中です...';
  });

  html.IFrameElement? iframe;
  html.FormElement? form;

  try {
    final csvText = createMemoCsvText();
    final recorder =
        recorderName.trim().isEmpty ? 'unknown' : recorderName.trim();

    final frameName =
        'upload_iframe_${DateTime.now().microsecondsSinceEpoch}';

    iframe = html.IFrameElement()
      ..name = frameName
      ..style.display = 'none';

    html.document.body!.append(iframe);

    form = html.FormElement()
      ..method = 'POST'
      ..action = googleAppsScriptUrl
      ..target = frameName
      ..style.display = 'none';

    void addField(String fieldName, String value) {
      final textarea = html.TextAreaElement()
        ..name = fieldName
        ..value = value;

      textarea.style.display = 'none';
      form!.append(textarea);
    }

    addField('uploadKey', uploadKey);
    addField('recorderName', recorder);
    addField('geoJsonText', geoJsonText);
    addField('csvText', csvText);

    html.document.body!.append(form);

    form.submit();

    setState(() {
      checkType = '終了';
      currentStep = AppStep.finishCheck;
      statusText = 'Google Driveへ送信しました。終了確認を送信してください';
     });


    await Future.delayed(const Duration(seconds: 5));
  } catch (e) {
    setState(() {
      statusText = 'Google Drive送信に失敗しました。もう一度送信してください';
    });
  } finally {
    form?.remove();
    iframe?.remove();
  }
}

Future<void> sendCheckRecord() async {
  final name = recorderName.trim();

  if (name.isEmpty) {
    setState(() {
      statusText = '先に記録者名を入力してください';
    });
    return;
  }

  setState(() {
    statusText = '$checkType確認を送信中です...';
  });

  html.IFrameElement? iframe;
  html.FormElement? form;

  try {
    final frameName =
        'check_iframe_${DateTime.now().microsecondsSinceEpoch}';

    iframe = html.IFrameElement()
      ..name = frameName
      ..style.display = 'none';

    html.document.body!.append(iframe);

    form = html.FormElement()
      ..method = 'POST'
      ..action = checkAppsScriptUrl
      ..target = frameName
      ..style.display = 'none';

    void addField(String fieldName, String value) {
      final textarea = html.TextAreaElement()
        ..name = fieldName
        ..value = value;

      textarea.style.display = 'none';
      form!.append(textarea);
    }

    addField('checkKey', checkKey);
    addField('name', name);
    addField('checkType', checkType);

    html.document.body!.append(form);

    form.submit();

    setState(() {
    if (checkType == '出発') {
    hasStartedCheck = true;
    hasFinishedCheck = false;
    currentStep = AppStep.recording;
    statusText = '出発確認を送信しました。記録を開始できます';
  }

    if (checkType == '終了') {
    hasFinishedCheck = true;
    statusText = '終了確認を送信しました';
  }
});

    await Future.delayed(const Duration(seconds: 3));
  } catch (e) {
    setState(() {
      statusText = '$checkType確認の送信に失敗しました。もう一度送信してください';
    });
  } finally {
    form?.remove();
    iframe?.remove();
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

        bottomNavigationBar: Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: Colors.white,
    border: Border(
      top: BorderSide(
        color: Colors.grey.shade300,
      ),
    ),
  ),
  child: SafeArea(
    child: Text(
      statusText,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    ),
  ),
),

        body: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 50),

                  Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),

                  const SizedBox(height: 24),

                  if (currentStep == AppStep.departureCheck) ...[
      TextField(
          readOnly: hasStartedCheck,
            decoration: InputDecoration(
            labelText: '記録者名',
            border: const OutlineInputBorder(),
            suffixText: hasStartedCheck ? '変更不可' : null,
            ),
     onChanged: (value) {
      if (!hasStartedCheck) {
        recorderName = value;
         }
       },
      ),

  const SizedBox(height: 24),

  const Text(
    '出発確認',
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  ),

  const SizedBox(height: 8),

  ElevatedButton(
    onPressed: () {
      checkType = '出発';
      sendCheckRecord();
    },
    child: const Text('出発確認を送信'),
  ),

  const SizedBox(height: 24),

  const Text(
    '出発確認を送信すると、記録画面に進みます',
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: Colors.red,
    ),
  ),
],

if (currentStep == AppStep.finishCheck) ...[
  const Text(
    '終了確認',
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  ),

  const SizedBox(height: 8),

  ElevatedButton(
    onPressed: hasFinishedCheck
        ? null
        : () {
            checkType = '終了';
            sendCheckRecord();
          },
    child: const Text('終了確認を送信'),
  ),

  if (hasFinishedCheck) ...[
    const SizedBox(height: 16),

    ElevatedButton(
    onPressed: () {
      html.window.open(routeMapPageUrl, '_blank');
    },
    child: const Text('みんなの歩いたルートを見る'),
    ),

   const SizedBox(height: 24),

   const Text(
    '必要な場合のみ端末に保存してください',
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
        ),
      ),

  const SizedBox(height: 8),

  ElevatedButton(
    onPressed: geoJsonText.isEmpty ? null : downloadGeoJson,
    child: const Text('ルート記録を端末保存'),
     ),

  const SizedBox(height: 8),

  ElevatedButton(
    onPressed: downloadMemoCsv,
    child: const Text('メモ一覧CSVを端末保存'),
     ),
   ],
],


const SizedBox(height: 8),




if (currentStep == AppStep.recording ||
    currentStep == AppStep.saveRecord) ...[       //ここから非表示/表示切替

                  const Text(
                    '動作モード',
                    style: TextStyle(fontSize: 16),
                  ),

                  const SizedBox(height: 8),

                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'test',
                        label: Text('PCテスト用'),
                      ),
                      ButtonSegment<String>(
                        value: 'production',
                        label: Text('実運用'),
                      ),
                    ],
                    selected: {operationMode},
                    onSelectionChanged:
                        (currentStep == AppStep.recording && !isRecording)
                            ? (Set<String> selected) {
                                setState(() {
                                  operationMode = selected.first;
                                });
                              }
                            : null,
                  ),

                  const SizedBox(height: 12),

                  Text(
                    operationMode == 'test'
                        ? 'PCテスト用：GPS取得に失敗した場合、テスト座標を記録します'
                        : '実運用：GPS取得失敗時や精度25m超の点は記録しません',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  ElevatedButton(
                    onPressed: (currentStep == AppStep.recording && !isRecording)
                        ? startRecording
                        : null,
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
                     onPressed: (currentStep == AppStep.recording && hasStartedCheck)
                         ? addMemoPoint
                         : null,
                    child: const Text('メモを記録する'),
                  ),

                  const SizedBox(height: 24),

                 ElevatedButton(
                    onPressed: (currentStep == AppStep.saveRecord && !isRecording)
                   ? createGeoJson
                        : null,
                    child: const Text('保存/送信用ルート・メモ記録作成'),
                  ),

                  if (currentStep == AppStep.saveRecord && geoJsonText.isNotEmpty) ...[
                    const SizedBox(height: 24),

                    const Text(
                      '記録をGoogle Driveへ送信',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'ルートとメモを管理用フォルダへ送信します',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13),
                    ),

                    const SizedBox(height: 12),

                    ElevatedButton(
                      onPressed: sendToGoogleDrive,
                      child: const Text('Google Driveへ送信'),
                    ),
                  ],

                  

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

const Text(
  '地図プレビュー',
  style: TextStyle(fontSize: 18),
),

const SizedBox(height: 8),

ElevatedButton(
  onPressed: (currentStep == AppStep.recording ||
          currentStep == AppStep.saveRecord)
      ? updateMapPreview
      : null,
  child: const Text('地図更新'),
),

const SizedBox(height: 8),

SizedBox(
  height: 300,
  child: FlutterMap(
    key: ValueKey(mapUpdateCount),
    options: MapOptions(
      initialCenter: mapTrackPoints.isNotEmpty
          ? LatLng(
              mapTrackPoints.last.latitude,
              mapTrackPoints.last.longitude,
            )
          : const LatLng(35.690921, 139.700258),
      initialZoom: 16,
    ),
    children: [
      TileLayer(
        urlTemplate: 'https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png', //地理院淡色地図
        userAgentPackageName: 'com.example.machiaruki_app',
      ),

      if (mapTrackPoints.length >= 2)
        PolylineLayer(
          polylines: [
            Polyline(
              points: mapTrackPoints.map((point) {
                return LatLng(
                  point.latitude,
                  point.longitude,
                );
              }).toList(),
              strokeWidth: 4,
              color: Colors.blue,
            ),
          ],
        ),

      MarkerLayer(
  markers: mapMemoPoints.map((memoPoint) {
    return Marker(
      point: LatLng(
        memoPoint.latitude,
        memoPoint.longitude,
      ),
      width: 40,
      height: 40,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          showDialog(
            context: context,
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: const Text('メモ'),
                content: Text(memoPoint.memo),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('閉じる'),
                  ),
                ],
              );
            },
          );
        },
        child: const Center(
          child: Icon(
            Icons.location_pin,
            size: 30,
            color: Colors.red,
          ),
        ),
      ),
    );
  }).toList(),
),
    ],
  ),
),

const SizedBox(height: 4),

const Align(
  alignment: Alignment.centerRight,
  child: Text(
    '出典：国土地理院（地理院タイル）',
    style: TextStyle(
      fontSize: 11,
      color: Colors.grey,
    ),
  ),
),

                  const SizedBox(height: 24),

                  const SizedBox(height: 24),

const Text(
  'メモ一覧',
  style: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  ),
),

const SizedBox(height: 8),

if (memoPoints.isEmpty)
  const Text('まだメモはありません')
else
  Column(
    children: memoPoints.map((memoPoint) {
      return Card(
        child: ListTile(
          title: Text(memoPoint.memo),
          subtitle: Text(
            '${formatDateTime(memoPoint.time)}\n'
            '緯度：${memoPoint.latitude.toStringAsFixed(6)} / '
            '経度：${memoPoint.longitude.toStringAsFixed(6)}',
          ),
        ),
      );
    }).toList(),
  ),
              

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
] //非表示/表示切替
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
