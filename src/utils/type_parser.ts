/**
 * Utility for parsing string representations of Godot engine variant types
 * into structured objects or formatted values.
 */

export interface GodotVector2 { __type: 'Vector2'; x: number; y: number }
export interface GodotVector2i { __type: 'Vector2i'; x: number; y: number }
export interface GodotVector3 { __type: 'Vector3'; x: number; y: number; z: number }
export interface GodotVector3i { __type: 'Vector3i'; x: number; y: number; z: number }
export interface GodotVector4 { __type: 'Vector4'; x: number; y: number; z: number; w: number }
export interface GodotColor { __type: 'Color'; r: number; g: number; b: number; a: number }
export interface GodotRect2 { __type: 'Rect2'; x: number; y: number; width: number; height: number }
export interface GodotRect2i { __type: 'Rect2i'; x: number; y: number; width: number; height: number }
export interface GodotQuaternion { __type: 'Quaternion'; x: number; y: number; z: number; w: number }
export interface GodotTransform2D { __type: 'Transform2D'; x: { x: number; y: number }; y: { x: number; y: number }; origin: { x: number; y: number } }
export interface GodotTransform3D { __type: 'Transform3D'; basis: any; origin: { x: number; y: number; z: number } }
export interface GodotBasis { __type: 'Basis'; x: { x: number; y: number; z: number }; y: { x: number; y: number; z: number }; z: { x: number; y: number; z: number } }

export function parseGodotVariant(val: any): any {
  if (Array.isArray(val)) {
    return val.map((elem) => parseGodotVariant(elem));
  }

  if (val && typeof val === 'object' && !val.__type) {
    // If dictionary has explicit keys matching variant structures
    if ('x' in val && 'y' in val && 'z' in val && 'w' in val) {
      return { __type: 'Quaternion', x: Number(val.x), y: Number(val.y), z: Number(val.z), w: Number(val.w) };
    }
    if ('x' in val && 'y' in val && 'z' in val) {
      return { __type: 'Vector3', x: Number(val.x), y: Number(val.y), z: Number(val.z) };
    }
    if ('x' in val && 'y' in val) {
      return { __type: 'Vector2', x: Number(val.x), y: Number(val.y) };
    }
    if ('r' in val && 'g' in val && 'b' in val) {
      return { __type: 'Color', r: Number(val.r), g: Number(val.g), b: Number(val.b), a: val.a !== undefined ? Number(val.a) : 1.0 };
    }
    // General dictionary recursion
    const res: Record<string, any> = {};
    for (const [k, v] of Object.entries(val)) {
      res[k] = parseGodotVariant(v);
    }
    return res;
  }

  if (typeof val !== 'string') return val;

  const trimmed = val.trim();

  // Vector2i(x, y)
  const vec2iMatch = /^Vector2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)$/i.exec(trimmed);
  if (vec2iMatch) {
    return {
      __type: 'Vector2i',
      x: parseInt(vec2iMatch[1], 10),
      y: parseInt(vec2iMatch[2], 10),
    };
  }

  // Vector2(x, y)
  const vec2Match = /^Vector2\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)$/i.exec(trimmed);
  if (vec2Match) {
    return {
      __type: 'Vector2',
      x: parseFloat(vec2Match[1]),
      y: parseFloat(vec2Match[2]),
    };
  }

  // Vector3i(x, y, z)
  const vec3iMatch = /^Vector3i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\)$/i.exec(trimmed);
  if (vec3iMatch) {
    return {
      __type: 'Vector3i',
      x: parseInt(vec3iMatch[1], 10),
      y: parseInt(vec3iMatch[2], 10),
      z: parseInt(vec3iMatch[3], 10),
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

  // Vector4(x, y, z, w)
  const vec4Match = /^Vector4\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)$/i.exec(trimmed);
  if (vec4Match) {
    return {
      __type: 'Vector4',
      x: parseFloat(vec4Match[1]),
      y: parseFloat(vec4Match[2]),
      z: parseFloat(vec4Match[3]),
      w: parseFloat(vec4Match[4]),
    };
  }

  // Quaternion(x, y, z, w)
  const quatMatch = /^Quaternion\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)$/i.exec(trimmed);
  if (quatMatch) {
    return {
      __type: 'Quaternion',
      x: parseFloat(quatMatch[1]),
      y: parseFloat(quatMatch[2]),
      z: parseFloat(quatMatch[3]),
      w: parseFloat(quatMatch[4]),
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

  // Rect2i(x, y, w, h)
  const rect2iMatch = /^Rect2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\)$/i.exec(trimmed);
  if (rect2iMatch) {
    return {
      __type: 'Rect2i',
      x: parseInt(rect2iMatch[1], 10),
      y: parseInt(rect2iMatch[2], 10),
      width: parseInt(rect2iMatch[3], 10),
      height: parseInt(rect2iMatch[4], 10),
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

  // Transform2D(ax, ay, bx, by, ox, oy)
  const t2dMatch = /^Transform2D\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)$/i.exec(trimmed);
  if (t2dMatch) {
    return {
      __type: 'Transform2D',
      x: { x: parseFloat(t2dMatch[1]), y: parseFloat(t2dMatch[2]) },
      y: { x: parseFloat(t2dMatch[3]), y: parseFloat(t2dMatch[4]) },
      origin: { x: parseFloat(t2dMatch[5]), y: parseFloat(t2dMatch[6]) },
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

