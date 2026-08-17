import { describe, it, expect, vi, beforeEach } from 'vitest';
import { installEditorPlugin } from '../src/tools/install_plugin.js';
import fs from 'fs-extra';

vi.mock('fs-extra', () => ({
  default: {
    existsSync: vi.fn(),
    ensureDirSync: vi.fn(),
    copySync: vi.fn(),
  },
}));

describe('installEditorPlugin', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('fails if project.godot does not exist', async () => {
    (fs.existsSync as any).mockReturnValue(false);
    const result = await installEditorPlugin('/invalid/path');
    expect(result.success).toBe(false);
    expect(result.message).toContain('No project.godot file found');
  });

  it('fails if addon source directory is not found', async () => {
    (fs.existsSync as any).mockImplementation((p: string) => {
      if (typeof p === 'string' && p.endsWith('project.godot')) return true;
      return false;
    });

    const result = await installEditorPlugin('/valid/path');
    expect(result.success).toBe(false);
    expect(result.message).toContain('plugin source not found');
  });

  it('successfully copies addon when valid', async () => {
    (fs.existsSync as any).mockReturnValue(true);

    const result = await installEditorPlugin('/valid/path');
    expect(result.success).toBe(true);
    expect(result.message).toContain('Successfully installed');
    expect(fs.ensureDirSync).toHaveBeenCalled();
    expect(fs.copySync).toHaveBeenCalled();
  });

  it('handles exceptions during installation', async () => {
    (fs.existsSync as any).mockImplementation(() => {
      throw new Error('EACCES: permission denied');
    });

    const result = await installEditorPlugin('/valid/path');
    expect(result.success).toBe(false);
    expect(result.message).toContain('Failed to install Godot MCP editor plugin: EACCES');
  });
});
