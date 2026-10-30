import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  manifestViolations,
  resourceViolations,
  sourceLiteralViolations
} from './localization-policy.mjs';

test('requires phone-only capability declarations', () => {
  const manifest = { module: { deviceTypes: ['phone', 'wearable'] } };
  assert.deepEqual(manifestViolations(manifest, 'module.json5'), [
    'module.json5: deviceTypes must be exactly ["phone"]'
  ]);
  assert.deepEqual(manifestViolations({ module: { deviceTypes: ['phone'] } }, 'module.json5'), []);
});

test('requires identical locale keys and canonical brand names', () => {
  const base = { string: [{ name: 'app_name', value: '眠屿' }, { name: 'subtitle', value: '本机' }] };
  const zh = { string: [{ name: 'app_name', value: '眠屿' }, { name: 'subtitle', value: '本机' }] };
  const enMissing = { string: [{ name: 'app_name', value: 'Mianyu' }] };
  assert.match(resourceViolations(base, zh, enMissing, true)[0], /key set differs/);

  const enWrongBrand = {
    string: [{ name: 'app_name', value: 'Bio Balance' }, { name: 'subtitle', value: 'On device' }]
  };
  assert.match(resourceViolations(base, zh, enWrongBrand, true)[0], /English app_name must be Mianyu/);

  const en = { string: [{ name: 'app_name', value: 'Mianyu' }, { name: 'subtitle', value: 'On device' }] };
  assert.deepEqual(resourceViolations(base, zh, en, true), []);
});

test('requires formatted resources to preserve the same placeholder indexes', () => {
  const base = { string: [{ name: 'date', value: '%1$d月%2$d日 · %3$s' }] };
  const zh = { string: [{ name: 'date', value: '%1$d月%2$d日 · %3$s' }] };
  const en = { string: [{ name: 'date', value: '%3$s, %2$d' }] };
  assert.match(resourceViolations(base, zh, en)[0], /placeholder set differs/);
});

test('flags CJK string literals but ignores comments and stable ASCII keys', () => {
  const source = `
    // 用户可见说明只在注释中
    const key = 'medication';
    Text('健康提醒');
    const message = \`保存失败，请重试\`;
  `;
  const violations = sourceLiteralViolations(source, 'Page.ets');
  assert.equal(violations.length, 2);
  assert.match(violations[0], /Page\.ets:4/);
  assert.match(violations[1], /Page\.ets:5/);
});
