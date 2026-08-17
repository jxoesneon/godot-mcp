import { describe, it, expect, vi, beforeEach } from 'vitest';
import { GodotMCPServer } from '../src/index.js';
import { spawn } from 'child_process';
import fs from 'fs-extra';

let capturedHandlers: Record<string, Function> = {};
let mockEditorBridgeInstance: any;

vi.mock('@modelcontextprotocol/sdk/server/index.js', () => {
  return {
    Server: class {
      setRequestHandler(schema: any, handler: Function) {
        capturedHandlers[Object.keys(capturedHandlers).length] = handler;
      }
      connect = vi.fn();
    }
  };
});

vi.mock('@modelcontextprotocol/sdk/server/stdio.js', () => ({
  StdioServerTransport: class {}
}));

vi.mock('child_process', () => ({
  spawn: vi.fn(),
}));

vi.mock('fs-extra', () => ({
  default: {
    existsSync: vi.fn().mockReturnValue(true),
    readdirSync: vi.fn().mockReturnValue([]),
    statSync: vi.fn().mockReturnValue({ isDirectory: () => false }),
  },
}));

vi.mock('../src/bridge/websocket_client.js', () => {
  return {
    GodotEditorBridge: class {
      isEditorConnected = vi.fn().mockResolvedValue(false);
      sendCommand = vi.fn().mockResolvedValue({ status: 'ok', result: 'live_ok' });
      constructor() {
        mockEditorBridgeInstance = this;
      }
    }
  };
});

vi.mock('../src/tools/install_plugin.js', () => ({
  installEditorPlugin: vi.fn().mockResolvedValue({ success: true, message: 'Installed successfully' }),
}));

describe('GodotMCPServer', () => {
  let serverInstance: GodotMCPServer;

  beforeEach(() => {
    vi.clearAllMocks();
    capturedHandlers = {};
    
    process.env.GODOT_PATH = 'custom-godot';
    serverInstance = new GodotMCPServer();
  });

  it('instantiates and starts server', async () => {
    expect(serverInstance).toBeDefined();
    await serverInstance.start();
  });

  it('lists all registered tool definitions', async () => {
    const listHandler = capturedHandlers[0];
    const res = await listHandler();
    expect(res.tools).toBeDefined();
    expect(res.tools.length).toBeGreaterThan(60);
  });

  it('calls install_editor_plugin tool', async () => {
    const callHandler = capturedHandlers[1];
    const res = await callHandler({ params: { name: 'install_editor_plugin', arguments: { project_path: '/my/proj' } } });
    expect(res.content[0].text).toContain('Installed successfully');
  });

  it('calls get_godot_version tool', async () => {
    const callHandler = capturedHandlers[1];
    const mockChild = {
      stdout: { on: vi.fn((event, cb) => cb(Buffer.from('Godot Engine v4.7.1'))) },
      on: vi.fn((event, cb) => {
        if (event === 'close') cb(0);
      }),
      unref: vi.fn()
    };
    (spawn as any).mockReturnValue(mockChild);

    const res = await callHandler({ params: { name: 'get_godot_version', arguments: {} } });
    expect(res.content[0].text).toBe('Godot Engine v4.7.1');
  });

  it('calls launch_editor tool', async () => {
    const callHandler = capturedHandlers[1];
    const mockChild = { unref: vi.fn() };
    (spawn as any).mockReturnValue(mockChild);

    const res = await callHandler({ params: { name: 'launch_editor', arguments: { project_path: '/my/proj' } } });
    expect(res.content[0].text).toContain("Godot Editor launched for project '/my/proj'");
  });

  it('calls list_projects tool and traverses subdirectories', async () => {
    const callHandler = capturedHandlers[1];
    (fs.readdirSync as any)
      .mockReturnValueOnce(['project.godot', 'subfolder', '.hidden'])
      .mockReturnValueOnce(['project.godot']);
    (fs.statSync as any).mockImplementation((p: string) => ({
      isDirectory: () => typeof p === 'string' && !p.endsWith('.godot') && !p.startsWith('.')
    }));

    const res = await callHandler({ params: { name: 'list_projects', arguments: { directory: '.' } } });
    const parsed = JSON.parse(res.content[0].text);
    expect(parsed).toContain('.');
    expect(parsed).toContain('subfolder');
  });

  it('calls run_project, handles stream output, and cleans up on close', async () => {
    const callHandler = capturedHandlers[1];
    let stdoutCb: any, stderrCb: any, closeCb: any;
    const mockChild = {
      stdout: { on: vi.fn((evt, cb) => { stdoutCb = cb; }) },
      stderr: { on: vi.fn((evt, cb) => { stderrCb = cb; }) },
      on: vi.fn((evt, cb) => { if (evt === 'close') closeCb = cb; }),
    };
    (spawn as any).mockReturnValue(mockChild);

    const runRes = await callHandler({ params: { name: 'run_project', arguments: { project_path: '/game' } } });
    const pid = JSON.parse(runRes.content[0].text).process_id;
    expect(pid).toBeDefined();

    stdoutCb(Buffer.from('Game started\n'));
    stderrCb(Buffer.from('Warning: texture missing\n'));

    const debugRes = await callHandler({ params: { name: 'get_debug_output', arguments: { process_id: pid } } });
    const debugJson = JSON.parse(debugRes.content[0].text);
    expect(debugJson.stdout).toContain('Game started\n');
    expect(debugJson.stderr).toContain('Warning: texture missing\n');

    closeCb();
    const deadDebugRes = await callHandler({ params: { name: 'get_debug_output', arguments: { process_id: pid } } });
    expect(deadDebugRes.content[0].text).toContain(`Process ID '${pid}' not found.`);
  });

  it('calls stop_project tool successfully and handles not found', async () => {
    const callHandler = capturedHandlers[1];
    const mockChild = {
      stdout: { on: vi.fn() },
      stderr: { on: vi.fn() },
      on: vi.fn(),
      kill: vi.fn()
    };
    (spawn as any).mockReturnValue(mockChild);

    const runRes = await callHandler({ params: { name: 'run_project', arguments: { project_path: '.' } } });
    const pid = JSON.parse(runRes.content[0].text).process_id;

    const stopRes = await callHandler({ params: { name: 'stop_project', arguments: { process_id: pid } } });
    expect(stopRes.content[0].text).toContain(`Project process '${pid}' stopped.`);
    expect(mockChild.kill).toHaveBeenCalled();

    const notFoundRes = await callHandler({ params: { name: 'stop_project', arguments: { process_id: 'non_existent' } } });
    expect(notFoundRes.content[0].text).toContain("Process ID 'non_existent' not found.");
  });

  it('handles live in-editor bridge dispatch (success and error)', async () => {
    const callHandler = capturedHandlers[1];
    mockEditorBridgeInstance.isEditorConnected.mockResolvedValueOnce(true);
    mockEditorBridgeInstance.sendCommand.mockResolvedValueOnce({ status: 'ok', result: { fps: 60 } });

    const okRes = await callHandler({ params: { name: 'get_performance_metrics', arguments: {} } });
    expect(okRes.content[0].text).toContain('in_editor_live (UndoRedo Enabled)');
    expect(okRes.content[0].text).toContain('60');

    mockEditorBridgeInstance.isEditorConnected.mockResolvedValueOnce(true);
    mockEditorBridgeInstance.sendCommand.mockResolvedValueOnce({ status: 'error', error: 'Node not found' });

    const errRes = await callHandler({ params: { name: 'inspect_node', arguments: { node_path: 'Missing' } } });
    expect(errRes.content[0].text).toContain('Node not found');
  });

  it('normalizes parameters and property maps for variant operations', async () => {
    const callHandler = capturedHandlers[1];
    mockEditorBridgeInstance.isEditorConnected.mockResolvedValue(true);
    mockEditorBridgeInstance.sendCommand.mockImplementation((cmd, params) => {
      return Promise.resolve({ status: 'ok', result: params });
    });

    const gdRes = await callHandler({
      params: {
        name: 'execute_gdscript',
        arguments: { script_code: 'return 42' }
      }
    });
    expect(gdRes.content[0].text).toContain('return 42');

    const nodeRes = await callHandler({
      params: {
        name: 'add_node',
        arguments: {
          properties: { speed: '120.5', color: 'Color(1, 0, 0)' },
          position: 'Vector3(1, 2, 3)'
        }
      }
    });
    expect(nodeRes.content[0].text).toContain('Vector3');
  });

  it('falls back to headless CLI when editor bridge throws or is disconnected', async () => {
    const callHandler = capturedHandlers[1];
    mockEditorBridgeInstance.isEditorConnected.mockRejectedValueOnce(new Error('Connection refused'));

    const mockChild = {
      stdout: { on: vi.fn((event, cb) => cb(Buffer.from('GODOT_MCP_RESULT: {"status":"ok","result":"headless_success"}'))) },
      stderr: { on: vi.fn() },
      on: vi.fn((event, cb) => {
        if (event === 'close') cb(0);
      }),
    };
    (spawn as any).mockReturnValue(mockChild);

    const res = await callHandler({ params: { name: 'get_scene_tree', arguments: { scene_path: '/my/scene.tscn' } } });
    expect(res.content[0].text).toContain('headless_cli_fallback');
    expect(res.content[0].text).toContain('headless_success');
  });

  it('handles headless execution errors (script error, invalid json, and non-zero exit)', async () => {
    const callHandler = capturedHandlers[1];
    mockEditorBridgeInstance.isEditorConnected.mockResolvedValue(false);

    // 1. Headless error status
    (spawn as any).mockReturnValueOnce({
      stdout: { on: vi.fn((event, cb) => cb(Buffer.from('GODOT_MCP_RESULT: {"status":"error","error":"GDScript syntax error"}'))) },
      stderr: { on: vi.fn() },
      on: vi.fn((event, cb) => { if (event === 'close') cb(0); }),
    });
    const errRes1 = await callHandler({ params: { name: 'validate_script', arguments: {} } });
    expect(errRes1.isError).toBe(true);
    expect(errRes1.content[0].text).toContain('GDScript syntax error');

    // 2. Malformed JSON after marker
    (spawn as any).mockReturnValueOnce({
      stdout: { on: vi.fn((event, cb) => cb(Buffer.from('GODOT_MCP_RESULT: {malformed}'))) },
      stderr: { on: vi.fn() },
      on: vi.fn((event, cb) => { if (event === 'close') cb(0); }),
    });
    const errRes2 = await callHandler({ params: { name: 'validate_script', arguments: {} } });
    expect(errRes2.isError).toBe(true);
    expect(errRes2.content[0].text).toContain('Failed to parse headless output');

    // 3. Non-zero exit code without marker
    (spawn as any).mockReturnValueOnce({
      stdout: { on: vi.fn() },
      stderr: { on: vi.fn((event, cb) => cb(Buffer.from('Engine crashed!'))) },
      on: vi.fn((event, cb) => { if (event === 'close') cb(1); }),
    });
    const errRes3 = await callHandler({ params: { name: 'validate_script', arguments: {} } });
    expect(errRes3.isError).toBe(true);
    expect(errRes3.content[0].text).toContain('Engine crashed!');
  });

  it('detects godot binary paths across platforms and fallback', () => {
    delete process.env.GODOT_PATH;
    (fs.existsSync as any).mockReturnValue(true);

    Object.defineProperty(process, 'platform', { value: 'darwin' });
    const sDarwin = new GodotMCPServer();
    expect((sDarwin as any).godotPath).toBe('/Applications/Godot.app/Contents/MacOS/Godot');

    Object.defineProperty(process, 'platform', { value: 'win32' });
    const sWin = new GodotMCPServer();
    expect((sWin as any).godotPath).toBe('C:\\Program Files\\Godot\\Godot.exe');

    Object.defineProperty(process, 'platform', { value: 'linux' });
    const sLinux = new GodotMCPServer();
    expect((sLinux as any).godotPath).toBe('/usr/bin/godot');

    (fs.existsSync as any).mockReturnValue(false);
    const sFallback = new GodotMCPServer();
    expect((sFallback as any).godotPath).toBe('godot');
  });

  it('throws error if headless operation script is missing', async () => {
    mockEditorBridgeInstance.isEditorConnected.mockResolvedValue(false);
    (fs.existsSync as any).mockImplementation((p: string) => {
      if (typeof p === 'string' && p.includes('godot_operations.gd')) return false;
      return true;
    });

    const callHandler = capturedHandlers[1];
    const res = await callHandler({ params: { name: 'get_scene_tree', arguments: {} } });
    expect(res.isError).toBe(true);
    expect(res.content[0].text).toContain('Headless script not found');
  });

  it('handles headless execution returning raw stdout on code 0 without marker', async () => {
    mockEditorBridgeInstance.isEditorConnected.mockResolvedValue(false);
    (fs.existsSync as any).mockReturnValue(true);
    (spawn as any).mockReturnValueOnce({
      stdout: { on: vi.fn((event, cb) => cb(Buffer.from('Raw standard output'))) },
      stderr: { on: vi.fn() },
      on: vi.fn((event, cb) => { if (event === 'close') cb(0); }),
    });

    const callHandler = capturedHandlers[1];
    const res = await callHandler({ params: { name: 'get_scene_tree', arguments: {} } });
    expect(res.content[0].text).toContain('Raw standard output');
  });
});
