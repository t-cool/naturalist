import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

void main() {
  runApp(const MyApp());
}

/// Flutter アプリ全体を構成するクラス
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Naturalist Memo Flutter',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

/// 住所やメモなどのレコードを表すクラス
class MemoRecord {
  final String time;
  final double lat;
  final double lng;
  String address;
  String memo;

  MemoRecord({
    required this.time,
    required this.lat,
    required this.lng,
    required this.address,
    required this.memo,
  });

  /// JSON 形式に変換
  Map<String, dynamic> toJson() {
    return {
      'time': time,
      'lat': lat,
      'lng': lng,
      'address': address,
      'memo': memo,
    };
  }

  /// JSON から MemoRecord インスタンスを生成
  factory MemoRecord.fromJson(Map<String, dynamic> json) {
    return MemoRecord(
      time: json['time'] as String,
      lat: json['lat'] as double,
      lng: json['lng'] as double,
      address: json['address'] as String,
      memo: json['memo'] as String,
    );
  }
}

/// メイン画面を表す StatefulWidget
class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

/// メイン画面のステート
class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _memoController = TextEditingController();
  List<MemoRecord> _records = [];
  bool _isOnline = true;
  String _currentAddress = '住所を取得中...';

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkConnectivity();
    _fetchLocationAndAddress();
  }

  /// 端末のオンライン・オフライン状態をチェック
  Future<void> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      _isOnline = connectivityResult != ConnectivityResult.none;
    });
  }

  /// 位置情報を取得し、住所を取得する
  Future<void> _fetchLocationAndAddress() async {
    try {
      // 位置情報を取得
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      // オンラインであれば住所を取得し、オフラインなら「未取得」とする
      if (_isOnline) {
        final address = await _fetchAddress(position.latitude, position.longitude);
        setState(() {
          _currentAddress = address;
        });
      } else {
        setState(() {
          _currentAddress = 'オフラインのため住所は未取得';
        });
      }
    } catch (e) {
      setState(() {
        _currentAddress = '住所の取得に失敗しました。';
      });
    }
  }

  /// 住所を OpenStreetMap Nominatim API から取得する
  Future<String> _fetchAddress(double lat, double lng) async {
    final endpoint = 'https://nominatim.openstreetmap.org/reverse';
    final params = {
      'lat': lat.toString(),
      'lon': lng.toString(),
      'format': 'json',
      'accept-language': 'ja',
    };
    final uri = Uri.parse(endpoint).replace(queryParameters: params);

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'] as String? ?? 'N/A';
        // 日本や郵便番号を削ぎ落として、逆順にして連結する例（任意の加工）
        final addressParts =
            displayName.split(',').map((part) => part.trim()).toList();
        // 例: 最後2つ（日本と郵便番号）を消し、逆順で結合
        final formatted = addressParts.length > 2
            ? addressParts.sublist(0, addressParts.length - 2).reversed.join('')
            : displayName;
        return formatted;
      } else {
        return '住所の取得に失敗しました。';
      }
    } catch (e) {
      return '住所の取得に失敗しました。';
    }
  }

  /// レコードを保存する（SharedPreferences に保存）
  Future<void> _saveData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final data = _records.map((record) => record.toJson()).toList();
    await prefs.setString('historyData', json.encode(data));
  }

  /// レコードを読み込む（SharedPreferences から読み込み）
  Future<void> _loadData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final historyString = prefs.getString('historyData');
    if (historyString != null) {
      final List decoded = json.decode(historyString);
      setState(() {
        _records = decoded.map((e) => MemoRecord.fromJson(e)).toList();
      });
    }
  }

  /// メモを保存ボタンを押したときの処理
  Future<void> _onSave() async {
    // 現在の時刻を整形
    final now = DateTime.now();
    final formattedTime =
        '${now.year}年${now.month.toString().padLeft(2, '0')}月${now.day.toString().padLeft(2, '0')}日'
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // 現在位置を取得し、住所を得る
    double lat = 0.0;
    double lng = 0.0;
    String address = '未取得';

    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      lat = position.latitude;
      lng = position.longitude;
      if (_isOnline) {
        address = await _fetchAddress(lat, lng);
      }
    } catch (e) {
      // 位置情報が取得できなかった場合
    }

    final newRecord = MemoRecord(
      time: formattedTime,
      lat: lat,
      lng: lng,
      address: address,
      memo: _memoController.text,
    );

    setState(() {
      _records.insert(0, newRecord); // 新しいデータを先頭に
      _memoController.clear();
    });

    await _saveData();
  }

  /// アドレスを更新ボタンを押したときの処理
  Future<void> _onUpdate(MemoRecord record) async {
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('オフラインです。更新できません。'),
        ),
      );
      return;
    }
    final newAddress = await _fetchAddress(record.lat, record.lng);
    setState(() {
      record.address = newAddress;
    });
    await _saveData();
  }

  /// レコード削除ボタン
  Future<void> _onDelete(MemoRecord record) async {
    setState(() {
      _records.remove(record);
    });
    await _saveData();
  }

  @override
  Widget build(BuildContext context) {
    // スマホでの操作性を優先し、全幅に近いフォームを用意
    return Scaffold(
      appBar: AppBar(
        title: const Text('Naturalist Memo Flutter移植版'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text(
              _currentAddress,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _memoController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'メモを入力',
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _onSave,
                  child: const Text('保存'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _exportDataAsCsv();
                  },
                  child: const Text('データをエクスポート'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '履歴',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _records.length,
              itemBuilder: (context, index) {
                final record = _records[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    title: Text('${record.time}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('住所: ${record.address}'),
                        Text('メモ: ${record.memo}'),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          onPressed: () => _onUpdate(record),
                          child: const Text('更新'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () => _onDelete(record),
                          child: const Text('削除'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// CSV 形式でエクスポートする（簡易実装）
  Future<void> _exportDataAsCsv() async {
    if (_records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('データがありません。'),
        ),
      );
      return;
    }

    // CSV ラインを組み立てる
    final headers = ['time', 'lat', 'lng', 'address', 'memo'];
    final rows = <String>[];
    rows.add(headers.join(','));
    for (final record in _records) {
      final values = [
        record.time,
        record.lat.toString(),
        record.lng.toString(),
        record.address.replaceAll(',', ' '), // カンマ除去など適宜処理
        record.memo.replaceAll(',', ' '),
      ];
      rows.add(values.map((val) => '"$val"').join(','));
    }
    final csvContent = rows.join('\n');

    // ここではダウンロードや外部への保存処理は省略
    // 実機端末でファイルに保存する際は path_provider 等を使います
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSVエクスポートのデータを出力しました（コンソールに表示）。'),
      ),
    );
    // デバッグ用にコンソール表示
    debugPrint(csvContent);
  }
}