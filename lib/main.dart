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

class _MachiarukiAppState extends State<MachiarukiApp> {
  String latitudeText = '未取得';
  String longitudeText = '未取得';
  String statusText = 'ボタンを押してください';

  Future<void> getCurrentLocation() async {
    setState(() {
      statusText = '現在地を取得中...';
    });

    try {
      // 位置情報サービスが使える状態か確認
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        setState(() {
          statusText = '位置情報サービスがオフです。PCの設定で制限されている可能性があります';
        });
        return;
      }

      // 位置情報の許可状態を確認
      LocationPermission permission = await Geolocator.checkPermission();

      // まだ許可されていなければ、ブラウザに許可を求める
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // 拒否された場合
      if (permission == LocationPermission.denied) {
        setState(() {
          statusText = '位置情報の許可が拒否されました';
        });
        return;
      }

      // 完全に拒否されている場合
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          statusText = '位置情報が完全に拒否されています。ブラウザ設定を確認してください';
        });
        return;
      }

      // 現在地を取得。10秒で取れなければ失敗扱い
      Position position = await Geolocator.getCurrentPosition(
  locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.high,
    timeLimit: Duration(seconds: 10),
  ),
);

      setState(() {
        latitudeText = position.latitude.toString();
        longitudeText = position.longitude.toString();
        statusText = '現在地を取得しました';
      });
    } catch (e) {
      setState(() {
        statusText = '現在地を取得できませんでした。スマホ実機で確認しましょう';
      });
    }
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: getCurrentLocation,
                child: const Text('現在地を取得'),
              ),
              const SizedBox(height: 24),
              Text(
                statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              Text(
                '緯度：$latitudeText',
                style: const TextStyle(fontSize: 22),
              ),
              Text(
                '経度：$longitudeText',
                style: const TextStyle(fontSize: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}