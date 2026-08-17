import { describe, it, expect } from 'vitest';
import { parseGodotVariant, parsePropertiesMap } from '../src/utils/type_parser.js';

describe('type_parser', () => {
  it('parses Vector2', () => {
    expect(parseGodotVariant('Vector2(1, 2.5)')).toEqual({ __type: 'Vector2', x: 1, y: 2.5 });
  });
  it('parses Vector2i', () => {
    expect(parseGodotVariant('Vector2i(1, 2)')).toEqual({ __type: 'Vector2i', x: 1, y: 2 });
  });
  it('parses Vector3', () => {
    expect(parseGodotVariant('Vector3(1, 2.5, 3)')).toEqual({ __type: 'Vector3', x: 1, y: 2.5, z: 3 });
  });
  it('parses Vector3i', () => {
    expect(parseGodotVariant('Vector3i(1, 2, 3)')).toEqual({ __type: 'Vector3i', x: 1, y: 2, z: 3 });
  });
  it('parses Vector4', () => {
    expect(parseGodotVariant('Vector4(1, 2.5, 3, 4)')).toEqual({ __type: 'Vector4', x: 1, y: 2.5, z: 3, w: 4 });
  });
  it('parses Quaternion', () => {
    expect(parseGodotVariant('Quaternion(1, 2.5, 3, 4)')).toEqual({ __type: 'Quaternion', x: 1, y: 2.5, z: 3, w: 4 });
  });
  it('parses Color', () => {
    expect(parseGodotVariant('Color(1, 0.5, 0)')).toEqual({ __type: 'Color', r: 1, g: 0.5, b: 0, a: 1 });
    expect(parseGodotVariant('Color(1, 0.5, 0, 0.8)')).toEqual({ __type: 'Color', r: 1, g: 0.5, b: 0, a: 0.8 });
  });
  it('parses Rect2', () => {
    expect(parseGodotVariant('Rect2(1, 2, 3, 4)')).toEqual({ __type: 'Rect2', x: 1, y: 2, width: 3, height: 4 });
  });
  it('parses Rect2i', () => {
    expect(parseGodotVariant('Rect2i(1, 2, 3, 4)')).toEqual({ __type: 'Rect2i', x: 1, y: 2, width: 3, height: 4 });
  });
  it('parses Transform2D', () => {
    expect(parseGodotVariant('Transform2D(1, 2, 3, 4, 5, 6)')).toEqual({
      __type: 'Transform2D',
      x: { x: 1, y: 2 },
      y: { x: 3, y: 4 },
      origin: { x: 5, y: 6 },
    });
  });
  it('parses boolean string', () => {
    expect(parseGodotVariant('true')).toBe(true);
    expect(parseGodotVariant('false')).toBe(false);
  });
  it('parses number string', () => {
    expect(parseGodotVariant('123.45')).toBe(123.45);
  });
  it('returns original if not matching', () => {
    expect(parseGodotVariant('SomeOtherString')).toBe('SomeOtherString');
    expect(parseGodotVariant('')).toBe('');
    expect(parseGodotVariant(123)).toBe(123);
  });
  it('parses arrays', () => {
    expect(parseGodotVariant(['Vector2(1, 2)', 'true'])).toEqual([
      { __type: 'Vector2', x: 1, y: 2 },
      true
    ]);
  });
  it('parses objects representing types', () => {
    expect(parseGodotVariant({ x: 1, y: 2, z: 3, w: 4 })).toEqual({ __type: 'Quaternion', x: 1, y: 2, z: 3, w: 4 });
    expect(parseGodotVariant({ x: 1, y: 2, z: 3 })).toEqual({ __type: 'Vector3', x: 1, y: 2, z: 3 });
    expect(parseGodotVariant({ x: 1, y: 2 })).toEqual({ __type: 'Vector2', x: 1, y: 2 });
    expect(parseGodotVariant({ r: 1, g: 0.5, b: 0 })).toEqual({ __type: 'Color', r: 1, g: 0.5, b: 0, a: 1 });
    expect(parseGodotVariant({ r: 1, g: 0.5, b: 0, a: 0.5 })).toEqual({ __type: 'Color', r: 1, g: 0.5, b: 0, a: 0.5 });
  });
  it('parses nested dictionaries and type arrays', () => {
    expect(parseGodotVariant({ test: 'Vector2(1, 2)' })).toEqual({ test: { __type: 'Vector2', x: 1, y: 2 } });
    expect(parseGodotVariant({ __type: 'Unknown', foo: 'bar' })).toEqual({ __type: 'Unknown', foo: 'bar' });
  });

  describe('parsePropertiesMap', () => {
    it('parses map of properties', () => {
      expect(parsePropertiesMap({
        pos: 'Vector2(1, 2)',
        active: 'true'
      })).toEqual({
        pos: { __type: 'Vector2', x: 1, y: 2 },
        active: true
      });
    });
  });
});
