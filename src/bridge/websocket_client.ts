import { WebSocket } from 'ws';

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

  constructor(host = '127.0.0.1', port = 6505, timeoutMs = 5000) {
    this.host = host;
    this.port = port;
    this.timeoutMs = timeoutMs;
  }

  public async isEditorConnected(): Promise<boolean> {
    try {
      const res = await this.sendCommand('ping', {}, 1500);
      return res.status === 'ok';
    } catch {
      return false;
    }
  }

  public sendCommand(command: string, params: Record<string, any> = {}, customTimeout?: number): Promise<BridgeResponse> {
    return new Promise((resolve, reject) => {
      const url = `ws://${this.host}:${this.port}`;
      const ws = new WebSocket(url);
      const reqId = `req_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`;
      const timeout = customTimeout || this.timeoutMs;

      const timer = setTimeout(() => {
        try {
          ws.close();
        } catch {}
        reject(new Error(`Godot Editor WebSocket command '${command}' timed out after ${timeout}ms`));
      }, timeout);

      ws.on('open', () => {
        const payload = JSON.stringify({ id: reqId, command, params });
        ws.send(payload);
      });

      ws.on('message', (data) => {
        clearTimeout(timer);
        try {
          const parsed = JSON.parse(data.toString()) as BridgeResponse;
          ws.close();
          resolve(parsed);
        } catch (err: any) {
          ws.close();
          reject(new Error(`Failed to parse response from Godot Editor: ${err.message}`));
        }
      });

      ws.on('error', (err) => {
        clearTimeout(timer);
        reject(err);
      });
    });
  }
}
