import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/team_location.dart';
import '../../shared/theme.dart';

/// Map pictures come from OpenStreetMap over the internet. Switched off where there is none to reach (tests).
bool mapTilesEnabled = true;

/// A pin on the map: where it is, what to call it, and whether it stands out.
typedef MapPin = ({double latitude, double longitude, String label, bool strong});

/// A street map with people's positions, an optional route joining [route] in order, and the zones as circles.
/// [onTap] reports where the map was tapped (used to place a new zone).
class TeamMap extends StatelessWidget {
  const TeamMap({super.key, this.pins = const [], this.route = const [], this.zones = const [], this.draft, this.onTap, this.height = 320});

  final List<MapPin> pins;
  final List<(double, double)> route;
  final List<Geofence> zones;

  /// A zone being placed: (latitude, longitude, radius in metres).
  final (double, double, int)? draft;
  final void Function(double latitude, double longitude)? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final p in pins) LatLng(p.latitude, p.longitude),
      for (final (lat, lon) in route) LatLng(lat, lon),
      for (final z in zones) LatLng(z.latitude, z.longitude),
      if (draft != null) LatLng(draft!.$1, draft!.$2),
    ];
    // With nothing to show, open on India rather than the middle of the ocean.
    final single = points.length == 1 || points.toSet().length == 1;
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: points.isEmpty ? const LatLng(22.5, 79) : points.first,
            initialZoom: points.isEmpty ? 4.5 : 15,
            initialCameraFit: points.isEmpty || single ? null : CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(48), maxZoom: 16),
            onTap: onTap == null ? null : (_, at) => onTap!(at.latitude, at.longitude),
          ),
          children: [
            if (mapTilesEnabled) TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.advaitamaa.billing_app', maxZoom: 19),
            CircleLayer(
              circles: [
                for (final z in zones)
                  CircleMarker(
                    point: LatLng(z.latitude, z.longitude), radius: z.radiusM.toDouble(), useRadiusInMeter: true,
                    color: receiveGreen.withValues(alpha: 0.15), borderColor: receiveGreen, borderStrokeWidth: 1.5,
                  ),
                if (draft != null)
                  CircleMarker(
                    point: LatLng(draft!.$1, draft!.$2), radius: draft!.$3.toDouble(), useRadiusInMeter: true,
                    color: brandBlue.withValues(alpha: 0.18), borderColor: brandBlue, borderStrokeWidth: 2,
                  ),
              ],
            ),
            if (route.length > 1) PolylineLayer(polylines: [Polyline(points: [for (final (lat, lon) in route) LatLng(lat, lon)], strokeWidth: 3, color: brandBlue)]),
            MarkerLayer(
              markers: [
                for (final z in zones)
                  Marker(
                    point: LatLng(z.latitude, z.longitude), width: 140, height: 18,
                    child: Text(z.name, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
                  ),
                for (final p in pins)
                  Marker(
                    point: LatLng(p.latitude, p.longitude), width: 140, height: 46, alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (p.label.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black26)),
                            child: Text(p.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                          ),
                        Icon(Icons.location_on, color: p.strong ? payRed : brandBlue, size: 26),
                      ],
                    ),
                  ),
              ],
            ),
            const Align(
              alignment: Alignment.bottomRight,
              child: Padding(padding: EdgeInsets.all(4), child: Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 10, color: Colors.black54, backgroundColor: Colors.white70))),
            ),
          ],
        ),
      ),
    );
  }
}
