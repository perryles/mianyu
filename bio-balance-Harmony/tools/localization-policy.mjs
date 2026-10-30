import { readdir, readFile } from 'node:fs/promises';
import { extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = fileURLToPath(new URL('../', import.meta.url));

function stripComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, (comment) => comment.replace(/[^\n]/g, ' '))
    .replace(/\/\/[^\n]*/g, (comment) => ' '.repeat(comment.length));
}

function parseJson5(source) {
  return JSON.parse(stripComments(source).replace(/,\s*([}\]])/g, '$1'));
}

function keyMap(resource) {
  return new Map((resource.string ?? []).map((entry) => [entry.name, entry.value]));
}

export function manifestViolations(manifest, displayPath) {
  const deviceTypes = manifest?.module?.deviceTypes;
  return Array.isArray(deviceTypes) && deviceTypes.length === 1 && deviceTypes[0] === 'phone' ? [] :
    [`${displayPath}: deviceTypes must be exactly ["phone"]`];
}

export function resourceViolations(base, zh, en, appScope = false) {
  const violations = [];
  const maps = { base: keyMap(base), zh_CN: keyMap(zh), en_US: keyMap(en) };
  const expectedKeys = [...maps.base.keys()].sort();
  for (const [locale, values] of Object.entries(maps)) {
    const keys = [...values.keys()].sort();
    if (JSON.stringify(keys) !== JSON.stringify(expectedKeys)) {
      violations.push(`${locale} resource key set differs from base`);
    }
  }
  for (const key of expectedKeys) {
    const expectedPlaceholders = [...`${maps.base.get(key)}`.matchAll(/%(\d+)\$[dfs]/g)].map((match) => match[1]).sort();
    for (const [locale, values] of Object.entries(maps)) {
      const placeholders = [...`${values.get(key) ?? ''}`.matchAll(/%(\d+)\$[dfs]/g)].map((match) => match[1]).sort();
      if (JSON.stringify(placeholders) !== JSON.stringify(expectedPlaceholders)) {
        violations.push(`${locale} ${key} placeholder set differs from base`);
      }
    }
  }
  if (appScope) {
    if (maps.base.get('app_name') !== '眠屿' || maps.zh_CN.get('app_name') !== '眠屿') {
      violations.push('Chinese app_name must be 眠屿');
    }
    if (maps.en_US.get('app_name') !== 'Mianyu') {
      violations.push('English app_name must be Mianyu');
    }
  }
  return violations;
}

export function sourceLiteralViolations(source, displayPath) {
  const withoutComments = stripComments(source);
  const violations = [];
  const literalPattern = /(['"`])(?:\\.|(?!\1)[\s\S])*?\1/g;
  for (const match of withoutComments.matchAll(literalPattern)) {
    if (/[\u3400-\u9fff]/u.test(match[0])) {
      const line = withoutComments.slice(0, match.index).split('\n').length;
      violations.push(`${displayPath}:${line}: user-visible CJK string literal must use app.string resources`);
    }
  }
  return violations;
}

async function sourceFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      return sourceFiles(path);
    }
    return ['.ets', '.ts'].includes(extname(entry.name)) ? [path] : [];
  }));
  return nested.flat();
}

async function readJson5(path) {
  return parseJson5(await readFile(path, 'utf8'));
}

async function verifyProject() {
  const violations = [];
  const manifests = [
    'entry/src/main/module.json5',
    'entry/src/ohosTest/module.json5'
  ];
  for (const manifestPath of manifests) {
    violations.push(...manifestViolations(
      await readJson5(join(projectRoot, manifestPath)),
      manifestPath
    ));
  }

  const resourceRoots = [
    ['AppScope/resources', true],
    ['entry/src/main/resources', false]
  ];
  for (const [resourceRoot, appScope] of resourceRoots) {
    const base = await readJson5(join(projectRoot, resourceRoot, 'base/element/string.json'));
    const zh = await readJson5(join(projectRoot, resourceRoot, 'zh_CN/element/string.json'));
    const en = await readJson5(join(projectRoot, resourceRoot, 'en_US/element/string.json'));
    violations.push(...resourceViolations(base, zh, en, appScope).map((message) => `${resourceRoot}: ${message}`));
  }
  const indexBase = await readJson5(join(projectRoot, 'entry/src/main/resources/base/element/index_string.json'));
  const indexZh = await readJson5(join(projectRoot, 'entry/src/main/resources/zh_CN/element/index_string.json'));
  const indexEn = await readJson5(join(projectRoot, 'entry/src/main/resources/en_US/element/index_string.json'));
  violations.push(...resourceViolations(indexBase, indexZh, indexEn).map((message) =>
    `entry/src/main/resources/index_string.json: ${message}`));

  const maintainedRoots = [
    join(projectRoot, 'entry/src/main/ets/pages'),
    join(projectRoot, 'entry/src/main/ets/service')
  ];
  for (const maintainedRoot of maintainedRoots) {
    for (const path of await sourceFiles(maintainedRoot)) {
      violations.push(...sourceLiteralViolations(
        await readFile(path, 'utf8'),
        relative(projectRoot, path)
      ));
    }
  }

  if (violations.length > 0) {
    console.error('HarmonyOS localization policy violations:');
    for (const violation of violations) {
      console.error(`- ${violation}`);
    }
    process.exitCode = 1;
  } else {
    console.log('HarmonyOS localization policy check passed.');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await verifyProject();
}
