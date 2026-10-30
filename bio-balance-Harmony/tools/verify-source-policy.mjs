import { readdir, readFile } from 'node:fs/promises';
import { extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = fileURLToPath(new URL('../', import.meta.url));
const sourceRoot = join(projectRoot, 'entry/src/main/ets');

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

function lineNumber(source, offset) {
  return source.slice(0, offset).split('\n').length;
}

function callExpression(source, markerOffset) {
  const openingParenthesis = source.indexOf('(', markerOffset);
  if (openingParenthesis < 0) {
    return '';
  }

  let depth = 0;
  let quote = '';
  let escaped = false;
  let lineComment = false;
  let blockComment = false;
  for (let offset = openingParenthesis; offset < source.length; offset += 1) {
    const character = source[offset];
    const nextCharacter = source[offset + 1];
    if (lineComment) {
      if (character === '\n') {
        lineComment = false;
      }
      continue;
    }
    if (blockComment) {
      if (character === '*' && nextCharacter === '/') {
        blockComment = false;
        offset += 1;
      }
      continue;
    }
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (character === '\\') {
        escaped = true;
      } else if (character === quote) {
        quote = '';
      }
      continue;
    }
    if (character === '/' && nextCharacter === '/') {
      lineComment = true;
      offset += 1;
    } else if (character === '/' && nextCharacter === '*') {
      blockComment = true;
      offset += 1;
    } else if (character === "'" || character === '"' || character === '`') {
      quote = character;
    } else if (character === '(') {
      depth += 1;
    } else if (character === ')') {
      depth -= 1;
      if (depth === 0) {
        return source.slice(markerOffset, offset + 1);
      }
    }
  }
  return source.slice(markerOffset);
}

function markerOffsets(source, pattern) {
  return [...source.matchAll(pattern)].map((match) => match.index);
}

function escapedPattern(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function importedHilogBindings(source) {
  const bindings = new Set(['hilog']);
  const defaultOrNamespaceImport = /import\s+(?:\*\s+as\s+)?([A-Za-z_$][\w$]*)\s+from\s+['"](?:@ohos\.hilog|@ohos\/hilog)['"]/g;
  for (const match of source.matchAll(defaultOrNamespaceImport)) {
    bindings.add(match[1]);
  }
  const namedKitImport = /import\s*\{([\s\S]*?)\}\s*from\s*['"]@kit\.PerformanceAnalysisKit['"]/g;
  for (const match of source.matchAll(namedKitImport)) {
    for (const member of match[1].split(',')) {
      const imported = member.trim().match(/^hilog(?:\s+as\s+([A-Za-z_$][\w$]*))?$/);
      if (imported) {
        bindings.add(imported[1] ?? 'hilog');
      }
    }
  }
  return bindings;
}

function splitArguments(call) {
  const openingParenthesis = call.indexOf('(');
  const source = call.slice(openingParenthesis + 1, -1);
  const argumentsList = [];
  let start = 0;
  let depth = 0;
  let quote = '';
  let escaped = false;
  let lineComment = false;
  let blockComment = false;
  for (let offset = 0; offset < source.length; offset += 1) {
    const character = source[offset];
    const nextCharacter = source[offset + 1];
    if (lineComment) {
      if (character === '\n') {
        lineComment = false;
      }
      continue;
    }
    if (blockComment) {
      if (character === '*' && nextCharacter === '/') {
        blockComment = false;
        offset += 1;
      }
      continue;
    }
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (character === '\\') {
        escaped = true;
      } else if (character === quote) {
        quote = '';
      }
      continue;
    }
    if (character === '/' && nextCharacter === '/') {
      lineComment = true;
      offset += 1;
    } else if (character === '/' && nextCharacter === '*') {
      blockComment = true;
      offset += 1;
    } else if (character === "'" || character === '"' || character === '`') {
      quote = character;
    } else if (character === '(' || character === '[' || character === '{') {
      depth += 1;
    } else if (character === ')' || character === ']' || character === '}') {
      depth -= 1;
    } else if (character === ',' && depth === 0) {
      argumentsList.push(source.slice(start, offset).trim());
      start = offset + 1;
    }
  }
  argumentsList.push(source.slice(start).trim());
  return argumentsList;
}

function fixedStringValue(expression) {
  const withoutComments = expression.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '').trim();
  const quote = withoutComments[0];
  if (!["'", '"', '`'].includes(quote) || withoutComments.at(-1) !== quote) {
    return undefined;
  }
  const value = withoutComments.slice(1, -1);
  if (quote === '`' && value.includes('${')) {
    return undefined;
  }
  return value;
}

function validDynamicArgument(key, expression) {
  if (key === 'errorCode') {
    return /^(?:(?:[A-Za-z_$][\w$]*)\.)*code$/.test(expression) ||
      /^(?:errorCode|[A-Za-z_$][\w$]*ErrorCode)$/.test(expression);
  }
  if (key === 'durationMs') {
    return /^(?:durationMs|[A-Za-z_$][\w$]*DurationMs)$/.test(expression);
  }
  return /^(?:technicalId|[A-Za-z_$][\w$]*(?:Id|ID))$/.test(expression);
}

function validateHilog(call) {
  const argumentsList = splitArguments(call);
  if (argumentsList.length < 3) {
    return 'hilog calls require domain, stable tag, and a fixed operation format';
  }
  if (!/^(?:DOMAIN|[A-Z][A-Z0-9_]*_DOMAIN|0x[0-9A-Fa-f]+|\d+)$/.test(argumentsList[0])) {
    return 'hilog domain must be a fixed technical constant';
  }
  const fixedTag = fixedStringValue(argumentsList[1]);
  const stableTag = /^(?:TAG|[A-Z][A-Z0-9_]*_TAG)$/.test(argumentsList[1]) ||
    (fixedTag !== undefined && /^[A-Za-z][A-Za-z0-9_.-]{0,22}$/.test(fixedTag));
  if (!stableTag) {
    return 'hilog tag must be a fixed technical constant';
  }
  const format = fixedStringValue(argumentsList[2]);
  if (format === undefined) {
    return 'hilog format must be a fixed string literal';
  }
  const allowedFormat = /^operation=[a-z][a-z0-9_]*(?: (?:errorCode=(?:-?\d+|%\{public\}d)|durationMs=(?:\d+|%\{public\}d)|technicalId=%\{public\}s))*$/;
  if (!allowedFormat.test(format)) {
    return 'hilog format contains fields outside operation, technicalId, errorCode, or durationMs';
  }

  const placeholders = [...format.matchAll(/(errorCode|durationMs|technicalId)=%\{public\}([ds])/g)];
  const dynamicArguments = argumentsList.slice(3);
  if (placeholders.length !== dynamicArguments.length) {
    return 'hilog dynamic arguments do not match approved format fields';
  }
  for (let index = 0; index < placeholders.length; index += 1) {
    const key = placeholders[index][1];
    const type = placeholders[index][2];
    if ((key === 'technicalId' && type !== 's') || (key !== 'technicalId' && type !== 'd') ||
      !validDynamicArgument(key, dynamicArguments[index])) {
      return `hilog ${key} argument is not an approved technical value`;
    }
  }
  return undefined;
}

export function scanSource(source, displayPath) {
  const violations = [];

  const consoleAliasPattern = /\b(?:const|let|var)\s+(?:[A-Za-z_$][\w$]*|\{[^}]*\})\s*=\s*console\b|\bconsole\s*=/g;
  for (const offset of markerOffsets(source, consoleAliasPattern)) {
    violations.push(`${displayPath}:${lineNumber(source, offset)} console must not be aliased or reassigned`);
  }
  for (const offset of markerOffsets(source, /\bconsole\.[A-Za-z]+\s*\(/g)) {
    violations.push(`${displayPath}:${lineNumber(source, offset)} console logging is forbidden in maintained application source`);
  }

  for (const binding of importedHilogBindings(source)) {
    const bindingPattern = escapedPattern(binding);
    const aliasPattern = new RegExp(`\\b(?:const|let|var)\\s+[A-Za-z_$][\\w$]*\\s*=\\s*${bindingPattern}\\b|\\b${bindingPattern}\\s*=`, 'g');
    for (const offset of markerOffsets(source, aliasPattern)) {
      violations.push(`${displayPath}:${lineNumber(source, offset)} HiLog binding must not be aliased or reassigned`);
    }

    const callPattern = new RegExp(`\\b${bindingPattern}\\.[A-Za-z]+\\s*\\(`, 'g');
    for (const offset of markerOffsets(source, callPattern)) {
      const call = callExpression(source, offset);
      const line = lineNumber(source, offset);
      const reason = validateHilog(call);
      if (reason) {
        violations.push(`${displayPath}:${line} ${reason}`);
      }
    }
  }

  for (const offset of markerOffsets(source, /\banimateTo\s*\(/g)) {
    const call = callExpression(source, offset);
    if (/\bselectedTab\s*=/.test(call)) {
      violations.push(`${displayPath}:${lineNumber(source, offset)} animates tab state used by Text properties`);
    }
  }
  return violations;
}

async function verifyProjectSource() {
  const violations = [];
  for (const path of await sourceFiles(sourceRoot)) {
    const source = await readFile(path, 'utf8');
    violations.push(...scanSource(source, relative(projectRoot, path)));
  }
  if (violations.length > 0) {
    console.error('HarmonyOS source policy violations:');
    for (const violation of violations) {
      console.error(`- ${violation}`);
    }
    process.exitCode = 1;
  } else {
    console.log('HarmonyOS source policy check passed.');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await verifyProjectSource();
}
