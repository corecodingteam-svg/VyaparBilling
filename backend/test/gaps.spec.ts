import { metresBetween, routeMetres, visits, zoneOf } from '../src/locations/geo';

describe('distance and zones', () => {
  const pune = { latitude: 18.5204, longitude: 73.8567 };
  const mumbai = { latitude: 19.076, longitude: 72.8777 };

  it('measures distance on the ground', () => {
    expect(Math.round(metresBetween(pune, mumbai) / 1000)).toBe(120);
    expect(metresBetween(pune, pune)).toBe(0);
  });

  it('adds up a route but not a parked phone’s jitter', () => {
    const jitter = [pune, { latitude: 18.52045, longitude: 73.8567 }, { latitude: 18.5204, longitude: 73.85675 }, pune];
    expect(routeMetres(jitter)).toBe(0);
    expect(Math.round(routeMetres([pune, mumbai, pune]) / 1000)).toBe(240);
    expect(routeMetres([])).toBe(0);
  });

  it('finds the zone a point is in and the visits along a trail', () => {
    const fences = [{ name: 'Shop', ...pune, radiusM: 200 }, { name: 'Warehouse', ...mumbai, radiusM: 500 }];
    expect(zoneOf({ latitude: 18.521, longitude: 73.8567 }, fences)).toBe('Shop');
    expect(zoneOf({ latitude: 18.6, longitude: 73.8567 }, fences)).toBeNull();
    const at = (h: number) => new Date(Date.UTC(2026, 9, 13, h));
    const trail = [
      { ...pune, at: at(4) }, { ...pune, at: at(5) }, { latitude: 18.8, longitude: 73.4, at: at(6) }, { ...mumbai, at: at(8) }, { latitude: 18.8, longitude: 73.4, at: at(10) }, { ...pune, at: at(12) },
    ];
    expect(visits(trail, fences)).toEqual([
      { zone: 'Shop', from: at(4), to: at(5) }, { zone: 'Warehouse', from: at(8), to: at(8) }, { zone: 'Shop', from: at(12), to: at(12) },
    ]);
  });
});
