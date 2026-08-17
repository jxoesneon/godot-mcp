import net from 'net';

export interface BridgeResponse {
  id: string;
  status: 'ok' | 'error';
  result?: any;
  error?: string;
}

export class GodotEditorBridge {
  private host: string;
  private port: number;
  private timeoutMs: number;

  constructor(host = '127.0.0.1', port = 6505, timeoutMs = 8000) {
    this.host = host;
    this.port = port;
    this.timeoutMs = timeoutMs;
  }

  public async isEditorConnected(): Promise<boolean> {
    try {
      const res = await this.sendCommand('ping', {}, 2000);
      return res && res.status === 'ok';
    } catch {
      return false;
    }
  }

  public sendCommand(command: string, params: Record<string, any> = {}, customTimeout?: number): Promise<BridgeResponse> {
    return new Promise((resolve, reject) => {
      const reqId = `req_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
      const timeout = customTimeout || this.timeoutMs;

      const client = net.createConnection({ host: this.host, port: this.port }, () => {
        const payload = JSON.stringify({ id: reqId, command, params });
        client.write(payload);
      });

      let buffer = '';
      const timer = setTimeout(() => {
        try { client.destroy(); } catch {}
        reject(new Error(`Godot Editor TCP command '${command}' timed out after ${timeout}ms`));
      }, timeout);

      client.on('data', (chunk) => {
        buffer += chunk.toString();
        let jsonStr = buffer;
        const idx = buffer.indexOf('\r\n\r\n');
        if (idx !== -1) {
          jsonStr = buffer.substring(idx + 4);
        }
        try {
          const parsed = JSON.parse(jsonStr.trim()) as BridgeResponse;
          clearTimeout(timer);
          client.end();
          resolve(parsed);
        } catch {
          // Chunk is still streaming, wait for complete JSON object
        }
      });

      client.on('error', (err) => {
        clearTimeout(timer);
        reject(err);
      });
    });
  }
}
