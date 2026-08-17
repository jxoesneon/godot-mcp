import { describe, it, expect, vi, beforeEach } from 'vitest';
import net from 'net';
import { GodotEditorBridge } from '../src/bridge/websocket_client.js';

vi.mock('net');

describe('GodotEditorBridge', () => {
  let bridge: GodotEditorBridge;

  beforeEach(() => {
    bridge = new GodotEditorBridge('127.0.0.1', 6505, 50);
    vi.clearAllMocks();
  });

  it('isEditorConnected returns true when ping succeeds', async () => {
    const mockClient = {
      write: vi.fn(),
      on: vi.fn((event, cb) => {
        if (event === 'data') {
          setTimeout(() => cb(Buffer.from('HTTP/1.1 200 OK\r\n\r\n' + JSON.stringify({ id: 'req_1', status: 'ok' }))), 10);
        }
      }),
      end: vi.fn(),
      destroy: vi.fn(),
    };
    (net.createConnection as any).mockImplementation((opts: any, cb: () => void) => {
      setTimeout(cb, 5);
      return mockClient;
    });

    const result = await bridge.isEditorConnected();
    expect(result).toBe(true);
  });

  it('isEditorConnected returns false when ping times out', async () => {
    const mockClient = {
      write: vi.fn(),
      on: vi.fn(),
      end: vi.fn(),
      destroy: vi.fn(),
    };
    (net.createConnection as any).mockImplementation((opts: any, cb: () => void) => {
      setTimeout(cb, 5);
      return mockClient;
    });

    const result = await bridge.isEditorConnected();
    expect(result).toBe(false);
  });

  it('isEditorConnected returns false on error', async () => {
    const mockClient = {
      write: vi.fn(),
      on: vi.fn((event, cb) => {
        if (event === 'error') {
          setTimeout(() => cb(new Error('Connection refused')), 10);
        }
      }),
      end: vi.fn(),
      destroy: vi.fn(),
    };
    (net.createConnection as any).mockImplementation((opts: any, cb: () => void) => {
      setTimeout(cb, 5);
      return mockClient;
    });

    const result = await bridge.isEditorConnected();
    expect(result).toBe(false);
  });

  it('sendCommand handles fragmented JSON', async () => {
    const mockClient = {
      write: vi.fn(),
      on: vi.fn((event, cb) => {
        if (event === 'data') {
          setTimeout(() => {
            cb(Buffer.from('Headers...\r\n\r\n{"id":"req_1",'));
            cb(Buffer.from('"status":"ok"}'));
          }, 10);
        }
      }),
      end: vi.fn(),
      destroy: vi.fn(),
    };
    (net.createConnection as any).mockImplementation((opts: any, cb: () => void) => {
      setTimeout(cb, 5);
      return mockClient;
    });

    const result = await bridge.sendCommand('test_cmd');
    expect(result).toEqual({ id: 'req_1', status: 'ok' });
  });

  it('sendCommand rejects on error', async () => {
    const mockClient = {
      write: vi.fn(),
      on: vi.fn((event, cb) => {
        if (event === 'error') {
          setTimeout(() => cb(new Error('Test error')), 10);
        }
      }),
      end: vi.fn(),
      destroy: vi.fn(),
    };
    (net.createConnection as any).mockImplementation((opts: any, cb: () => void) => {
      setTimeout(cb, 5);
      return mockClient;
    });

    await expect(bridge.sendCommand('test_cmd')).rejects.toThrow('Test error');
  });

  it('sendCommand times out if no data received', async () => {
    const mockClient = {
      write: vi.fn(),
      on: vi.fn(),
      end: vi.fn(),
      destroy: vi.fn(),
    };
    (net.createConnection as any).mockImplementation((opts: any, cb: () => void) => {
      setTimeout(cb, 5);
      return mockClient;
    });

    await expect(bridge.sendCommand('test_cmd')).rejects.toThrow("Godot Editor TCP command 'test_cmd' timed out");
  });
});
