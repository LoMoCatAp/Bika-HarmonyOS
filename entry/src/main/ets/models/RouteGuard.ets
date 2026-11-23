export function isAllowedDirectAddress(value: string): boolean {
  if (value.length === 0 || value.length > 45 || /[:][/][/]|[/?#@ %\[\]]/.test(value)) {
    return false;
  }

  const ipv4Parts = value.split('.');
  if (ipv4Parts.length === 4) {
    for (let part of ipv4Parts) {
      if (!/^\d{1,3}$/.test(part) || Number(part) > 255) {
        return false;
      }
    }
    return true;
  }

  if (value.indexOf('.') >= 0 || value.indexOf(':') < 0) {
    return false;
  }
  const compressionCount = (value.match(/::/g) || []).length;
  if (compressionCount > 1 || value.indexOf(':') < 0) {
    return false;
  }
  const hasCompression = compressionCount === 1;
  const sides = hasCompression ? value.split('::') : [value, ''];
  const groups = sides[0].length === 0 ? [] : sides[0].split(':');
  const rightGroups = sides[1].length === 0 ? [] : sides[1].split(':');
  const allGroups = groups.concat(rightGroups);
  if (allGroups.some((group: string): boolean => !/^[0-9a-fA-F]{1,4}$/.test(group))) {
    return false;
  }
  if (hasCompression) {
    return allGroups.length <= 7;
  }
  return allGroups.length === 8;
}

export function shouldTryPlaintextBootstrap(poolExhausted: boolean, lastHttpAt: number, now: number): boolean {
  if (!poolExhausted) {
    return false;
  }
  if (lastHttpAt === 0) {
    return true;
  }
  return now - lastHttpAt >= 30 * 60 * 1000;
}
