/**
 * ClearCall 信令中继 — Cloudflare Workers + Durable Objects
 *
 * 协议与 Dart 版 signaling_server/server.dart 完全兼容。
 *
 * REST API：
 *   POST /rooms              → 创建房间 → {"roomId":"123456"}
 *   GET  /rooms/{roomId}     → 查询房间 → {"participantCount":2,...}
 *   GET  /health             → 健康检查
 *
 * WebSocket：
 *   GET  /ws?room={id}&uid={uid}  → 升级为 WebSocket
 *   消息格式与 Dart 版完全一致（join/sdp/ice/leave/ping）
 *
 * 部署：
 *   cd signaling_server/cf-worker
 *   npm install
 *   npx wrangler deploy
 */

// ═══════════════════════════════════════════════════════════
// Durable Object：每个房间一个实例
// ═══════════════════════════════════════════════════════════

interface RoomConn {
  uid: string;
  ws: WebSocket;
}

export class RoomDO {
  private sessions: Map<string, WebSocket> = new Map();
  private roomId: string = '';
  private createdAt: number = Date.now();

  constructor(private state: DurableObjectState) {
    // 接受来自 Worker 的 WebSocket 连接
    state.acceptWebSocket();
  }

  /** Worker 将 WebSocket 请求转发到此处 */
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    // /status — 查询房间状态（供 Worker 调用）
    if (url.pathname === '/status') {
      const participants = await this.state.storage.get<string[]>('participants') || [];
      const roomId = (await this.state.storage.get<string>('roomId')) || url.searchParams.get('room') || '';
      return new Response(JSON.stringify({
        roomId,
        status: participants.length === 0 ? 'waiting' : 'active',
        participantCount: participants.length,
        participantIds: participants,
        maxParticipants: 3,
      }), { headers: { 'Content-Type': 'application/json' } });
    }

    // /ws — WebSocket 升级
    const uid = url.searchParams.get('uid') || 'unknown';
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.state.acceptWebSocket(server);
    server.serializeAttachment({ uid, pending: true } as any);
    return new Response(null, { status: 101, webSocket: client });
  }

  /** 收到客户端消息 */
  async webSocketMessage(ws: WebSocket, raw: string) {
    try {
      const msg = JSON.parse(raw);
      const type = msg.type as string;
      const from = msg.from as string;

      if (!type || !from) {
        this.send(ws, { type: 'error', from: 'server', data: { message: '缺少 type 或 from' } });
        return;
      }

      switch (type) {
        case 'join': {
          const roomId = msg.roomId as string;
          if (!roomId) {
            this.send(ws, { type: 'error', from: 'server', data: { message: 'join 必须包含 roomId' } });
            return;
          }

          // 检查满员
          if (this.sessions.size >= 3) {
            this.send(ws, { type: 'error', from: 'server', data: { message: '房间已满（最多3人）' } });
            return;
          }

          // 注册
          this.roomId = roomId;
          this.sessions.set(from, ws);
          ws.serializeAttachment({ uid: from } as any);

          // 告诉新加入者
          const others = [...this.sessions.keys()].filter((id) => id !== from);
          this.send(ws, {
            type: 'joined',
            from: 'server',
            data: { roomId, participants: others, status: 'active' },
          });

          // 广播给其他人
          this.relay(from, JSON.stringify({ type: 'join', from, data: msg.data || {} }));

          // 更新存储
          await this.state.storage.put('roomId', roomId);
          await this.state.storage.put('participants', [...this.sessions.keys()]);
          break;
        }

        case 'sdp':
        case 'ice':
        case 'signal':
          this.relay(from, raw);
          break;

        case 'leave':
          this.removeSession(from);
          this.send(ws, { type: 'left', from: 'server', data: { message: '已离开' } });
          break;

        case 'ping':
          this.send(ws, { type: 'pong', from: 'server' });
          // 刷新存活时间
          await this.state.storage.put('lastActivity', Date.now());
          break;

        default:
          this.send(ws, { type: 'error', from: 'server', data: { message: `未知类型: ${type}` } });
      }
    } catch (e: any) {
      this.send(ws, { type: 'error', from: 'server', data: { message: `消息格式错误: ${e.message}` } });
    }
  }

  /** 客户端断开 */
  async webSocketClose(ws: WebSocket) {
    const attach = ws.deserializeAttachment() as any;
    if (attach?.uid) {
      this.removeSession(attach.uid);
    }
  }

  async webSocketError(ws: WebSocket, _error: unknown) {
    const attach = ws.deserializeAttachment() as any;
    if (attach?.uid) {
      this.removeSession(attach.uid);
    }
  }

  /** 清理并设置自动销毁 alarm */
  private async removeSession(uid: string) {
    this.sessions.delete(uid);
    this.relay(uid, JSON.stringify({ type: 'leave', from: uid, data: {} }));

    if (this.sessions.size === 0) {
      // 10 分钟后自动销毁
      await this.state.storage.setAlarm(Date.now() + 10 * 60 * 1000);
    }
  }

  /** alarm 触发 → 自毁 */
  async alarm() {
    if (this.sessions.size === 0) {
      await this.state.storage.deleteAll();
    }
  }

  /** 转发消息给房间内其他人 */
  private relay(fromUid: string, raw: string) {
    for (const [uid, ws] of this.sessions) {
      if (uid !== fromUid) {
        try { ws.send(raw); } catch (_) {}
      }
    }
  }

  private send(ws: WebSocket, msg: Record<string, unknown>) {
    try { ws.send(JSON.stringify(msg)); } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════
// Worker 入口：处理 HTTP 请求
// ═══════════════════════════════════════════════════════════

function corsHeaders(): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Content-Type': 'application/json',
  };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // CORS 预检
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders() });
    }

    const url = new URL(request.url);
    const path = url.pathname;
    const segs = path.split('/').filter((s) => s.length > 0);

    // POST /rooms — 创建房间
    if (request.method === 'POST' && path === '/rooms') {
      const roomId = String(Math.floor(100000 + Math.random() * 900000));
      // 获取或创建 DO（预创建，不占资源直到有连接）
      const doId = env.ROOM.idFromName(roomId);
      return new Response(JSON.stringify({ roomId, status: 'waiting' }), {
        headers: corsHeaders(),
      });
    }

    // GET /rooms/:id — 查询房间
    if (request.method === 'GET' && segs.length === 2 && segs[0] === 'rooms') {
      const roomId = segs[1];
      const doId = env.ROOM.idFromName(roomId);
      const stub = env.ROOM.get(doId);
      // 通过 HTTP 查询 DO 状态（用 fetch 到 DO）
      const doUrl = new URL('https://do.local/status');
      doUrl.searchParams.set('room', roomId);
      try {
        const resp = await stub.fetch(new Request(doUrl));
        const data: any = await resp.json();
        return new Response(JSON.stringify(data), { headers: corsHeaders() });
      } catch {
        return new Response(JSON.stringify({ roomId, participantCount: 0, status: 'waiting' }), {
          headers: corsHeaders(),
        });
      }
    }

    // GET /health — 健康检查
    if (path === '/health') {
      return new Response(JSON.stringify({ status: 'ok', platform: 'Cloudflare Workers' }), {
        headers: corsHeaders(),
      });
    }

    // GET /ws?room=xxx&uid=xxx — WebSocket 升级
    if (path === '/ws') {
      const roomId = url.searchParams.get('room');
      const uid = url.searchParams.get('uid');

      if (!roomId || !uid) {
        return new Response(JSON.stringify({ error: '缺少 room 或 uid 参数' }), {
          status: 400,
          headers: corsHeaders(),
        });
      }

      // 创建或获取房间 DO
      const doId = env.ROOM.idFromName(roomId);
      const stub = env.ROOM.get(doId);

      // 将请求转发到 DO（DO 内部创建 WebSocket）
      const doUrl = new URL('https://do.local/ws');
      doUrl.searchParams.set('uid', uid);
      return stub.fetch(new Request(doUrl));
    }

    // 首页
    if (path === '/' || path === '') {
      return new Response('ClearCall Signaling Relay 🟢 — Cloudflare Workers', {
        headers: { ...corsHeaders(), 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

    return new Response('Not Found', { status: 404 });
  },
};

// ═══════════════════════════════════════════════════════════
// 类型定义
// ═══════════════════════════════════════════════════════════

interface Env {
  ROOM: DurableObjectNamespace<RoomDO>;
}
