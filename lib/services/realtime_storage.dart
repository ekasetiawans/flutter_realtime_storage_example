import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

class RealtimeStorage {
  final String baseURL;
  final String database;
  late final Dio _dio;
  late WebSocket _webSocket;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  RealtimeStorage({
    required this.baseURL,
    required this.database,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: '$baseURL/database/$database/',
        contentType: 'application/json',
        setRequestContentTypeWhenNoPayload: true,
        responseType: ResponseType.json,
      ),
    );

    _connectWebSocket();
  }

  final _webSocketReady = Completer<WebSocket>();
  Future<void> _connectWebSocket() async {
    try {
      final wsUrl = baseURL.replaceFirst('http', 'ws');
      _webSocket = await WebSocket.connect('$wsUrl/database/$database/');
      _webSocket.listen(
        (event) {
          final data = json.decode(event);
          _controller.add(data);
        },
        cancelOnError: false,
        onDone: () {
          if (!_isDisposed) {
            Future.delayed(const Duration(seconds: 1), _connectWebSocket);
          }
        },
        onError: (err) {
          print(err);
        },
      );

      if (!_webSocketReady.isCompleted) {
        _webSocketReady.complete(_webSocket);
      }

      final subs = List.from(_subscriptions);
      _subscriptions.clear();

      for (var sub in subs) {
        _sub(sub);
      }
    } catch (e) {
      if (!_isDisposed) {
        Future.delayed(const Duration(seconds: 1), _connectWebSocket);
      }
    }
  }

  final _subscriptions = <String>[];
  Future<void> _sub(String path) async {
    await _webSocketReady.future;
    if (_subscriptions.contains(path)) return;
    _subscriptions.add(path);
    _webSocket.add(json.encode({
      'command': 'sub',
      'path': path,
    }));
  }

  Future<void> _unsub(String path) async {
    await _webSocketReady.future;
    if (!_subscriptions.contains(path)) return;
    _subscriptions.remove(path);
    _webSocket.add(json.encode({
      'command': 'unsub',
      'path': path,
    }));
  }

  Collection collection(String path) {
    return Collection._(
      path: path,
      storage: this,
    );
  }

  Stream<DocumentSnapshot?> document(String path) async* {
    final segments = path.split('/');
    if (segments.length % 2 == 1) {
      throw Exception('path is not valid as document path');
    }

    final res = await _dio.get(path);
    if (res.statusCode == 200) {
      final snapshot = DocumentSnapshot._(
        data: res.data,
        storage: this,
        path: path,
      );
      yield snapshot;
    }

    _sub(path);
    yield* _controller.stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (event, sink) {
          final path = event['path'];
          if (path == path) {
            final command = event['event'];
            switch (command) {
              case 'update':
                final data = event['value'];
                if (data != null) {
                  final snapshot = DocumentSnapshot._(
                    data: data,
                    storage: this,
                    path: path,
                  );
                  sink.add(snapshot);
                  return;
                }
                break;

              case 'delete':
                sink.add(null);
                break;
              default:
            }
          }
        },
        handleDone: (sink) => sink.close(),
        handleError: (error, stackTrace, sink) =>
            sink.addError(error, stackTrace),
      ),
    );
  }

  bool _isDisposed = false;
  void dispose() {
    _isDisposed = true;
    _controller.close();
    _webSocket.close();
  }
}

class Collection {
  final String _path;
  final RealtimeStorage _storage;

  Collection._({required String path, required RealtimeStorage storage})
      : _storage = storage,
        _path = path;

  Stream<List<DocumentSnapshot>> stream() async* {
    final segments = _path.split('/');
    if (segments.length % 2 == 0) {
      throw Exception('path is not valid as collection path');
    }

    final res = await _storage._dio.get(_path);
    List<DocumentSnapshot> list = [];
    if (res.statusCode == 200) {
      if (res.data is List) {
        list = (res.data as List)
            .map((e) => DocumentSnapshot._(
                  data: e,
                  storage: _storage,
                  path: _path + '/' + e['_id'],
                ))
            .toList();
        yield list;
      }
    }

    _storage._sub(_path);
    yield* _storage._controller.stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (event, sink) {
          final path = event['path'];
          if (path == path) {
            final command = event['event'];
            switch (command) {
              case 'add':
                final data = event['value'];
                if (data != null) {
                  final snapshot = DocumentSnapshot._(
                    data: data,
                    storage: _storage,
                    path: path + '/' + data['_id'],
                  );
                  list.add(snapshot);
                  sink.add(list);
                }
                break;

              case 'update':
                final data = event['value'];
                if (data != null) {
                  final snapshot = DocumentSnapshot._(
                    data: data,
                    storage: _storage,
                    path: path + '/' + data['_id'],
                  );

                  final idx =
                      list.indexWhere((element) => element.id == snapshot.id);
                  if (idx >= 0) {
                    list[idx]._data = snapshot._data;
                    sink.add(list);
                  }
                }
                break;

              case 'delete':
                final data = event['value'];
                if (data != null) {
                  final docId = data['documentId'];
                  list.removeWhere((element) => element.id == docId);
                } else {
                  list.clear();
                }

                sink.add(list);
                break;
              default:
            }
          }
        },
        handleDone: (sink) => sink.close(),
        handleError: (error, stackTrace, sink) =>
            sink.addError(error, stackTrace),
      ),
    );
  }

  Future<DocumentSnapshot?> add(Map<String, dynamic> data) async {
    final res = await _storage._dio.post(
      _path,
      data: data,
    );

    if (res.statusCode == 200) {
      final result = DocumentSnapshot._(
        data: res.data,
        storage: _storage,
        path: _path + '/' + res.data['_id'],
      );

      return result;
    }
  }
}

class DocumentSnapshot {
  String get id => _data['_id'];
  late Map<String, dynamic> _data;
  final RealtimeStorage _storage;
  final String _path;

  DocumentSnapshot._({
    required Map<String, dynamic> data,
    required RealtimeStorage storage,
    required String path,
  })  : _path = path,
        _storage = storage,
        _data = data;

  dynamic operator [](String key) {
    return _data[key];
  }

  void operator []=(String key, dynamic value) {
    _data[key] = value;
  }

  Future<bool> update() async {
    final updated = Map.from(_data);
    updated.remove('_id');

    final res = await _storage._dio.put(
      _path,
      data: updated,
    );
    return res.statusCode == 200;
  }

  Future<bool> delete() async {
    final res = await _storage._dio.delete(_path);
    return res.statusCode == 200;
  }
}
