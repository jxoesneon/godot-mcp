import fs from 'fs-extra';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export async function installEditorPlugin(projectPath: string): Promise<{ success: boolean; message: string }> {
  try {
    const projectGodotPath = path.join(projectPath, 'project.godot');
    if (!fs.existsSync(projectGodotPath)) {
      return {
        success: false,
        message: `No project.godot file found at '${projectPath}'. Please specify a valid Godot 4 project directory.`
      };
    }

    // Resolve addon source directory
    let addonSource = path.join(__dirname, '..', 'addons', 'godot_mcp');
    if (!fs.existsSync(addonSource)) {
      // Check root level addons if running in dev environment
      addonSource = path.join(__dirname, '..', '..', 'addons', 'godot_mcp');
    }

    if (!fs.existsSync(addonSource)) {
      return {
        success: false,
        message: `Godot MCP editor plugin source not found at '${addonSource}'. Please build the project first.`
      };
    }

    const targetAddonsDir = path.join(projectPath, 'addons', 'godot_mcp');
    fs.ensureDirSync(targetAddonsDir);
    fs.copySync(addonSource, targetAddonsDir, { overwrite: true });

    return {
      success: true,
      message: `Successfully installed Godot MCP Pro Bridge plugin into '${targetAddonsDir}'. Enable 'Godot MCP Pro Bridge' in Project Settings -> Plugins to activate live in-editor WebSocket capabilities!`
    };
  } catch (err: any) {
    return {
      success: false,
      message: `Failed to install Godot MCP editor plugin: ${err.message}`
    };
  }
}
