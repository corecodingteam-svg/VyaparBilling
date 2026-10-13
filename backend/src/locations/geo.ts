export interface Point {
  latitude: number;
  longitude: number;
}

export interface Fence extends Point {
  name: string;
  radiusM: number;
}

const rad = (d: number) => (d * Math.PI) / 180;

/** Distance between two points on the ground, in metres. */
export function metresBetween(a: Point, b: Point): number {
  const dLat = rad(b.latitude - a.latitude);
  const dLon = rad(b.longitude - a.longitude);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(dLon / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Length of a trail in metres. Steps shorter than [jitterM] are ignored, so a phone sitting still (whose
 * reported position wanders a few metres) does not add up to a journey.
 */
export function routeMetres(points: Point[], jitterM = 25): number {
  let total = 0;
  let last: Point | undefined;
  for (const p of points) {
    if (!last) {
      last = p;
      continue;
    }
    const d = metresBetween(last, p);
    if (d < jitterM) continue;
    total += d;
    last = p;
  }
  return total;
}

/** The zone a point is in: the nearest one whose circle contains it, or null. */
export function zoneOf(p: Point, fences: Fence[]): string | null {
  let best: { name: string; d: number } | null = null;
  for (const f of fences) {
    const d = metresBetween(p, f);
    if (d <= f.radiusM && (!best || d < best.d)) best = { name: f.name, d };
  }
  return best?.name ?? null;
}

/** Stretches of a trail spent inside zones, oldest first: which zone, from when to when. */
export function visits<T extends Point & { at: Date }>(points: T[], fences: Fence[]): { zone: string; from: Date; to: Date }[] {
  const out: { zone: string; from: Date; to: Date }[] = [];
  let current: string | null = null;
  for (const p of points) {
    const zone = zoneOf(p, fences);
    // Leaving a zone ends the visit, so coming back later starts a new one.
    if (zone && zone === current) out[out.length - 1].to = p.at;
    else if (zone) out.push({ zone, from: p.at, to: p.at });
    current = zone;
  }
  return out;
}
