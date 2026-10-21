import math
from dataclasses import dataclass, field
from datetime import datetime
from typing import List, Dict, Any, Set, Tuple, Optional


@dataclass
class RouteSimplificationOptions:
    """Configuration tolerances for hybrid route simplification pipeline."""
    # Base perpendicular tolerance in meters (initial recommended value: 0.5 - 1.0 m)
    base_epsilon_meters: float = 0.8
    # Stricter perpendicular tolerance applied near significant turns, curves, and junctions
    turn_epsilon_meters: float = 0.4
    # Aggressive perpendicular tolerance applied along nearly straight segments
    straight_epsilon_meters: float = 1.2
    # Radial pre-filter distance threshold in meters for Stage A
    radial_pre_filter_meters: float = 1.0
    # Minimum angular direction change in degrees to identify a turn (Stage C)
    min_turn_angle_degrees: float = 15.0
    # Maximum allowable cross-track deviation in meters for Stage D validation
    max_allowed_deviation_meters: float = 2.5
    # Minimum spatial segment length in meters over which bearing is calculated to reject GPS jitter
    min_turn_segment_distance_meters: float = 3.0
    # Threshold in seconds for detecting GPS recording interruptions / gaps (15 min)
    gap_duration_seconds: int = 900
    # Preserve directional reversals and small loops
    preserve_loops: bool = True


@dataclass
class HybridSimplificationResult:
    """Summary of the simplification output and quality metrics."""
    simplified_points: List[Any]
    retained_indices: List[int]
    original_point_count: int
    simplified_point_count: int
    reduction_percentage: float
    max_deviation_meters: float
    protected_indices: Set[int] = field(default_factory=set)


def haversine_distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculates great-circle distance between two coordinates in meters."""
    R = 6371000.0  # Earth's mean radius in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2.0) ** 2
    return 2.0 * R * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))


def calculate_bearing_degrees(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculates initial bearing from point 1 to point 2 in degrees (0..360)."""
    dlon = math.radians(lon2 - lon1)
    lat1_r, lat2_r = math.radians(lat1), math.radians(lat2)
    y = math.sin(dlon) * math.cos(lat2_r)
    x = math.cos(lat1_r) * math.sin(lat2_r) - math.sin(lat1_r) * math.cos(lat2_r) * math.cos(dlon)
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


def angular_difference_degrees(a1: float, a2: float) -> float:
    """Calculates smallest angular difference between two bearings in degrees (0..180)."""
    diff = abs(a1 - a2) % 360.0
    return 360.0 - diff if diff > 180.0 else diff


def perpendicular_cross_track_distance_meters(
    p_lat: float, p_lon: float,
    a_lat: float, a_lon: float,
    b_lat: float, b_lon: float,
) -> float:
    """Calculates perpendicular cross-track distance in meters from point P to segment AB."""
    dist_ab = haversine_distance_meters(a_lat, a_lon, b_lat, b_lon)
    if dist_ab < 0.2:
        return haversine_distance_meters(p_lat, p_lon, a_lat, a_lon)

    dist_ap = haversine_distance_meters(a_lat, a_lon, p_lat, p_lon)
    dist_bp = haversine_distance_meters(b_lat, b_lon, p_lat, p_lon)

    # Triangle semiperimeter
    s = (dist_ab + dist_ap + dist_bp) / 2.0
    area_sq = s * (s - dist_ab) * (s - dist_ap) * (s - dist_bp)
    if area_sq <= 0.0:
        return 0.0

    # Height = 2 * Area / Base
    return (2.0 * math.sqrt(area_sq)) / dist_ab


class RouteSimplificationService:
    """Four-Stage Hybrid Route Simplification Engine."""

    @staticmethod
    def _extract_coord(pt: Any) -> Tuple[float, float, Optional[datetime], bool]:
        """Extracts (lat, lon, timestamp, is_gap) from dict or ORM object."""
        if isinstance(pt, dict):
            lat = float(pt.get("latitude", 0.0))
            lon = float(pt.get("longitude", 0.0))
            ts_raw = pt.get("recorded_at") or pt.get("captured_at")
            is_gap = bool(pt.get("is_gap", False))
        else:
            lat = float(getattr(pt, "latitude", 0.0))
            lon = float(getattr(pt, "longitude", 0.0))
            ts_raw = getattr(pt, "recorded_at", None)
            is_gap = bool(getattr(pt, "is_gap", False))

        ts: Optional[datetime] = None
        if isinstance(ts_raw, datetime):
            ts = ts_raw
        elif isinstance(ts_raw, str):
            try:
                s = ts_raw.replace("Z", "+00:00")
                ts = datetime.fromisoformat(s)
            except Exception:
                ts = None

        return lat, lon, ts, is_gap

    @classmethod
    def simplify_points(
        cls,
        points: List[Any],
        options: Optional[RouteSimplificationOptions] = None,
    ) -> HybridSimplificationResult:
        """Applies the 4-stage hybrid simplification algorithm to an ordered sequence of coordinates."""
        opts = options or RouteSimplificationOptions()
        n = len(points)

        if n <= 2:
            return HybridSimplificationResult(
                simplified_points=list(points),
                retained_indices=list(range(n)),
                original_point_count=n,
                simplified_point_count=n,
                reduction_percentage=0.0,
                max_deviation_meters=0.0,
                protected_indices=set(range(n)),
            )

        coords = [cls._extract_coord(p) for p in points]

        # =====================================================================
        # STAGE C: Turning-Point and Anchor Protection
        # Protect start, end, gaps, and noise-resistant turns before filtering
        # =====================================================================
        protected_indices: Set[int] = {0, n - 1}

        # 1. Protect GPS gap boundaries
        for i in range(n):
            lat, lon, ts, is_gap = coords[i]
            if is_gap:
                protected_indices.add(i)
                if i > 0:
                    protected_indices.add(i - 1)
            elif i > 0 and ts and coords[i - 1][2]:
                elapsed = abs((ts - coords[i - 1][2]).total_seconds())
                if elapsed >= opts.gap_duration_seconds:
                    protected_indices.add(i)
                    protected_indices.add(i - 1)

        # 2. Noise-resistant turn and junction detection
        turn_indices: Set[int] = set()
        for i in range(1, n - 1):
            if i in protected_indices:
                continue

            prev_idx = i - 1
            while (
                prev_idx > 0
                and (i - prev_idx) < 3
                and haversine_distance_meters(
                    coords[prev_idx][0], coords[prev_idx][1], coords[i][0], coords[i][1]
                ) < opts.min_turn_segment_distance_meters
            ):
                prev_idx -= 1

            next_idx = i + 1
            while (
                next_idx < n - 1
                and (next_idx - i) < 3
                and haversine_distance_meters(
                    coords[i][0], coords[i][1], coords[next_idx][0], coords[next_idx][1]
                ) < opts.min_turn_segment_distance_meters
            ):
                next_idx += 1

            dist_in = haversine_distance_meters(
                coords[prev_idx][0], coords[prev_idx][1], coords[i][0], coords[i][1]
            )
            dist_out = haversine_distance_meters(
                coords[i][0], coords[i][1], coords[next_idx][0], coords[next_idx][1]
            )

            # Requires physical movement on both sides to eliminate sensor jitter
            if dist_in >= opts.min_turn_segment_distance_meters and dist_out >= opts.min_turn_segment_distance_meters:
                b1 = calculate_bearing_degrees(
                    coords[prev_idx][0], coords[prev_idx][1], coords[i][0], coords[i][1]
                )
                b2 = calculate_bearing_degrees(
                    coords[i][0], coords[i][1], coords[next_idx][0], coords[next_idx][1]
                )
                turn_angle = angular_difference_degrees(b1, b2)
                if turn_angle >= opts.min_turn_angle_degrees:
                    protected_indices.add(i)
                    turn_indices.add(i)

        # 3. Preserve loops and path reversals (requires actual physical movement)
        if opts.preserve_loops:
            for i in range(1, n - 1):
                if i in protected_indices:
                    continue
                prev_p, curr_p, next_p = coords[i - 1], coords[i], coords[i + 1]
                dist_in = haversine_distance_meters(prev_p[0], prev_p[1], curr_p[0], curr_p[1])
                dist_out = haversine_distance_meters(curr_p[0], curr_p[1], next_p[0], next_p[1])
                if dist_in >= opts.min_turn_segment_distance_meters and dist_out >= opts.min_turn_segment_distance_meters:
                    b_in = calculate_bearing_degrees(prev_p[0], prev_p[1], curr_p[0], curr_p[1])
                    b_out = calculate_bearing_degrees(curr_p[0], curr_p[1], next_p[0], next_p[1])
                    if angular_difference_degrees(b_in, b_out) >= 120.0:
                        protected_indices.add(i)
                        turn_indices.add(i)

        # =====================================================================
        # STAGE A: Radial Distance Pre-Filter
        # Remove consecutive redundant coordinates within radial_pre_filter_meters,
        # but NEVER remove any protected anchor!
        # =====================================================================
        candidate_indices = [0]
        for i in range(1, n - 1):
            if i in protected_indices:
                candidate_indices.append(i)
            else:
                last_kept = candidate_indices[-1]
                dist = haversine_distance_meters(
                    coords[last_kept][0], coords[last_kept][1], coords[i][0], coords[i][1]
                )
                if dist >= opts.radial_pre_filter_meters:
                    candidate_indices.append(i)
        candidate_indices.append(n - 1)

        candidate_set = set(candidate_indices)

        # =====================================================================
        # STAGE B: Adaptive Ramer-Douglas-Peucker (RDP)
        # Simplify between adjacent protected anchors with geodesic distance.
        # =====================================================================
        retained_set: Set[int] = set(protected_indices)

        def rdp_recursive(start: int, end: int, epsilon: float):
            if end <= start + 1:
                return

            max_dist = 0.0
            idx_farthest = start

            start_lat, start_lon = coords[start][0], coords[start][1]
            end_lat, end_lon = coords[end][0], coords[end][1]

            for idx in range(start + 1, end):
                # Only consider candidates that survived Stage A pre-filter
                if idx not in candidate_set:
                    continue
                dist = perpendicular_cross_track_distance_meters(
                    coords[idx][0], coords[idx][1],
                    start_lat, start_lon,
                    end_lat, end_lon,
                )
                if dist > max_dist:
                    max_dist = dist
                    idx_farthest = idx

            if max_dist > epsilon:
                retained_set.add(idx_farthest)
                rdp_recursive(start, idx_farthest, epsilon)
                rdp_recursive(idx_farthest, end, epsilon)

        sorted_anchors = sorted(list(protected_indices))
        for a in range(len(sorted_anchors) - 1):
            s_idx = sorted_anchors[a]
            e_idx = sorted_anchors[a + 1]
            is_curved = (s_idx in turn_indices) or (e_idx in turn_indices)
            seg_eps = opts.turn_epsilon_meters if is_curved else opts.straight_epsilon_meters
            rdp_recursive(s_idx, e_idx, seg_eps)

        # =====================================================================
        # STAGE D: Maximum-Deviation Validation
        # Verify simplified line against all original points.
        # Restore worst-violating point if deviation exceeds max_allowed_deviation_meters.
        # =====================================================================
        retained_list = sorted(list(retained_set))
        max_deviation_measured = 0.0

        max_passes = 50
        while max_passes > 0:
            max_passes -= 1
            worst_deviation = 0.0
            worst_violator: Optional[int] = None

            for i in range(len(retained_list) - 1):
                s = retained_list[i]
                e = retained_list[i + 1]
                s_lat, s_lon = coords[s][0], coords[s][1]
                e_lat, e_lon = coords[e][0], coords[e][1]

                for p in range(s + 1, e):
                    dev = perpendicular_cross_track_distance_meters(
                        coords[p][0], coords[p][1],
                        s_lat, s_lon,
                        e_lat, e_lon,
                    )
                    if dev > worst_deviation:
                        worst_deviation = dev
                        worst_violator = p

            if worst_deviation > max_deviation_measured:
                max_deviation_measured = worst_deviation

            if worst_deviation > opts.max_allowed_deviation_meters and worst_violator is not None:
                retained_set.add(worst_violator)
                retained_list = sorted(list(retained_set))
            else:
                break

        final_indices = sorted(list(retained_set))
        simplified_points = [points[i] for i in final_indices]
        reduction = ((n - len(simplified_points)) / n) * 100.0 if n > 0 else 0.0

        return HybridSimplificationResult(
            simplified_points=simplified_points,
            retained_indices=final_indices,
            original_point_count=n,
            simplified_point_count=len(simplified_points),
            reduction_percentage=reduction,
            max_deviation_meters=max_deviation_measured,
            protected_indices=protected_indices,
        )
