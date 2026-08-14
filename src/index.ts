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
import { parsePropertiesMap, parseGodotVariant } from './utils/type_parser.js';
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

          case 'add_node':
          case 'modify_node_properties':
          case 'instantiate_scene': {
            if (parsedArgs.properties) {
              parsedArgs.properties = parsePropertiesMap(parsedArgs.properties);
            }
            if (parsedArgs.position) {
              parsedArgs.position = parseGodotVariant(parsedArgs.position);
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
        description: 'Creates a new Godot scene (.tscn) file with specified root node type or inheriting from a base scene.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'res:// or file path' },
            root_type: { type: 'string', description: 'Node2D, Node3D, Control, CharacterBody2D, etc. (default: Node2D)' },
            root_name: { type: 'string', description: 'Name of root node (default: Root)' },
            inherits: { type: 'string', description: 'Path to base .tscn scene file to inherit from' },
          },
          required: ['scene_path'],
        },
      },
      {
        name: 'add_node',
        description: 'Adds a child node to a scene with optional properties and script. Supports in-editor Undo/Redo when Godot editor is open!',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Scene file path' },
            node_type: { type: 'string', description: 'Node class name (e.g. Sprite2D, CollisionShape2D)' },
            node_name: { type: 'string', description: 'Name for the new node' },
            parent_path: { type: 'string', description: 'Parent node path (default ".")' },
            properties: { type: 'object', description: 'Initial properties map to set on the new node' },
            script_path: { type: 'string', description: 'Path to script (.gd) to attach to the new node' },
          },
          required: ['node_type'],
        },
      },
      {
        name: 'modify_node_properties',
        description: 'Sets properties on a node with smart variant parsing (Vector2, Vector3, Color, Rect2, Transform2D, Transform3D, Basis, Quaternion, Array, Dictionary).',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string' },
            node_path: { type: 'string', description: 'Node path in scene (default ".")' },
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
          properties: {
            scene_path: { type: 'string' },
            node_path: { type: 'string', description: 'Node path to move' },
            new_parent_path: { type: 'string', description: 'Destination parent node path' },
            keep_global_transform: { type: 'boolean', description: 'Whether to maintain global transform (default true)' },
          },
          required: ['node_path', 'new_parent_path'],
        },
      },
      {
        name: 'duplicate_node',
        description: 'Duplicates an existing node inside a scene.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string' },
            node_path: { type: 'string', description: 'Node path to duplicate' },
            new_name: { type: 'string', description: 'Optional name for the duplicated node' },
            parent_path: { type: 'string', description: 'Optional parent node path to place duplicated node under' },
          },
          required: ['node_path'],
        },
      },
      {
        name: 'inspect_node',
        description: 'Returns all property values, attached scripts, signals, groups, and child nodes of a node.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string' },
            node_path: { type: 'string', description: 'Node path in scene (default ".")' },
            include_signals: { type: 'boolean', description: 'Whether to include signals list (default true)' },
            include_groups: { type: 'boolean', description: 'Whether to include node groups (default true)' },
            include_children: { type: 'boolean', description: 'Whether to include child nodes list (default true)' },
          },
        },
      },
      {
        name: 'get_scene_tree',
        description: 'Returns full hierarchical node tree of open editor scene or .tscn file.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string' },
            max_depth: { type: 'number', description: 'Maximum depth of tree traversal (-1 for unlimited, default -1)' },
            filter_type: { type: 'string', description: 'Filter nodes by class type (e.g. Sprite2D)' },
          },
        },
      },
      {
        name: 'instantiate_scene',
        description: 'Instantiates a sub-scene (.tscn) as a child node in a scene or active editor session.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Target scene file path (required for headless mode)' },
            target_scene_path: { type: 'string', description: 'Path to .tscn scene file to instantiate' },
            parent_path: { type: 'string', description: 'Parent node path (default ".")' },
            node_name: { type: 'string', description: 'Optional custom name for instantiated root node' },
            position: { description: 'Optional initial position (Vector2, Vector3, or dict {x, y} / {x, y, z})' },
          },
          required: ['target_scene_path'],
        },
      },
      {
        name: 'create_script',
        description: 'Generates a new GDScript file with optional class_name, signals, and methods.',
        inputSchema: {
          type: 'object',
          properties: {
            script_path: { type: 'string', description: 'Target path (e.g. res://scripts/my_script.gd)' },
            extends_class: { type: 'string', description: 'Class to extend (default: Node)' },
            class_name: { type: 'string', description: 'Optional class_name declaration' },
            content: { type: 'string', description: 'Raw GDScript code content' },
            signals: {
              type: 'array',
              description: 'List of signal definitions: [{ name: "health_changed", args: ["new_hp"] }] or string names',
            },
            methods: {
              type: 'array',
              description: 'List of method definitions: [{ name: "take_damage", args: ["amount"], return_type: "void", content: "pass" }]',
            },
          },
          required: ['script_path'],
        },
      },
      {
        name: 'attach_script',
        description: 'Attaches a script to a node in a scene.',
        inputSchema: {
          type: 'object',
          properties: {
            script_path: { type: 'string', description: 'Path to script file (.gd)' },
            node_path: { type: 'string', description: 'Node path in scene (default: ".")' },
            scene_path: { type: 'string', description: 'Scene path (.tscn) for headless operation' },
          },
          required: ['script_path'],
        },
      },
      {
        name: 'edit_script',
        description: 'Edits GDScript file content (full code or line range replacement).',
        inputSchema: {
          type: 'object',
          properties: {
            script_path: { type: 'string', description: 'Path to GDScript file' },
            code: { type: 'string', description: 'New GDScript code content or line replacement text' },
            line_start: { type: 'number', description: '1-based starting line index for range replacement' },
            line_end: { type: 'number', description: '1-based ending line index for range replacement' },
          },
          required: ['script_path', 'code'],
        },
      },
      {
        name: 'validate_script',
        description: 'Validates GDScript syntax and instantiability.',
        inputSchema: {
          type: 'object',
          properties: {
            script_path: { type: 'string', description: 'Path to GDScript file' },
          },
          required: ['script_path'],
        },
      },
      {
        name: 'connect_signal',
        description: 'Connects a signal from a source node to a target node method in a scene.',
        inputSchema: {
          type: 'object',
          properties: {
            signal_name: { type: 'string', description: 'Signal name (e.g. "pressed", "body_entered")' },
            source_node_path: { type: 'string', description: 'Source node path emitting the signal' },
            target_node_path: { type: 'string', description: 'Target node path receiving signal' },
            target_method: { type: 'string', description: 'Target method name to call' },
            binds: { type: 'array', description: 'Optional list of bound parameters' },
            flags: { description: 'Connection flags (number or array of string names like ["deferred", "persist", "one_shot"])' },
            scene_path: { type: 'string', description: 'Scene path for headless operation' },
          },
          required: ['signal_name', 'source_node_path', 'target_node_path', 'target_method'],
        },
      },
      {
        name: 'disconnect_signal',
        description: 'Disconnects a signal between source and target nodes in a scene.',
        inputSchema: {
          type: 'object',
          properties: {
            signal_name: { type: 'string', description: 'Signal name' },
            source_node_path: { type: 'string', description: 'Source node path' },
            target_node_path: { type: 'string', description: 'Target node path' },
            target_method: { type: 'string', description: 'Target method name' },
            scene_path: { type: 'string', description: 'Scene path for headless operation' },
          },
          required: ['signal_name', 'source_node_path', 'target_node_path', 'target_method'],
        },
      },
      {
        name: 'list_signals',
        description: 'Lists all available signals and active signal connections on a node.',
        inputSchema: {
          type: 'object',
          properties: {
            node_path: { type: 'string', description: 'Node path to inspect (default: ".")' },
            scene_path: { type: 'string', description: 'Scene path for headless operation' },
          },
          required: ['node_path'],
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
          properties: {
            scene_path: { type: 'string', description: 'Source scene file path (.tscn)' },
            output_path: { type: 'string', description: 'Output .tres or .meshlib resource file path' },
            generate_collisions: { type: 'boolean', description: 'Whether to generate collision shapes for meshes (default: false)' },
          },
          required: ['scene_path', 'output_path'],
        },
      },
      {
        name: 'get_uid',
        description: 'Retrieves Godot 4.4+ file UID.',
        inputSchema: {
          type: 'object',
          properties: { file_path: { type: 'string', description: 'Resource file path (e.g. res://icon.svg)' } },
          required: ['file_path'],
        },
      },
      {
        name: 'update_project_uids',
        description: 'Resaves resources to synchronize UIDs across Godot 4.4 project.',
        inputSchema: {
          type: 'object',
          properties: {
            project_path: { type: 'string', description: 'Path to Godot project directory (default: current directory)' },
          },
        },
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
        description: 'Configures CollisionObject2D/3D physics body properties (CharacterBody, RigidBody, StaticBody, AnimatableBody, mass, friction, bounce, gravity_scale, collision_layer, collision_mask, is_3d).',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Scene file path (for headless mode)' },
            node_path: { type: 'string', description: 'Path to target physics body node' },
            body_type: { type: 'string', description: 'Body type: CharacterBody2D/3D, RigidBody2D/3D, StaticBody2D/3D, AnimatableBody2D/3D' },
            mass: { type: 'number', description: 'Mass for RigidBody2D/3D' },
            friction: { type: 'number', description: 'Friction coefficient' },
            bounce: { type: 'number', description: 'Bounciness / restitution coefficient' },
            gravity_scale: { type: 'number', description: 'Gravity scale for RigidBody2D/3D' },
            collision_layer: { type: 'number', description: 'Collision layer bitmask' },
            collision_mask: { type: 'number', description: 'Collision mask bitmask' },
            is_3d: { type: 'boolean', description: 'Whether this physics body is 3D' },
          },
          required: ['node_path'],
        },
      },
      {
        name: 'add_collision_shape',
        description: 'Adds a CollisionShape2D or CollisionShape3D with specified shape (Box, Sphere, Capsule, Cylinder, Rectangle, Circle, Segment, WorldBoundary, ConvexPolygon, ConcavePolygon) to a physics body.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Scene file path (for headless mode)' },
            parent_path: { type: 'string', description: 'Parent physics body or node path' },
            shape_type: { type: 'string', description: 'Shape type: Box, Sphere, Capsule, Cylinder, Rectangle, Circle, Segment, WorldBoundary, ConvexPolygon, ConcavePolygon' },
            shape_params: { type: 'object', description: 'Shape parameters: size, radius, height, points, normal, d, etc.' },
            node_name: { type: 'string', description: 'Name of collision shape node to create' },
            is_3d: { type: 'boolean', description: 'Whether shape is 3D' },
          },
          required: ['parent_path', 'shape_type'],
        },
      },
      {
        name: 'configure_raycast',
        description: 'Sets up RayCast2D or RayCast3D node parameters (target_position, collide_with_bodies, collide_with_areas, collision_mask, enabled, is_3d).',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Scene file path (for headless mode)' },
            node_path: { type: 'string', description: 'Path to RayCast node' },
            target_position: { description: 'Target position vector: {x, y} or {x, y, z}' },
            collide_with_bodies: { type: 'boolean', description: 'Whether raycast collides with physics bodies' },
            collide_with_areas: { type: 'boolean', description: 'Whether raycast collides with Area nodes' },
            collision_mask: { type: 'number', description: 'Collision mask bitmask' },
            enabled: { type: 'boolean', description: 'Whether RayCast is enabled' },
            is_3d: { type: 'boolean', description: 'Whether RayCast is 3D' },
          },
          required: ['node_path'],
        },
      },
      {
        name: 'configure_area',
        description: 'Configures Area2D or Area3D node parameters (monitoring, monitorable, priority, gravity, collision_layer, collision_mask, is_3d).',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Scene file path (for headless mode)' },
            node_path: { type: 'string', description: 'Path to Area node' },
            monitoring: { type: 'boolean', description: 'Whether area detects overlapping areas/bodies' },
            monitorable: { type: 'boolean', description: 'Whether area can be detected by other areas' },
            priority: { type: 'number', description: 'Area processing priority' },
            gravity: { type: 'number', description: 'Area gravity acceleration override' },
            collision_layer: { type: 'number', description: 'Collision layer bitmask' },
            collision_mask: { type: 'number', description: 'Collision mask bitmask' },
            is_3d: { type: 'boolean', description: 'Whether Area is 3D' },
          },
          required: ['node_path'],
        },
      },
      {
        name: 'create_ui_layout',
        description: 'Builds UI layout containers and controls with layout presets.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Path to scene file (.tscn)' },
            parent_path: { type: 'string', description: 'Parent node path in scene (default: root)' },
            container_type: { type: 'string', description: 'Container class type (VBoxContainer, HBoxContainer, GridContainer, MarginContainer, PanelContainer, ScrollContainer, etc.)' },
            container_name: { type: 'string', description: 'Name of the container node' },
            layout_preset: { type: 'string', description: 'Layout preset (FullRect, Center, TopLeft, BottomRight, TopRight, BottomLeft, TopWide, BottomWide, LeftWide, RightWide, HCenterWide, VCenterWide, Wide, etc. or integer enum)' },
            controls_to_add: {
              type: 'array',
              description: 'List of controls to add (string names like "Button" or objects with {type, name, text, properties})',
            },
          },
        },
      },
      {
        name: 'apply_theme',
        description: 'Applies a Theme resource to a target node in a scene.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Path to scene file (.tscn)' },
            theme_path: { type: 'string', description: 'Path to Theme resource file (.theme or .tres)' },
            target_node_path: { type: 'string', description: 'Path to target Control node (default: root)' },
            node_path: { type: 'string', description: 'Alias for target_node_path' },
          },
          required: ['theme_path'],
        },
      },
      {
        name: 'configure_control_anchors',
        description: 'Configures Control node layout presets, anchors, and offsets.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Path to scene file (.tscn)' },
            node_path: { type: 'string', description: 'Path to target Control node' },
            anchor_preset: { type: 'string', description: 'Layout preset (FullRect, Center, TopLeft, BottomRight, TopRight, BottomLeft, TopWide, BottomWide, LeftWide, RightWide, HCenterWide, VCenterWide, Wide, etc. or integer enum)' },
            custom_anchors: {
              type: 'object',
              description: 'Custom anchor values { left, top, right, bottom } (0.0 to 1.0)',
              properties: {
                left: { type: 'number' },
                top: { type: 'number' },
                right: { type: 'number' },
                bottom: { type: 'number' },
              },
            },
            custom_offsets: {
              type: 'object',
              description: 'Custom offset values { left, top, right, bottom } in pixels',
              properties: {
                left: { type: 'number' },
                top: { type: 'number' },
                right: { type: 'number' },
                bottom: { type: 'number' },
              },
            },
          },
          required: ['node_path'],
        },
      },
      {
        name: 'set_control_theme_override',
        description: 'Sets a theme override (color, font, font_size, constant, stylebox) on a Control node.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Path to scene file (.tscn)' },
            node_path: { type: 'string', description: 'Path to target Control node' },
            override_type: { type: 'string', description: 'Type of override: "color", "font", "font_size", "constant", "stylebox"' },
            override_name: { type: 'string', description: 'Name of theme override property (e.g. font_color, font_size, separation, panel)' },
            value: { description: 'Value for override (Color hex/dict, Font path, number for font_size/constant, StyleBox path/dict, or null/empty to clear)' },
          },
          required: ['node_path', 'override_type', 'override_name'],
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
        description: 'Creates a ShaderMaterial with GDShader code (supports canvas_item, spatial, sky, fog). Can save as resource or attach to node in scene.',
        inputSchema: {
          type: 'object',
          properties: {
            shader_code: { type: 'string', description: 'GDShader code snippet or complete shader text' },
            shader_type: { type: 'string', description: 'canvas_item, spatial, sky, fog (default: canvas_item)' },
            output_path: { type: 'string', description: 'Path to save .tres/.material file' },
            save_path: { type: 'string', description: 'Alias for output_path' },
            shader_path: { type: 'string', description: 'Path to save raw .gdshader code file' },
            shader_parameters: { type: 'object', description: 'Initial uniform values map' },
            scene_path: { type: 'string', description: 'Target .tscn scene path to attach material' },
            node_path: { type: 'string', description: 'Target node path in scene' },
          },
        },
      },
      {
        name: 'set_shader_parameter',
        description: 'Sets uniforms/parameters on a ShaderMaterial attached to a Sprite2D, MeshInstance3D, ColorRect, or saved material resource.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Scene file path (for headless mode)' },
            node_path: { type: 'string', description: 'Node path containing the ShaderMaterial' },
            material_path: { type: 'string', description: 'Direct path to .tres material file' },
            param_name: { type: 'string', description: 'Uniform parameter name' },
            value: { type: 'any', description: 'Parameter value (scalar, vector, color, texture res:// path)' },
            parameters: { type: 'object', description: 'Dictionary of multiple parameter key-values' },
            surface_index: { type: 'number', description: 'Surface override index for MeshInstance3D' },
          },
        },
      },
      {
        name: 'create_visual_shader',
        description: 'Generates a VisualShader resource with graph nodes and connections.',
        inputSchema: {
          type: 'object',
          properties: {
            shader_type: { type: 'string', description: 'canvas_item, spatial, sky, fog, particles (default: canvas_item)' },
            mode: { type: 'string', description: 'Alias for shader_type' },
            output_path: { type: 'string', description: 'Path to save .tres VisualShader resource' },
            save_path: { type: 'string', description: 'Alias for output_path' },
            nodes: {
              type: 'array',
              description: 'List of nodes: { type: "VisualShaderNodeColorConstant", position: {x,y}, properties: {...}, stage: "fragment" }',
              items: { type: 'object' },
            },
            connections: {
              type: 'array',
              description: 'List of connections: { from_node: int, from_port: int, to_node: int, to_port: int, stage: "fragment" }',
              items: { type: 'object' },
            },
            create_material: { type: 'boolean', description: 'Whether to wrap in ShaderMaterial (default: true)' },
            material_save_path: { type: 'string', description: 'Path to save generated ShaderMaterial' },
            scene_path: { type: 'string', description: 'Target scene file path' },
            node_path: { type: 'string', description: 'Target node path to attach generated material' },
          },
        },
      },
      {
        name: 'configure_audio_bus',
        description: 'Creates or updates AudioServer audio buses, volume, send bus, and audio effects.',
        inputSchema: {
          type: 'object',
          properties: {
            bus_name: { type: 'string', description: 'Audio bus name (e.g. "Master", "Music", "SFX")' },
            volume_db: { type: 'number', description: 'Bus volume in decibels (dB)' },
            send_bus: { type: 'string', description: 'Name of bus to send audio output to' },
            add_effect: { description: 'Audio effect class name or boolean (e.g. "AudioEffectReverb")' },
            effect_type: { type: 'string', description: 'Audio effect class name' },
          },
          required: ['bus_name'],
        },
      },
      {
        name: 'create_audio_stream_player',
        description: 'Creates an AudioStreamPlayer, AudioStreamPlayer2D, or AudioStreamPlayer3D node in a scene.',
        inputSchema: {
          type: 'object',
          properties: {
            stream_path: { type: 'string', description: 'Path to audio stream file (.wav, .ogg, .mp3)' },
            bus_name: { type: 'string', description: 'Target audio bus name (default: "Master")' },
            autoplay: { type: 'boolean', description: 'Whether audio auto-plays on ready' },
            volume_db: { type: 'number', description: 'Volume in decibels (dB)' },
            pitch_scale: { type: 'number', description: 'Pitch scale factor' },
            is_3d: { type: 'boolean', description: 'Create AudioStreamPlayer3D node' },
            is_2d: { type: 'boolean', description: 'Create AudioStreamPlayer2D node' },
            scene_path: { type: 'string', description: 'Scene path for headless operation' },
            parent_path: { type: 'string', description: 'Parent node path (default: ".")' },
            node_name: { type: 'string', description: 'Name for audio player node' },
          },
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
        description: 'Simulates playtest input events (key press, mouse click, mouse motion, action).',
        inputSchema: {
          type: 'object',
          properties: {
            action: { type: 'string', description: 'Input action name (for event_type: action)' },
            event_type: { type: 'string', description: 'Event type: action, key, mouse_button, mouse_motion' },
            type: { type: 'string', description: 'Alias for event_type' },
            pressed: { type: 'boolean', description: 'Pressed state (default: true)' },
            key_code: { type: 'any', description: 'Key code (number or key name string like "Space", "KEY_A", 32)' },
            mouse_button_index: { type: 'number', description: 'Mouse button index (1=Left, 2=Right, 3=Middle, 4=WheelUp, 5=WheelDown)' },
            position: { type: 'object', description: '{x, y} position vector for mouse events' },
            relative_motion: { type: 'object', description: '{x, y} relative motion vector for mouse_motion' },
          },
        },
      },
      {
        name: 'take_screenshot',
        description: 'Captures viewport screenshot from active Godot editor window or running application as Base64 image.',
        inputSchema: {
          type: 'object',
          properties: {
            format: { type: 'string', description: 'Image format: png or jpg (default: png)' },
            max_width: { type: 'number', description: 'Maximum image width for downscaling' },
            max_height: { type: 'number', description: 'Maximum image height for downscaling' },
            quality: { type: 'number', description: 'JPEG quality float 0.0-1.0 or int 1-100 (default: 0.75)' },
          },
        },
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
      {
        name: 'set_tilemap_cell',
        description: 'Sets tile cell on TileMap or TileMapLayer with source_id, atlas_coords, and alternative_tile.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Scene file path (for headless mode)' },
            node_path: { type: 'string', description: 'Path to TileMap or TileMapLayer node' },
            layer: { type: 'number', description: 'Layer index (for TileMap, default 0)' },
            coords: { type: 'object', description: '{x, y} tile coordinates' },
            source_id: { type: 'number', description: 'TileSet source ID' },
            atlas_coords: { type: 'object', description: '{x, y} coordinates in atlas' },
            alternative_tile: { type: 'number', description: 'Alternative tile ID (default 0)' },
          },
          required: ['node_path'],
        },
      },
      {
        name: 'configure_navigation_region',
        description: 'Sets up NavigationRegion2D or NavigationRegion3D with NavigationMesh or NavigationPolygon.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Scene file path' },
            node_path: { type: 'string', description: 'Path to NavigationRegion node' },
            navmesh_path: { type: 'string', description: 'Path to NavigationMesh/NavigationPolygon resource (.tres/.res)' },
            is_3d: { type: 'boolean', description: 'Whether this is a 3D navigation region' },
            bake: { type: 'boolean', description: 'Whether to bake navigation mesh' },
          },
          required: ['node_path'],
        },
      },
      {
        name: 'set_gridmap_cell',
        description: 'Places mesh library items into GridMap at (x, y, z) coordinates.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string', description: 'Scene file path' },
            node_path: { type: 'string', description: 'Path to GridMap node' },
            position: { type: 'object', description: '{x, y, z} grid coordinates' },
            item: { type: 'number', description: 'MeshLibrary item index' },
            orientation: { type: 'number', description: 'Item orientation (0-23)' },
            mesh_library_path: { type: 'string', description: 'Path to MeshLibrary resource' },
          },
          required: ['node_path'],
        },
      },
      {
        name: 'create_animation',
        description: 'Creates Animation resource with length, step, and loop mode.',
        inputSchema: {
          type: 'object',
          properties: {
            animation_path: { type: 'string', description: 'Path to save standalone .tres Animation resource' },
            scene_path: { type: 'string', description: 'Path to scene file' },
            animation_player_path: { type: 'string', description: 'Path to AnimationPlayer node in scene' },
            animation_name: { type: 'string', description: 'Name of the animation' },
            length: { type: 'number', description: 'Animation length in seconds' },
            step: { type: 'number', description: 'Animation step in seconds' },
            loop_mode: { type: 'string', description: 'Loop mode: "none", "linear", "pingpong"' },
          },
        },
      },
      {
        name: 'add_animation_track',
        description: 'Adds value, transform, or method tracks to an Animation.',
        inputSchema: {
          type: 'object',
          properties: {
            animation_path: { type: 'string' },
            scene_path: { type: 'string' },
            animation_player_path: { type: 'string' },
            animation_name: { type: 'string' },
            track_type: { type: 'string', description: 'Track type: "value", "position_3d", "rotation_3d", "scale_3d", "transform", "method", "bezier"' },
            track_path: { type: 'string', description: 'Node or property path (e.g. "Sprite2D:position" or "Player:play_sound")' },
            interpolation_type: { type: 'string', description: 'Interpolation: "nearest", "linear", "cubic"' },
            update_mode: { type: 'string', description: 'Update mode for value track: "continuous", "discrete", "capture"' },
          },
        },
      },
      {
        name: 'insert_animation_keyframe',
        description: 'Inserts keyframe at specified time in an Animation track.',
        inputSchema: {
          type: 'object',
          properties: {
            animation_path: { type: 'string' },
            scene_path: { type: 'string' },
            animation_player_path: { type: 'string' },
            animation_name: { type: 'string' },
            track_index: { type: 'number' },
            track_path: { type: 'string' },
            time: { type: 'number', description: 'Time in seconds' },
            value: { description: 'Keyframe value (number, vector dict, color dict, or method dict)' },
            transition: { type: 'number', description: 'Transition/easing value' },
          },
        },
      },
      {
        name: 'configure_animation_tree',
        description: 'Sets up AnimationTree state machines and blend trees.',
        inputSchema: {
          type: 'object',
          properties: {
            scene_path: { type: 'string' },
            animation_tree_path: { type: 'string' },
            animation_player_path: { type: 'string' },
            tree_type: { type: 'string', description: 'Tree type: "state_machine", "blend_tree", "blend_space_2d", "blend_space_1d"' },
            active: { type: 'boolean' },
            states: { type: 'array', description: 'States array for state machine' },
            transitions: { type: 'array', description: 'Transitions array for state machine' },
            start_node: { type: 'string', description: 'Start node name' },
            blend_nodes: { type: 'array', description: 'Blend nodes array for blend tree' },
            connections: { type: 'array', description: 'Connections array for blend tree' },
          },
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
