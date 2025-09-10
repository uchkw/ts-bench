// Utilities for creating filesystem-safe and Docker-safe path segments

/**
 * Sanitize a string to be safe as a single filesystem path segment.
 * - Replaces characters that are problematic in filenames or Docker volume specs
 *   including: \\, /, :, *, ?, " , <, >, | and whitespace with '-'
 * - Collapses consecutive '-' into a single '-'
 * - Trims leading/trailing '-'
 */
export function sanitizePathSegment(input: string): string {
  if (!input) return "";
  return input
    .replace(/[\\/:*?"<>|\s]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

/**
 * Sanitize an ISO timestamp for filenames.
 * Output format: YYYYMMDD-hhmmss (UTC), e.g. 20250910-135625
 */
export function sanitizeTimestampForFilename(iso: string): string {
  if (!iso) return '';
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  const yyyy = d.getUTCFullYear();
  const mm = pad(d.getUTCMonth() + 1);
  const dd = pad(d.getUTCDate());
  const hh = pad(d.getUTCHours());
  const mi = pad(d.getUTCMinutes());
  const ss = pad(d.getUTCSeconds());
  return `${yyyy}${mm}${dd}-${hh}${mi}${ss}`;
}
