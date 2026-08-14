#!/usr/bin/env node

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from '@modelcontextprotocol/sdk/types.js';
import { spawn, ChildProcess } from 'child_process';
import path from 'path';
import fs from 'fs-extra';
import { fileURLToPath } from 'url';
import { GodotEditorBridge } from './bridge/websocket_client.js';
import { parsePropertiesMap } from './utils/type_parser.js';
import { installEditorPlugin } from './tools/install_plugin.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface RunningProcess {
  process: ChildProcess;
  output: string[];
  errors: string[];
  projectPath: string;
}

class GodotMCPServer {
  private server: Server;
  private runningProjects: Map<string, RunningProcess> = new Map();
  private godotPath: string | null = null;
  private editorBridge: GodotEditorBridge;

  constructor() {
    this.server = new Server(
      {
        name: 'godot-mcp-pro',
        version: '2.0.0',
      },
      {
        capabilities: {
          tools: {},
        },
      }
    );

    this.editorBridge = new GodotEditorBridge();
    this.detectGodotPath();
    this.setupHandlers();
  }

  private detectGodotPath(): void {
    if (process.env.GODOT_PATH) {
      this.godotPath = process.env.GODOT_PATH;
      return;
    }

    const platform = process.platform;
    const commonPaths: string[] = [];

    if (platform === 'darwin') {
      commonPaths.push(
        '/Applications/Godot.app/Contents/MacOS/Godot',
        '/Applications/Godot_mono.app/Contents/MacOS/Godot',
        '/Applications/Godot 4.app/Contents/MacOS/Godot'
      );
    } else if (platform === 'win32') {
      commonPaths.push(
        'C:\\Program Files\\Godot\\Godot.exe',
        'C:\\Godot\\Godot.exe'
      );
    } else {
      commonPaths.push('/usr/bin/godot', '/usr/local/bin/godot');
    }

    for (const p of commonPaths) {
      if (fs.existsSync(p)) {
        this.godotPath = p;
        break;
      }
    }

    if (!this.godotPath) {
      this.godotPath = 'godot';
    }
  }

  private async executeHeadlessOp(opName: string, params: Record<string, any>): Promise<any> {
    const scriptPath = path.join(__dirname, 'scripts', 'godot_operations.gd');
    if (!fs.existsSync(scriptPath)) {
      throw new Error(`Headless script not found at '${scriptPath}'. Build the project first.`);
    }

    const opPayload = JSON.stringify({ operation: opName, params });
    const projectPath = params.project_path || params.scene_path ? path.dirname(params.scene_path) : '.';

    const args = ['--headless', '-s', scriptPath, '--op', opPayload];
    if (projectPath && fs.existsSync(path.join(projectPath, 'project.godot'))) {
      args.unshift('--path', projectPath);
    }

    return new Promise((resolve, reject) => {
      const child = spawn(this.godotPath!, args, { cwd: process.cwd() });
      let stdout = '';
      let stderr = '';

      child.stdout.on('data', (d) => { stdout += d.toString(); });
      child.stderr.on('data', (d) => { stderr += d.toString(); });

      child.on('close', (code) => {
        const marker = 'GODOT_MCP_RESULT:';
        const idx = stdout.indexOf(marker);
        if (idx !== -1) {
          const jsonStr = stdout.substr(idx + marker.length).trim();
          try {
            const parsed = JSON.parse(jsonStr);
            if (parsed.status === 'ok') resolve(parsed.result);
            else reject(new Error(parsed.error || 'Headless operation failed'));
            return;
          } catch (e: any) {
            reject(new Error(`Failed to parse headless output: ${e.message}`));
            return;
          }
        }

        if (code === 0) {
          resolve({ stdout, stderr });
        } else {
          reject(new Error(stderr || stdout || `Godot process exited with code ${code}`));
        }
      });
    });
  }

  private async dispatchSmartOp(opName: string, params: Record<string, any>): Promise<any> {
    // 1. Try Live In-Editor WebSocket Bridge first!
    try {
      const isConnected = await this.editorBridge.isEditorConnected();
      if (isConnected) {
        const res = await this.editorBridge.sendCommand(opName, params);
        if (res.status === 'ok') {
          return { mode: 'in_editor_live (UndoRedo Enabled)', result: res.result };
        }
      }
    } catch {}

    // 2. Fallback to Headless CLI execution
    const res = await this.executeHeadlessOp(opName, params);
    return { mode: 'headless_cli_fallback', result: res };
  }

  private setupHandlers(): void {
    this.server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: this.getToolDefinitions(),
    }));

    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      const { name, arguments: args = {} } = request.params;
      const parsedArgs = args as Record<string, any>;

      try {
        switch (name) {
          case 'install_editor_plugin': {
            const res = await installEditorPlugin(parsedArgs.project_path);
            return { content: [{ type: 'text', text: JSON.stringify(res, null, 2) }] };
          }

          case 'launch_editor': {
            const projectPath = parsedArgs.project_path;
            const child = spawn(this.godotPath!, ['-e', '--path', projectPath], { detached: true, stdio: 'ignore' });
            child.unref();
            return { content: [{ type: 'text', text: `Godot Editor launched for project '${projectPath}'` }] };
          }

          case 'run_project': {
            const projectPath = parsedArgs.project_path;
            const processId = `proj_${Date.now()}`;
            const child = spawn(this.godotPath!, ['--path', projectPath], { cwd: projectPath });

            const procRecord: RunningProcess = { process: child, output: [], errors: [], projectPath };
            child.stdout?.on('data', (d) => procRecord.output.push(d.toString()));
            child.stderr?.on('data', (d) => procRecord.errors.push(d.toString()));
            child.on('close', () => this.runningProjects.delete(processId));

            this.runningProjects.set(processId, procRecord);
            return { content: [{ type: 'text', text: JSON.stringify({ process_id: processId, status: 'running' }, null, 2) }] };
          }

          case 'stop_project': {
            const pid = parsedArgs.process_id;
            const proc = this.runningProjects.get(pid);
            if (proc) {
              proc.process.kill();
              this.runningProjects.delete(pid);
              return { content: [{ type: 'text', text: `Project process '${pid}' stopped.` }] };
            }
            return { content: [{ type: 'text', text: `Process ID '${pid}' not found.` }] };
          }

          case 'get_debug_output': {
            const pid = parsedArgs.process_id;
            const proc = this.runningProjects.get(pid);
            if (proc) {
              return { content: [{ type: 'text', text: JSON.stringify({ stdout: proc.output, stderr: proc.errors }, null, 2) }] };
            }
            return { content: [{ type: 'text', text: `Process ID '${pid}' not found.` }] };
          }

          case 'get_godot_version': {
            return new Promise((resolve) => {
              const child = spawn(this.godotPath!, ['--version']);
              let out = '';
              child.stdout.on('data', (d) => out += d.toString());
              child.on('close', () => {
                resolve({ content: [{ type: 'text', text: out.trim() || 'Godot 4.x' }] });
              });
            });
          }

          case 'list_projects': {
            const dir = parsedArgs.directory || '.';
            const projects: string[] = [];
            const walk = (d: string) => {
              const files = fs.readdirSync(d);
              if (files.includes('project.godot')) projects.push(d);
              for (const f of files) {
                const full = path.join(d, f);
                if (fs.statSync(full).isDirectory() && !f.startsWith('.')) {
                  try { walk(full); } catch {}
                }
              }
            };
            walk(dir);
            return { content: [{ type: 'text', text: JSON.stringify(projects, null, 2) }] };
          }

          case 'modify_node_properties': {
            if (parsedArgs.properties) {
              parsedArgs.properties = parsePropertiesMap(parsedArgs.properties);
            }
            const res = await this.dispatchSmartOp(name, parsedArgs);
            return { content: [{ type: 'text', text: JSON.stringify(res, null, 2) }] };
          }

          // Dispatch all other operations to smart dual bridge
          default: {
            const res = await this.dispatchSmartOp(name, parsedArgs);
            return { content: [{ type: 'text', text: JSON.stringify(res, null, 2) }] };
          }
        }
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error executing tool '${name}': ${err.message}` }], isError: true };
      }
    });
  }

  private getToolDefinitions(): Tool[] {
    return [
      {
        name: 'install_editor_plugin',
        description: 'Installs the Godot MCP Pro Bridge editor plugin into a target Godot 4 project path for live in-editor WebSocket capabilities and Ctrl+Z UndoRedo support.',
        inputSchema: {
          type: 'object',
          properties: { project_path: { type: 'string', description: 'Absolute path to Godot project directory' } },
          required: ['project_path'],
        },
      },
      {
        name: 'launch_editor',
        description: 'Launches Godot Engine Editor for specified project.',
        inputSchema: {
          type: 'object',
          properties: { project_path: { type: 'string', description: 'Project directory path' } },
          required: ['project_path'],
        },
      },
      {
        name: 'run_project',
        description: 'Runs Godot game project in debug mode.',
        inputSchema: {
          type: 'object',
          properties: { project_path: { type: 'string' } },
          required: ['project_path'],
        },
      },
      {
        name: 'stop_project',
        description: 'Stops a running game project process.',
        inputSchema: {
          type: 'object',
          properties: { process_id: { type: 'string' } },
          required: ['process_id'],
        },
      },
      {
        name: 'get_debug_output',
        description: 'Retrieves debug console stdout/stderr logs from a running project.',
        inputSchema: {
          type: 'object',
          properties: { process_id: { type: 'string' } },
          required: ['process_id'],
        },
      },
      {
        name: 'get_godot_version',
        description: 'Gets installed Godot executable version.',
        inputSchema: { type: 'object', properties: {} },
      },
      {
        name: 'list_projects',
        description: 'Lists all Godot projects found inside a directory.',
        inputSchema: {
          type: 'object',
          properties: { directory: { type: 'string', description: 'Directory to search' } },
        },
      },
      {
        name: 'create_scene',
        description: 'Creates a new Godot scene (.tscn) file with specified root node type.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'res:// or file path' },
            root_type: { type: 'string', description: 'Node2D, Node3D, Control, CharacterBody2D, etc.' },
            root_name: { type: 'string', description: 'Name of root node' },
          },
          required: ['scene_path'],
        },
      },
      {
        name: 'add_node',
        description: 'Adds a child node to a scene. Supports in-editor Undo/Redo when Godot editor is open!',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string' },
            node_type: { type: 'string', description: 'Node class name' },
            node_name: { type: 'string' },
            parent_path: { type: 'string', description: 'Parent node path' },
          },
          required: ['node_type'],
        },
      },
      {
        name: 'modify_node_properties',
        description: 'Sets properties on a node with smart variant parsing (Vector2, Vector3, Color, Rect2, booleans, numbers).',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string' },
            node_path: { type: 'string' },
            properties: { type: 'object', description: 'Key-value map of properties to set' },
          },
          required: ['properties'],
        },
      },
      {
        name: 'delete_node',
        description: 'Deletes a node from a scene or live editor session.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, node_path: { type: 'string' } },
          required: ['node_path'],
        },
      },
      {
        name: 'reparent_node',
        description: 'Reparents a node to a new parent node.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, node_path: { type: 'string' }, new_parent_path: { type: 'string' } },
          required: ['node_path', 'new_parent_path'],
        },
      },
      {
        name: 'duplicate_node',
        description: 'Duplicates an existing node inside a scene.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, node_path: { type: 'string' }, new_name: { type: 'string' } },
          required: ['node_path'],
        },
      },
      {
        name: 'inspect_node',
        description: 'Returns all property values, attached scripts, and child node counts.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, node_path: { type: 'string' } },
        },
      },
      {
        name: 'get_scene_tree',
        description: 'Returns full hierarchical node tree of open editor scene or .tscn file.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' } },
        },
      },
      {
        name: 'create_script',
        description: 'Generates a new GDScript file.',
        inputSchema: {
          type: 'object',
          properties: {
            script_path: { type: 'string' },
            extends_class: { type: 'string' },
            content: { type: 'string' },
          },
          required: ['script_path'],
        },
      },
      {
        name: 'attach_script',
        description: 'Attaches a script to a node in a scene.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, node_path: { type: 'string' }, script_path: { type: 'string' } },
          required: ['script_path'],
        },
      },
      {
        name: 'edit_script',
        description: 'Edits code of a GDScript file and updates resource filesystem.',
        inputSchema: {
          type: 'object',
          properties: { script_path: { type: 'string' }, code: { type: 'string' } },
          required: ['script_path', 'code'],
        },
      },
      {
        name: 'validate_script',
        description: 'Validates GDScript syntax and instantiability.',
        inputSchema: {
          type: 'object',
          properties: { script_path: { type: 'string' } },
          required: ['script_path'],
        },
      },
      {
        name: 'load_sprite',
        description: 'Loads a Texture2D onto a Sprite2D node.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, texture_path: { type: 'string' }, node_name: { type: 'string' } },
          required: ['texture_path'],
        },
      },
      {
        name: 'export_mesh_library',
        description: 'Exports 3D MeshInstance nodes to a MeshLibrary resource for GridMap usage.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, output_path: { type: 'string' } },
          required: ['scene_path', 'output_path'],
        },
      },
      {
        name: 'get_uid',
        description: 'Retrieves Godot 4.4+ file UID.',
        inputSchema: {
          type: 'object',
          properties: { file_path: { type: 'string' } },
          required: ['file_path'],
        },
      },
      {
        name: 'update_project_uids',
        description: 'Resaves resources to synchronize UIDs across Godot 4.4 project.',
        inputSchema: { type: 'object', properties: {} },
      },
      {
        name: 'add_input_action',
        description: 'Creates a new action in Godot InputMap.',
        inputSchema: {
          type: 'object',
          properties: { action_name: { type: 'string' } },
          required: ['action_name'],
        },
      },
      {
        name: 'bind_input_event',
        description: 'Binds a key/mouse event to an InputMap action.',
        inputSchema: {
          type: 'object',
          properties: { action_name: { type: 'string' }, event_type: { type: 'string' } },
          required: ['action_name'],
        },
      },
      {
        name: 'configure_physics_body',
        description: 'Configures CollisionObject2D/3D physics body properties.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, node_path: { type: 'string' }, body_type: { type: 'string' } },
        },
      },
      {
        name: 'add_collision_shape',
        description: 'Adds a CollisionShape2D or CollisionShape3D to a physics body.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, parent_path: { type: 'string' }, shape_type: { type: 'string' } },
        },
      },
      {
        name: 'configure_raycast',
        description: 'Sets up RayCast2D or RayCast3D node parameters.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, node_path: { type: 'string' }, target_position: { type: 'string' } },
        },
      },
      {
        name: 'create_ui_layout',
        description: 'Builds UI layout containers and controls.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, layout_type: { type: 'string' } },
        },
      },
      {
        name: 'apply_theme',
        description: 'Applies Theme resource or overrides font/color properties.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, node_path: { type: 'string' }, theme_path: { type: 'string' } },
        },
      },
      {
        name: 'create_particle_system',
        description: 'Creates a GPUParticles2D or GPUParticles3D system with material.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, is_3d: { type: 'boolean' } },
        },
      },
      {
        name: 'create_shader_material',
        description: 'Creates a ShaderMaterial with GDShader code.',
        inputSchema: {
          type: 'object',
          properties: { shader_code: { type: 'string' }, output_path: { type: 'string' } },
        },
      },
      {
        name: 'configure_audio_bus',
        description: 'Adds or configures audio buses and stream players.',
        inputSchema: {
          type: 'object',
          properties: { bus_name: { type: 'string' } },
        },
      },
      {
        name: 'configure_tilemap',
        description: 'Configures TileMap or TileMapLayer with TileSet resource.',
        inputSchema: {
          type: 'object',
          properties: { scene_path: { type: 'string' }, tileset_path: { type: 'string' } },
        },
      },
      {
        name: 'simulate_input',
        description: 'Simulates playtest input events (key press, mouse click, action).',
        inputSchema: {
          type: 'object',
          properties: { action: { type: 'string' }, type: { type: 'string' }, pressed: { type: 'boolean' } },
        },
      },
      {
        name: 'take_screenshot',
        description: 'Captures viewport screenshot from active Godot editor window as Base64 image.',
        inputSchema: { type: 'object', properties: {} },
      },
      {
        name: 'run_unit_tests',
        description: 'Executes GUT (Godot Unit Testing) tests headlessly and returns test results report.',
        inputSchema: {
          type: 'object',
          properties: {
            project_path: { type: 'string', description: 'Path to Godot project directory' },
            test_dir: { type: 'string', description: 'Directory containing GUT unit tests (default: res://test/unit)' },
            prefix: { type: 'string', description: 'Prefix for test files (default: test_)' },
            select_script: { type: 'string', description: 'Optional specific test script to run' },
          },
        },
      },
      {
        name: 'add_autoload',
        description: 'Adds an Autoload singleton script or scene to project.godot.',
        inputSchema: {
          type: 'object',
          properties: {
            project_path: { type: 'string', description: 'Path to Godot project directory' },
            name: { type: 'string', description: 'Name of the Autoload singleton' },
            path: { type: 'string', description: 'Resource path to script or scene (e.g. res://scripts/global.gd)' },
          },
          required: ['name', 'path'],
        },
      },
      {
        name: 'remove_autoload',
        description: 'Removes an Autoload singleton from project.godot.',
        inputSchema: {
          type: 'object',
          properties: {
            project_path: { type: 'string', description: 'Path to Godot project directory' },
            name: { type: 'string', description: 'Name of the Autoload singleton to remove' },
          },
          required: ['name'],
        },
      },
    ];
  }

  public async start(): Promise<void> {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('Godot MCP Pro Server running on stdio');
  }
}

const server = new GodotMCPServer();
server.start().catch((err) => {
  console.error('Fatal error running Godot MCP Server:', err);
  process.exit(1);
});
