export function normalizeUrl(
  path: string,
  tenant?: string | undefined,
): string {
  const hostname = tenant ? `${tenant}.u.isuren.internal` : 'pipe.u.isuren.internal';
  const port = window.location.port;
  return `https://${hostname}${port ? `:${port}` : ''}${path}`;
}
