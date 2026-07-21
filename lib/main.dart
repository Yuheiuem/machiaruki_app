import 'dart:async';
import 'dart:convert';

// Flutter Webでファイルダウンロードを使うため
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const String appVersion = 'v1.50';  //バージョン表示



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

  final String memoId;
  final String memoType;
  final String memoTypeLabel;
  final String formVersion;
  final List<Map<String, String>> answers;

  MemoPoint({
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.memo,
    required this.isTestData,
    required this.memoId,
    required this.memoType,
    required this.memoTypeLabel,
    required this.formVersion,
    required this.answers,
  });
}

enum AppStep {
  departureCheck,
  recording,
  saveRecord,
  finishCheck,
}

enum RecordStatus {
  notStarted,
  recording,
  paused,
  finished,
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
  RecordStatus recordStatus = RecordStatus.notStarted;
  DateTime? pausedAt;
  String pausedElapsedText = '0秒';
  Timer? pauseTimer;
  String memoFormVersion = 'unknown';
  List<Map<String, dynamic>> memoFormCategories = [];
  String selectedMemoType = '';
  Map<String, String> memoAnswers = {};
  int memoFormResetCount = 0;
  bool isMemoFormConfigLoaded = false;


  final String checkAppsScriptUrl =
     'https://script.google.com/macros/s/AKfycbwsXNA0zpEEbzFnMRLt2kIYmaMaaKoDs50lllgDevq64EInOObKtAKWdFa5yI1TNSqm/exec';
  final String checkKey = 'machiaruki-check-key';
  //出発終了確認
  final String googleAppsScriptUrl = 
     'https://script.google.com/macros/s/AKfycbxsUODDG7nWFkl7o-LDMMEZG1mG20JXxH94PnJN16fWZGNhxuH984NOm499tE6GZBr4/exec';
  final String uploadKey = 'machiaruki-test-key';
  //GoosleDrive送信用
  final String routeMapPageUrl =
    'https://yuheiuem.github.io/machiaruki_app/route_map/';
  //参加者の歩いたルート表示用
  // 動作モード
  // test: PCテスト用。GPS失敗時にテスト座標を使う
  // production: 実運用。GPS失敗時や精度不良時は記録しない
  String operationMode = 'production';

  bool isRecording = false;
  int testCount = 0;

  Timer? timer;
  List<TrackPoint> trackPoints = [];
  List<MemoPoint> memoPoints = [];

  List<TrackPoint> mapTrackPoints = [];
  List<MemoPoint> mapMemoPoints = [];
   int mapUpdateCount = 0;

  final TextEditingController memoController = TextEditingController();



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

  Future<void> loadMemoFormConfig() async {
    try {
      final configUrl = Uri.base.resolve('memo_form_config.json').toString();

      final text = await html.HttpRequest.getString(
        '$configUrl?t=${DateTime.now().millisecondsSinceEpoch}',
      );

      final decoded = jsonDecode(text) as Map<String, dynamic>;

      final rawCategories = decoded['categories'];

      if (rawCategories is! List) {
        setState(() {
          isMemoFormConfigLoaded = false;
          statusText = 'メモ項目設定を読み込めませんでした';
        });
        return;
      }

      final categories = rawCategories
          .whereType<Map>()
          .map((category) => Map<String, dynamic>.from(category))
          .toList();

      if (categories.isEmpty) {
        setState(() {
          isMemoFormConfigLoaded = false;
          statusText = 'メモ項目設定を読み込めませんでした';
        });
        return;
      }

      setState(() {
        memoFormVersion = decoded['version']?.toString() ?? 'unknown';
        memoFormCategories = categories;
        selectedMemoType = categories.first['id'].toString();
        memoAnswers.clear();
        memoFormResetCount++;
        isMemoFormConfigLoaded = true;
      });
    } catch (e) {
      setState(() {
        isMemoFormConfigLoaded = false;
        statusText = 'メモ項目設定の読み込みに失敗しました';
      });
    }
  }

  Map<String, dynamic>? getSelectedMemoCategory() {
    for (final category in memoFormCategories) {
      if (category['id'] == selectedMemoType) {
        return category;
      }
    }

    if (memoFormCategories.isNotEmpty) {
      return memoFormCategories.first;
    }

    return null;
  }

  List<Map<String, dynamic>> getSelectedMemoFields() {
    final category = getSelectedMemoCategory();

    if (category == null) {
      return [];
    }

    final rawFields = category['fields'];

    if (rawFields is! List) {
      return [];
    }

    return rawFields
        .whereType<Map>()
        .map((field) => Map<String, dynamic>.from(field))
        .toList();
  }

String formatClockTime(DateTime dateTime) {
  String twoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }

  final hour = twoDigits(dateTime.hour);
  final minute = twoDigits(dateTime.minute);

  return '$hour:$minute';
}

String formatDurationText(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours時間$minutes分$seconds秒';
  }

  if (minutes > 0) {
    return '$minutes分$seconds秒';
  }

  return '$seconds秒';
}

  String escapeCsvValue(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

String createMemoColumnName(Map<String, String> field) {
  final fieldId = field['fieldId'] ?? '';
  final fieldLabel = field['fieldLabel'] ?? fieldId;

  if (fieldId.isEmpty) {
    return fieldLabel;
  }

  return '${fieldId}__$fieldLabel';
}

List<Map<String, String>> getMemoFieldColumnsForCsv() {
  final columns = <Map<String, String>>[];
  final seenFieldIds = <String>{};

  for (final category in memoFormCategories) {
    final rawFields = category['fields'];

    if (rawFields is! List) {
      continue;
    }

    for (final rawField in rawFields) {
      if (rawField is! Map) {
        continue;
      }

      final field = Map<String, dynamic>.from(rawField);

      final fieldId = field['id']?.toString() ?? '';

      if (fieldId.isEmpty || seenFieldIds.contains(fieldId)) {
        continue;
      }

      seenFieldIds.add(fieldId);

      columns.add({
        'fieldId': fieldId,
        'fieldLabel': field['label']?.toString() ?? fieldId,
      });
    }
  }

  // 念のため、既に記録済みのメモにだけ存在する項目も拾う
  for (final memoPoint in memoPoints) {
    for (final answer in memoPoint.answers) {
      final fieldId = answer['fieldId'] ?? '';

      if (fieldId.isEmpty || seenFieldIds.contains(fieldId)) {
        continue;
      }

      seenFieldIds.add(fieldId);

      columns.add({
        'fieldId': fieldId,
        'fieldLabel': answer['fieldLabel'] ?? fieldId,
      });
    }
  }

  return columns;
}

String createMemoCsvText() {
  final fieldColumns = getMemoFieldColumnsForCsv();

  final headerColumns = [
    'memo_id',
    'recorder_name',
    'memo_type',
    'memo_type_label',
    ...fieldColumns.map(createMemoColumnName),
    'recorded_at',
    'latitude',
    'longitude',
    'operation_mode',
    'is_test_data',
    'server_saved_at',
    'form_version',
  ];

  final lines = <String>[
    headerColumns.map(escapeCsvValue).join(','),
  ];

  final safeRecorderName =
      recorderName.trim().isEmpty ? 'unknown' : recorderName.trim();

  for (final memoPoint in memoPoints) {
    final answerMap = <String, String>{};

    for (final answer in memoPoint.answers) {
      final fieldId = answer['fieldId'] ?? '';

      if (fieldId.isNotEmpty) {
        answerMap[fieldId] = answer['answer'] ?? '';
      }
    }

    final rowColumns = [
      memoPoint.memoId,
      safeRecorderName,
      memoPoint.memoType,
      memoPoint.memoTypeLabel,
      ...fieldColumns.map((field) {
        final fieldId = field['fieldId'] ?? '';
        return answerMap[fieldId] ?? '';
      }),
      formatDateTime(memoPoint.time),
      memoPoint.latitude.toStringAsFixed(6),
      memoPoint.longitude.toStringAsFixed(6),
      operationMode,
      memoPoint.isTestData.toString(),
      '',
      memoPoint.formVersion,
    ];

    lines.add(rowColumns.map(escapeCsvValue).join(','));
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

  void startLocationRecordingTimer() {
  timer?.cancel();

  addTrackPoint();

  timer = Timer.periodic(
    const Duration(seconds: 5),
    (timer) {
      addTrackPoint();
    },
  );
}

  void startRecording() {
  pauseTimer?.cancel();

  setState(() {
    isRecording = true;
    recordStatus = RecordStatus.recording;
    currentStep = AppStep.recording;
    statusText = '記録を開始しました';
    trackPoints.clear();
    memoPoints.clear();
    mapTrackPoints.clear();
    mapMemoPoints.clear();
    geoJsonText = '';
    testCount = 0;
    latitudeText = '未取得';
    longitudeText = '未取得';
    pausedAt = null;
    pausedElapsedText = '0秒';
  });

  startLocationRecordingTimer();
}

 void pauseRecording() {
  timer?.cancel();

  setState(() {
    isRecording = false;
    recordStatus = RecordStatus.paused;
    pausedAt = DateTime.now();
    pausedElapsedText = '0秒';
    statusText = '記録を一時停止しています';
  });

  startPauseTimer();
}

void resumeRecording() {
  pauseTimer?.cancel();

  setState(() {
    isRecording = true;
    recordStatus = RecordStatus.recording;
    pausedAt = null;
    pausedElapsedText = '0秒';
    statusText = '記録を再開しました';
  });

  startLocationRecordingTimer();
}

void finishRecording() {
  timer?.cancel();
  pauseTimer?.cancel();

  setState(() {
    isRecording = false;
    recordStatus = RecordStatus.finished;
    currentStep = AppStep.saveRecord;
    statusText = '記録を終了しました。保存/送信用データを作成してください';
  });
}

  Future<void> addMemoPoint() async {
  final selectedCategory = getSelectedMemoCategory();
  final fields = getSelectedMemoFields();

  if (selectedCategory == null || fields.isEmpty) {
    setState(() {
      statusText = 'メモ項目設定を読み込めていません';
    });
    return;
  }

  final memoType = selectedCategory['id'].toString();
  final memoTypeLabel = selectedCategory['label'].toString();

  final answers = <Map<String, String>>[];

  for (final field in fields) {
    final fieldId = field['id'].toString();
    final fieldLabel = field['label'].toString();
    final required = field['required'] == true;
    final answer = (memoAnswers[fieldId] ?? '').trim();

    if (required && answer.isEmpty) {
      setState(() {
        statusText = '$fieldLabel を入力してください';
      });
      return;
    }

    if (answer.isNotEmpty) {
      answers.add({
        'fieldId': fieldId,
        'fieldLabel': fieldLabel,
        'answer': answer,
      });
    }
  }

  if (answers.isEmpty) {
    setState(() {
      statusText = 'メモ内容を入力してください';
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

  final now = DateTime.now();
  final memoId = 'memo_${now.microsecondsSinceEpoch}';

  final summaryText = '$memoTypeLabel：${answers.map((answer) {
    return '${answer['fieldLabel']}=${answer['answer']}';
  }).join(' / ')}';

  final memoPoint = MemoPoint(
    time: now,
    latitude: point.latitude,
    longitude: point.longitude,
    memo: summaryText,
    isTestData: point.isTestData,
    memoId: memoId,
    memoType: memoType,
    memoTypeLabel: memoTypeLabel,
    formVersion: memoFormVersion,
    answers: answers,
  );

  setState(() {
  memoPoints.add(memoPoint);

  latitudeText = roundTo6(point.latitude).toString();
  longitudeText = roundTo6(point.longitude).toString();

  memoAnswers.clear();
  memoFormResetCount++;
  statusText = 'メモ地点を記録し、Google Driveへ送信しました';
});

  sendMemoToGoogleDrive(memoPoint);
}
 
  void updateMapPreview() {
  setState(() {
    mapTrackPoints = List.from(trackPoints);
    mapMemoPoints = List.from(memoPoints);
    mapUpdateCount++;

    statusText = '地図プレビューを更新しました';
  });
}

void updatePausedElapsedText() {
  if (pausedAt == null || !mounted) {
    return;
  }

  final elapsed = DateTime.now().difference(pausedAt!);

  setState(() {
    pausedElapsedText = formatDurationText(elapsed);
  });
}

void startPauseTimer() {
  pauseTimer?.cancel();

  updatePausedElapsedText();

  pauseTimer = Timer.periodic(
    const Duration(seconds: 1),
    (timer) {
      updatePausedElapsedText();
    },
  );
}

  void createGeoJson() {
    if (trackPoints.length < 2) {
      setState(() {
        geoJsonText = '';
        statusText = 'ルート記録を作るには2点以上の記録が必要です';
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

Future<void> sendMemoToGoogleDrive(MemoPoint memoPoint) async {
  html.IFrameElement? iframe;
  html.FormElement? form;

  try {
    final recorder =
        recorderName.trim().isEmpty ? 'unknown' : recorderName.trim();

    final frameName =
        'memo_upload_iframe_${DateTime.now().microsecondsSinceEpoch}';

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
    addField('uploadType', 'memo');
    addField('recorderName', recorder);
    addField('memoId', memoPoint.memoId);
    addField('memoType', memoPoint.memoType);
    addField('memoTypeLabel', memoPoint.memoTypeLabel);
    addField('formVersion', memoPoint.formVersion);
    addField('answersJson', jsonEncode(memoPoint.answers));
    addField('fieldColumnsJson', jsonEncode(getMemoFieldColumnsForCsv()));
    addField('recordedAt', formatDateTime(memoPoint.time));
    addField('latitude', memoPoint.latitude.toStringAsFixed(6));
    addField('longitude', memoPoint.longitude.toStringAsFixed(6));
    addField('operationMode', operationMode);
    addField('isTestData', memoPoint.isTestData.toString());

    html.document.body!.append(form);

    form.submit();

    await Future.delayed(const Duration(seconds: 3));
  } catch (e) {
    setState(() {
      statusText = 'メモ送信に失敗しました。もう一度送信してください';
    });
  } finally {
    form?.remove();
    iframe?.remove();
  }
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
    final recorder =
        recorderName.trim().isEmpty ? 'unknown' : recorderName.trim();

    final frameName =
        'upload_iframe_${DateTime.now().microsecondsSinceEpoch}';

    final csvText = memoPoints.isEmpty ? '' : createMemoCsvText();

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
void initState() {
  super.initState();
  loadMemoFormConfig();
}

  @override
  void dispose() {
  timer?.cancel();
  pauseTimer?.cancel();
  memoController.dispose();
  super.dispose();
}

Widget buildStructuredMemoForm() {
  if (!isMemoFormConfigLoaded) {
    return const Text(
      'メモ項目設定を読み込み中です',
      textAlign: TextAlign.center,
    );
  }

  final selectedCategory = getSelectedMemoCategory();
  final fields = getSelectedMemoFields();

  if (selectedCategory == null || fields.isEmpty) {
    return const Text(
      '使用できるメモ項目がありません',
      textAlign: TextAlign.center,
    );
  }

  return Column(
    children: [
      const Text(
        'メモ種別',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),

      const SizedBox(height: 8),

      SegmentedButton<String>(
        segments: memoFormCategories.map((category) {
          return ButtonSegment<String>(
            value: category['id'].toString(),
            label: Text(category['label'].toString()),
          );
        }).toList(),
        selected: {selectedMemoType},
        onSelectionChanged: (selected) {
          setState(() {
            selectedMemoType = selected.first;
            memoAnswers.clear();
            memoFormResetCount++;
          });
        },
      ),

      const SizedBox(height: 16),

      ...fields.map((field) {
        final fieldId = field['id'].toString();
        final fieldLabel = field['label'].toString();
        final fieldType = field['type']?.toString() ?? 'text';
        final required = field['required'] == true;
        final rawOptions = field['options'];
        final options = rawOptions is List
            ? rawOptions.map((option) => option.toString()).toList()
            : <String>[];

        if (fieldType == 'select' && options.isNotEmpty) {
          final currentValue = memoAnswers[fieldId];
          final dropdownValue =
              options.contains(currentValue) ? currentValue : null;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              key: ValueKey('text-$selectedMemoType-$fieldId-$memoFormResetCount'),
              initialValue: dropdownValue,
              decoration: InputDecoration(
                labelText: required ? '$fieldLabel *' : fieldLabel,
                border: const OutlineInputBorder(),
              ),
              items: options.map((option) {
                return DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  memoAnswers[fieldId] = value;
                }
              },
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            key: ValueKey('$selectedMemoType-$fieldId-$memoFormResetCount'),
            initialValue: memoAnswers[fieldId] ?? '',
            decoration: InputDecoration(
              labelText: required ? '$fieldLabel *' : fieldLabel,
              border: const OutlineInputBorder(),
            ),
            maxLines: fieldType == 'multiline' ? 3 : 1,
            onChanged: (value) {
              memoAnswers[fieldId] = value;
            },
          ),
        );
      }),

      ElevatedButton(
        onPressed: isRecording ? addMemoPoint : null,
        child: const Text('メモを記録する'),
      ),
    ],
  );
}

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'まち歩きアプリ',
      home: Scaffold(
        appBar: AppBar(
  title: const Text('まち歩きアプリ'),
  actions: const [
    Padding(
      padding: EdgeInsets.only(right: 12),
      child: Center(
        child: Text(
          appVersion,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ),
  ],
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

  const Text(
    'ご参加ありがとうございます。お疲れ様でした',
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  ),

  const SizedBox(height: 16),

  ElevatedButton(
    onPressed: () {
      html.window.open(routeMapPageUrl, '_blank');
    },
    child: const Text('みんなの歩いたルートを見る'),
  ),

  const SizedBox(height: 16),

  const Text(
    '記録内容の確認',
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  ),

  const SizedBox(height: 16),

  const Text(
    'ルート確認',
    style: TextStyle(fontSize: 16),
  ),

  const SizedBox(height: 8),

  if (trackPoints.length < 2)
    const Text(
      'ルート表示には2点以上の記録が必要です',
      textAlign: TextAlign.center,
    )
  else ...[
    SizedBox(
      height: 300,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(
            trackPoints.last.latitude,
            trackPoints.last.longitude,
          ),
          initialZoom: 16,
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.machiaruki_app',
          ),

          PolylineLayer(
            polylines: [
              Polyline(
                points: trackPoints.map((point) {
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
            markers: memoPoints.map((memoPoint) {
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
  ],

  const SizedBox(height: 24),

  const Text(
    'メモ一覧',
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
  ),

  const SizedBox(height: 8),

  if (memoPoints.isEmpty)
    const Text('記録されたメモはありません')
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
    onPressed: memoPoints.isEmpty ? null : downloadMemoCsv, 
    child: const Text('メモ一覧CSVを端末保存'),
  ),
 ],
],


const SizedBox(height: 8),




if (currentStep == AppStep.recording ||
    currentStep == AppStep.saveRecord) ...[       //ここから非表示/表示切替

                  Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          operationMode == 'production'
                              ? '本番調査用'
                              : 'PC実験用',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: operationMode == 'production'
                                ? Colors.grey
                                : Colors.red,
                          ),
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          onPressed: recordStatus == RecordStatus.notStarted
                              ? () {
                                  setState(() {
                                    if (operationMode == 'production') {
                                      operationMode = 'test';
                                      statusText = 'PC実験用に切り替えました';
                                    } else {
                                      operationMode = 'production';
                                      statusText = '本番調査用に戻しました';
                                    }
                                  });
                                }
                              : null,
                          icon: const Icon(
                            Icons.science_outlined,
                            size: 16,
                          ),
                          label: Text(
                            operationMode == 'production'
                                ? 'PC実験用'
                                : '本番調査用に戻す',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    operationMode == 'production'
                        ? '通常はこのまま使用してください。GPS取得失敗時や精度25m超の点は記録しません。'
                        : 'PC実験用です。GPS取得に失敗した場合、テスト座標を記録します。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: operationMode == 'test'
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: operationMode == 'test'
                          ? Colors.red
                          : Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 24),

                  if (recordStatus != RecordStatus.paused) ...[
  Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      ElevatedButton(
        onPressed: recordStatus == RecordStatus.notStarted
            ? startRecording
            : null,
        child: const Text('記録開始'),
      ),

      const SizedBox(width: 16),

      ElevatedButton(
        onPressed: recordStatus == RecordStatus.recording
            ? pauseRecording
            : null,
        child: const Text('一時停止'),
      ),
    ],
  ),
],

if (recordStatus == RecordStatus.paused) ...[
  const SizedBox(height: 16),

  const Text(
    '記録を一時停止しています',
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  ),

  const SizedBox(height: 8),

  Text(
    pausedAt == null
        ? '停止時刻：未取得'
        : '停止時刻：${formatClockTime(pausedAt!)}',
    style: const TextStyle(fontSize: 15),
  ),

  const SizedBox(height: 4),

  Text(
    '停止してから：$pausedElapsedText',
    style: const TextStyle(fontSize: 15),
  ),

  const SizedBox(height: 12),

  const Text(
    '一時停止中に移動した場合、再開後のルートが不自然になる可能性があります。',
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: Colors.red,
    ),
  ),

  const SizedBox(height: 16),

  Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      ElevatedButton(
        onPressed: resumeRecording,
        child: const Text('記録を再開'),
      ),

      const SizedBox(width: 16),

      ElevatedButton(
        onPressed: finishRecording,
        child: const Text('記録終了'),
      ),
    ],
  ),
],


  if (currentStep == AppStep.recording &&
    recordStatus == RecordStatus.recording) ...[
  const SizedBox(height: 24),

    buildStructuredMemoForm(),
  ],

                  const SizedBox(height: 24),

                 ElevatedButton(
                    onPressed: (currentStep == AppStep.saveRecord && !isRecording)
                   ? createGeoJson
                        : null,
                    child: const Text('保存/送信用ルート記録作成'),
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
                      'ルートを管理用フォルダへ送信します。メモは記録時に逐次送信されます。',
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
