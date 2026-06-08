import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// ClearCall 信令中继服务器 — 极简 WebSocket 房间消息转发
///
/// REST API：
///   POST /rooms                   创建房间 → {"roomId":"123456","status":"waiting"}
///   GET  /rooms/{roomId}         查询房间（人数、参与者）
///   GET  /health                  健康检查 + 运行统计
///
/// WebSocket 接入点：
///   WS  /ws                       客户端连接后发送 join 消息绑定房间
///
/// 消息协议（JSON）：
///   →  client→server
///   {"type":"join","roomId":"123456","from":"uid","data":{"nickname":"..."}}
///   {"type":"sdp",  "from":"uid","to":"uid","data":{"type":"offer/answer","sdp":"..."}}
///   {"type":"ice",  "from":"uid","to":"uid","data":{"candidate":"...","sdpMid":"0","sdpMLineIndex":0}}
///   {"type":"leave","from":"uid"}
///   {"type":"ping", "from":"uid"}
///   ←  server→client
///   {"type":"joined","from":"server","data":{"roomId":"...","participants":["..."],"status":"active"}}
///   {"type":"join","from":"uid","data":{}}           // 其他人加入
///   {"type":"leave","from":"uid","data":{}}          // 其他人离开
///   {"type":"error","from":"server","data":{"message":"..."}}
///   {"type":"pong","from":"server"}
///
/// 运行：
///   dart run server.dart --port=8080
void main(List<String> args) async {
  final port = int.tryParse(
        args.firstWhere((a) => a.startsWith('--port='), orElse: () => '--port=8080').split('=').last,
      ) ??
      8080;

  final wsHandler = webSocketHandler(_handleWebSocket);

  final cascade = Cascade()
      .add(wsHandler)
      .add(_router);

  final app = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(cascade.handler);

  await io.serve(app, '0.0.0.0', port);
  print('🔌 ClearCall 信令中继 已启动 → ws://0.0.0.0:$port/ws');
  print('   POST /rooms    创建房间');
  print('   GET  /rooms/id 查询房间');
  print('   GET  /health   健康检查');
}

// ════════════════════════════════════════════════
// 房间管理（纯内存）
// ════════════════════════════════════════════════

final Map<String, _Room> _rooms = {};

Handler get _router => (Request request) {
  final path = request.url.path;
  final segs = path.split('/').where((s) => s.isNotEmpty).toList();

  // POST /rooms
  if (request.method == 'POST' && segs.isEmpty) {
    final id = _genRoomId();
    while (_rooms.containsKey(id)) {
      // 极低概率冲突，重新生成
    }
    _rooms[id] = _Room(id: id, createdAt: DateTime.now());
    _startCleanup();
    print('🏠 房间 $id 已创建');
    return Response.ok(
      jsonEncode({'roomId': id, 'status': 'waiting'}),
      headers: {_jsonHdr: 'application/json'},
    );
  }

  // GET /rooms/{id}
  if (request.method == 'GET' && segs.length == 1) {
    final room = _rooms[segs[0]];
    if (room == null) {
      return Response.notFound(
        jsonEncode({'error': '房间不存在', 'code': 'not_found'}),
      );
    }
    final pids = room.channels.keys.toList();
    return Response.ok(jsonEncode({
      'roomId': segs[0],
      'status': pids.isEmpty ? 'waiting' : 'active',
      'participantCount': pids.length,
      'participantIds': pids,
      'maxParticipants': 3,
    }), headers: {_jsonHdr: 'application/json'});
  }

  // GET /health
  if (segs.isNotEmpty && segs[0] == 'health') {
    return Response.ok(jsonEncode({
      'status': 'ok',
      'rooms': _rooms.length,
      'connections': _rooms.values.fold<int>(0, (s, r) => s + r.channels.length),
    }), headers: {_jsonHdr: 'application/json'});
  }

  // GET / — 首页
  if (path.isEmpty || path == '/') {
    return Response.ok(
      'ClearCall Signaling Relay 🟢\n'
      'Rooms: ${_rooms.length} | '
      'Connections: ${_rooms.values.fold<int>(0, (s, r) => s + r.channels.length)}',
    );
  }

  return Response.notFound('Not Found');
};

const _jsonHdr = 'Content-Type';

// ════════════════════════════════════════════════
// WebSocket 处理
// ════════════════════════════════════════════════

void _handleWebSocket(WebSocketChannel ch, String? protocol) {
  final conn = _Conn(ch);
  _pending.add(conn);

  ch.stream.listen(
    (msg) => _onMessage(conn, msg as String),
    onDone: () => _onDisconnect(conn),
    onError: (e) {
      print('⚠️ WS 错误: $e');
      _onDisconnect(conn);
    },
  );
}

final List<_Conn> _pending = [];

void _onMessage(_Conn conn, String raw) {
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final type = m['type'] as String?;
    final from = m['from'] as String?;

    if (type == null || from == null) {
      _send(conn, {'type': 'error', 'from': 'server', 'data': {'message': '缺少 type 或 from'}});
      return;
    }

    // 必须先 join
    if (conn.roomId == null) {
      if (type != 'join') {
        _send(conn, {'type': 'error', 'from': 'server', 'data': {'message': '请先发送 join 消息'}});
        return;
      }
      final rid = m['roomId'] as String?;
      if (rid == null) {
        _send(conn, {'type': 'error', 'from': 'server', 'data': {'message': 'join 必须包含 roomId'}});
        return;
      }
      _doJoin(conn, rid, from, m['data'] as Map<String, dynamic>?);
      return;
    }

    final room = _rooms[conn.roomId];
    if (room == null) {
      _send(conn, {'type': 'error', 'from': 'server', 'data': {'message': '房间不存在'}});
      return;
    }

    switch (type) {
      case 'sdp':
      case 'ice':
      case 'signal':
        _relay(room, from, raw);
        break;
      case 'leave':
        _doLeave(conn, room);
        _send(conn, {'type': 'left', 'from': 'server', 'data': {'message': '已离开'}});
        break;
      case 'ping':
        _send(conn, {'type': 'pong', 'from': 'server'});
        room.touch();
        break;
      default:
        _send(conn, {'type': 'error', 'from': 'server', 'data': {'message': '未知类型: $type'}});
    }
  } catch (e) {
    _sendSafe(conn, {'type': 'error', 'from': 'server', 'data': {'message': '消息格式错误: $e'}});
  }
}

void _doJoin(_Conn conn, String roomId, String userId, Map<String, dynamic>? extra) {
  final room = _rooms.putIfAbsent(roomId, () => _Room(id: roomId, createdAt: DateTime.now()));

  if (room.channels.length >= 3) {
    _send(conn, {'type': 'error', 'from': 'server', 'data': {'message': '房间已满（最多3人）'}});
    return;
  }

  conn.roomId = roomId;
  conn.userId = userId;
  room.channels[userId] = conn;

  final others = room.channels.keys.where((id) => id != userId).toList();

  // 告诉新加入的人
  _send(conn, {
    'type': 'joined',
    'from': 'server',
    'data': {'roomId': roomId, 'participants': others, 'status': 'active'},
  });

  // 广播给其他人
  _relay(room, userId, jsonEncode({'type': 'join', 'from': userId, 'data': extra ?? {}}));

  print('👤 $userId → 房间 $roomId（${room.channels.length}/3）');
}

void _doLeave(_Conn conn, _Room room) {
  final uid = conn.userId;
  if (uid == null) return;
  room.channels.remove(uid);
  _relay(room, uid, jsonEncode({'type': 'leave', 'from': uid, 'data': {}}));
  print('👋 $uid ← 房间 ${room.id}（${room.channels.length}/3）');
  if (room.channels.isEmpty) room.emptiedAt = DateTime.now();
}

void _onDisconnect(_Conn conn) {
  if (conn.roomId != null && conn.userId != null) {
    final room = _rooms[conn.roomId];
    if (room != null) {
      room.channels.remove(conn.userId);
      _relay(room, conn.userId!, jsonEncode({'type': 'leave', 'from': conn.userId, 'data': {}}));
      print('🔌 ${conn.userId} 断连 ← 房间 ${conn.roomId}');
      if (room.channels.isEmpty) room.emptiedAt = DateTime.now();
    }
  }
  _pending.remove(conn);
}

void _relay(_Room room, String fromUid, String raw) {
  for (final e in room.channels.entries) {
    if (e.key != fromUid) {
      try {
        e.value.channel.sink.add(raw);
      } catch (_) {}
    }
  }
}

void _send(_Conn conn, Map<String, dynamic> msg) {
  try {
    conn.channel.sink.add(jsonEncode(msg));
  } catch (_) {}
}

void _sendSafe(_Conn conn, Map<String, dynamic> msg) {
  try {
    conn.channel.sink.add(jsonEncode(msg));
  } catch (_) {}
}

// ════════════════════════════════════════════════
// 工具
// ════════════════════════════════════════════════

String _genRoomId() {
  final r = Random();
  return (100000 + r.nextInt(900000)).toString();
}

Timer? _cleanupTimer;
void _startCleanup() {
  _cleanupTimer ??= Timer.periodic(const Duration(minutes: 2), (_) {
    final now = DateTime.now();
    final dead = <String>[];
    _rooms.forEach((id, room) {
      final emptySince = room.emptiedAt;
      if (room.channels.isEmpty && emptySince != null && now.difference(emptySince).inMinutes >= 1) {
        dead.add(id);
      }
      if (now.difference(room.createdAt).inMinutes >= 30) {
        dead.add(id);
      }
    });
    for (final id in dead) {
      _rooms.remove(id);
      print('🧹 清理: $id');
    }
  });
}

class _Room {
  final String id;
  final DateTime createdAt;
  DateTime? emptiedAt;
  final Map<String, _Conn> channels = {};
  _Room({required this.id, required this.createdAt});
  void touch() => emptiedAt = null;
}

class _Conn {
  final WebSocketChannel channel;
  String? roomId;
  String? userId;
  _Conn(this.channel);
}
