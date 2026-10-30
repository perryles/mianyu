import assert from 'node:assert/strict';
import { test } from 'node:test';
import { scanSource } from './verify-source-policy.mjs';

function violations(source) {
  return scanSource(source, 'fixture.ets');
}

test('accepts fixed operations plus error-code and duration fields', () => {
  const source = `
    hilog.info(DOMAIN, TAG, 'operation=ability_create');
    hilog.error(DOMAIN, TAG,
      'operation=load_content errorCode=%{public}d durationMs=%{public}d', err.code, durationMs);
  `;
  assert.deepEqual(violations(source), []);
});

test('rejects every console call', () => {
  assert.match(violations('console.info(healthRecord);')[0], /console logging is forbidden/);
});

test('rejects direct dynamic or object hilog payloads', () => {
  const source = `
    hilog.info(DOMAIN, TAG, '%{public}s', userText);
    hilog.info(DOMAIN, TAG, 'operation=debug payload=%{public}s', healthRecord);
  `;
  assert.equal(violations(source).length, 2);
});

test('rejects indirectly serialized hilog payloads', () => {
  const source = `
    const payload = JSON.stringify(frameworkObject);
    hilog.error(DOMAIN, TAG, 'operation=restore payload=%{public}s', payload);
  `;
  assert.equal(violations(source).length, 1);
});

test('rejects interpolated log format strings', () => {
  const source = 'hilog.info(DOMAIN, TAG, `operation=debug value=${healthValue}`);';
  assert.match(violations(source)[0], /fixed string literal/);
});

test('rejects animated state that controls tab text properties', () => {
  const source = `
    this.getUIContext().animateTo(
      { duration: 180 },
      () => { this.selectedTab = index; }
    );
  `;
  assert.match(violations(source)[0], /animates tab state/);
});

test('allows JSON serialization used only for local persistence', () => {
  const source = 'store.putSync(key, JSON.stringify(record));';
  assert.deepEqual(violations(source), []);
});

test('handles multiline calls, nested parentheses, and comments', () => {
  const source = `
    hilog.info(
      DOMAIN,
      TAG,
      'operation=ability_create' /* a comment containing ) */
    );
  `;
  assert.deepEqual(violations(source), []);
});

test('rejects dynamic domains and tags', () => {
  const source = `
    hilog.info(userDomain, TAG, 'operation=ability_create');
    hilog.info(DOMAIN, userText, 'operation=ability_create');
  `;
  assert.equal(violations(source).length, 2);
});

test('checks the actual binding imported from HiLog', () => {
  const source = `
    import logger from '@ohos.hilog';
    logger.info(DOMAIN, TAG, '%{public}s', userText);
  `;
  assert.equal(violations(source).length, 1);
});

test('rejects aliasing the HiLog binding', () => {
  const source = `
    import hilog from '@ohos.hilog';
    const logger = hilog;
    logger.info(DOMAIN, TAG, '%{public}s', userText);
  `;
  assert.match(violations(source)[0], /must not be aliased or reassigned/);
});

test('rejects aliasing console', () => {
  const source = `
    const logger = console;
    logger.info(healthRecord);
  `;
  assert.match(violations(source)[0], /console must not be aliased/);
});
