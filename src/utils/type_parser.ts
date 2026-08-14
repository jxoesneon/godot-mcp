/**
 * Utility for parsing string representations of Godot engine variant types
 * into structured objects or formatted values.
 */

export interface GodotVector2 { __type: 'Vector2'; x: number; y: number }
export interface GodotVector3 { __type: 'Vector3'; x: number; y: number; z: number }
export interface GodotColor { __type: 'Color'; r: number; g: number; b: number; a: number }
export interface GodotRect2 { __type: 'Rect2'; x: number; y: number; width: number; height: number }

export function parseGodotVariant(val: any): any {
  if (typeof val !== 'string') return val;

  const trimmed = val.trim();

  // Vector2(x, y)
  const vec2Match = /^Vector2\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)$/i.exec(trimmed);
  if (vec2Match) {
    return {
      __type: 'Vector2',
      x: parseFloat(vec2Match[1]),
      y: parseFloat(vec2Match[2]),
    };
  }

  // Vector3(x, y, z)
  const vec3Match = /^Vector3\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)$/i.exec(trimmed);
  if (vec3Match) {
    return {
      __type: 'Vector3',
      x: parseFloat(vec3Match[1]),
      y: parseFloat(vec3Match[2]),
      z: parseFloat(vec3Match[3]),
    };
  }

  // Color(r, g, b, [a])
  const colorMatch = /^Color\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)(?:\s*,\s*(-?\d+(?:\.\d+)?))?\s*\)$/i.exec(trimmed);
  if (colorMatch) {
    return {
      __type: 'Color',
      r: parseFloat(colorMatch[1]),
      g: parseFloat(colorMatch[2]),
      b: parseFloat(colorMatch[3]),
      a: colorMatch[4] !== undefined ? parseFloat(colorMatch[4]) : 1.0,
    };
  }

  // Rect2(x, y, w, h)
  const rectMatch = /^Rect2\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)$/i.exec(trimmed);
  if (rectMatch) {
    return {
      __type: 'Rect2',
      x: parseFloat(rectMatch[1]),
      y: parseFloat(rectMatch[2]),
      width: parseFloat(rectMatch[3]),
      height: parseFloat(rectMatch[4]),
    };
  }

  // Boolean string
  if (trimmed.toLowerCase() === 'true') return true;
  if (trimmed.toLowerCase() === 'false') return false;

  // Number string
  if (!isNaN(Number(trimmed)) && trimmed !== '') {
    return Number(trimmed);
  }

  return val;
}

export function parsePropertiesMap(props: Record<string, any>): Record<string, any> {
  const result: Record<string, any> = {};
  for (const [k, v] of Object.entries(props)) {
    result[k] = parseGodotVariant(v);
  }
  return result;
}
