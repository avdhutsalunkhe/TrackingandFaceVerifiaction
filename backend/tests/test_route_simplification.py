import math
import pytest
from datetime import datetime, timedelta
from app.services.route_simplification_service import (
    RouteSimplificationService,
    RouteSimplificationOptions,
    haversine_distance_meters,
    calculate_bearing_degrees,
    angular_difference_degrees,
    perpendicular_cross_track_distance_meters,
)
from app.models.tracking import TrackingSession, GpsRoutePoint
from app.database import SessionLocal


def test_scenario_1_straight_route_with_redundant_points():
    """1. A straight route with many redundant intermediate points."""
    start_lat, start_lon = 18.520000, 73.850000
    now = datetime(2026, 10, 19, 10, 0, 0)

    # 50 points in a perfectly straight line going North (~10m between points = 500m total)
    points = [
        {
            "latitude": start_lat + (i * 0.00009),
            "longitude": start_lon,
            "recorded_at": (now + timedelta(seconds=i * 5)).isoformat(),
            "accuracy_meters": 5.0,
            "is_gap": 0,
        }
        for i in range(50)
    ]

    res = RouteSimplificationService.simplify_points(points, RouteSimplificationOptions(base_epsilon_meters=0.8))
    # A straight line should collapse to essentially start and end (<= 3 points)
    assert res.simplified_point_count <= 3
    assert res.reduction_percentage >= 94.0
    assert res.max_deviation_meters < 0.8
    assert res.retained_indices[0] == 0
    assert res.retained_indices[-1] == 49


def test_scenario_2_route_containing_sharp_turns():
    """2. A route containing sharp turns (e.g. 90-degree corners)."""
    now = datetime(2026, 10, 19, 10, 0, 0)
    points = []

    # Leg 1: 20 points going North
    for i in range(20):
        points.append({
            "latitude": 18.520000 + (i * 0.0001),
            "longitude": 73.850000,
            "recorded_at": (now + timedelta(seconds=i * 5)).isoformat(),
            "is_gap": 0,
        })
    corner1_idx = len(points) - 1

    # Leg 2: 20 points turning East (90 deg turn)
    for i in range(1, 21):
        points.append({
            "latitude": 18.520000 + (19 * 0.0001),
            "longitude": 73.850000 + (i * 0.0001),
            "recorded_at": (now + timedelta(seconds=(20 + i) * 5)).isoformat(),
            "is_gap": 0,
        })
    corner2_idx = len(points) - 1

    # Leg 3: 20 points turning South (90 deg turn)
    for i in range(1, 21):
        points.append({
            "latitude": (18.520000 + (19 * 0.0001)) - (i * 0.0001),
            "longitude": 73.850000 + (20 * 0.0001),
            "recorded_at": (now + timedelta(seconds=(40 + i) * 5)).isoformat(),
            "is_gap": 0,
        })

    res = RouteSimplificationService.simplify_points(points)
    # The corner vertices must be preserved
    assert corner1_idx in res.retained_indices
    assert corner2_idx in res.retained_indices
    assert res.retained_indices[0] == 0
    assert res.retained_indices[-1] == len(points) - 1
    # Significant reduction achieved
    assert res.simplified_point_count < 10
    assert res.max_deviation_meters <= 2.5


def test_scenario_3_curved_road():
    """3. A curved road (circular arc)."""
    now = datetime(2026, 10, 19, 10, 0, 0)
    points = []
    center_lat, center_lon = 18.520000, 73.850000
    radius = 0.001  # ~110m

    # Arc of 90 degrees sampled every 2 degrees (46 points)
    for idx, angle_deg in enumerate(range(0, 92, 2)):
        rad = math.radians(angle_deg)
        points.append({
            "latitude": center_lat + radius * math.sin(rad),
            "longitude": center_lon + radius * math.cos(rad),
            "recorded_at": (now + timedelta(seconds=idx * 5)).isoformat(),
            "is_gap": 0,
        })

    res = RouteSimplificationService.simplify_points(points, RouteSimplificationOptions(turn_epsilon_meters=0.5, straight_epsilon_meters=1.0))
    # Curve geometry must be smoothly preserved without exceeding max deviation
    assert res.max_deviation_meters <= 2.5
    # Must preserve endpoints
    assert res.retained_indices[0] == 0
    assert res.retained_indices[-1] == len(points) - 1
    # Number of points should be reduced while preserving arc shape
    assert res.simplified_point_count < len(points)
    assert res.simplified_point_count >= 4  # needs intermediate vertices to represent arc


def test_scenario_4_small_loop_and_retraced_path():
    """4. A small loop and a route that retraces its path."""
    now = datetime(2026, 10, 19, 10, 0, 0)
    # Route: Outbound along road, turnaround loop at end, return along same road
    points = []
    # Outbound: 10 points
    for i in range(10):
        points.append({"latitude": 18.5200 + (i * 0.0001), "longitude": 73.8500, "recorded_at": (now + timedelta(seconds=i * 10)).isoformat(), "is_gap": 0})
    turnaround_idx = len(points) - 1

    # Return along same road: 10 points backwards
    for i in range(1, 11):
        points.append({"latitude": (18.5200 + 0.0009) - (i * 0.0001), "longitude": 73.8500, "recorded_at": (now + timedelta(seconds=(10 + i) * 10)).isoformat(), "is_gap": 0})

    res = RouteSimplificationService.simplify_points(points, RouteSimplificationOptions(preserve_loops=True))
    # Turnaround apex must be preserved, and temporal order must not be collapsed
    assert turnaround_idx in res.retained_indices
    assert res.retained_indices[0] == 0
    assert res.retained_indices[-1] == len(points) - 1
    assert res.retained_indices == sorted(res.retained_indices)


def test_scenario_5_duplicate_and_near_duplicate_coordinates():
    """5. Duplicate and near-duplicate coordinates (stationary jitter)."""
    now = datetime(2026, 10, 19, 10, 0, 0)
    points = []
    # 30 points jittering within 0.3 meters of the same spot
    for i in range(30):
        points.append({
            "latitude": 18.520000 + ((i % 3) * 0.000001),
            "longitude": 73.850000 + (((i + 1) % 3) * 0.000001),
            "recorded_at": (now + timedelta(seconds=i * 3)).isoformat(),
            "is_gap": 0,
        })

    res = RouteSimplificationService.simplify_points(points, RouteSimplificationOptions(radial_pre_filter_meters=1.0))
    # Entire stationary jitter cluster should be collapsed to start and end
    assert res.simplified_point_count == 2
    assert res.reduction_percentage > 90.0


def test_scenario_6_noisy_smartphone_gps_samples():
    """6. Noisy smartphone GPS samples (minor sensor fluctuations)."""
    now = datetime(2026, 10, 19, 10, 0, 0)
    points = []
    # Straight road with ±1.0m lateral GPS noise
    for i in range(40):
        lateral_noise = 0.000008 if (i % 2 == 1) else -0.000008  # ~0.9m jitter
        points.append({
            "latitude": 18.520000 + (i * 0.0001),
            "longitude": 73.850000 + lateral_noise,
            "recorded_at": (now + timedelta(seconds=i * 5)).isoformat(),
            "is_gap": 0,
        })

    res = RouteSimplificationService.simplify_points(
        points,
        RouteSimplificationOptions(straight_epsilon_meters=2.0, min_turn_angle_degrees=20.0)
    )
    # Noise should not generate false turn anchors along a straight road
    assert res.simplified_point_count <= 4
    assert res.reduction_percentage >= 90.0


def test_scenario_7_gps_interruptions_and_separate_segments():
    """7. GPS interruptions and separate segments (recording gap)."""
    now = datetime(2026, 10, 19, 10, 0, 0)
    # Segment 1: 10 points
    points = [
        {"latitude": 18.5200 + (i * 0.0001), "longitude": 73.8500, "recorded_at": (now + timedelta(seconds=i * 5)).isoformat(), "is_gap": 0}
        for i in range(10)
    ]
    seg1_end = len(points) - 1

    # Point with is_gap = 1 (after a 30-minute GPS outage)
    seg2_start = len(points)
    points.append({
        "latitude": 18.5500,
        "longitude": 73.8700,
        "recorded_at": (now + timedelta(minutes=35)).isoformat(),
        "is_gap": 1,
    })

    # Segment 2: 10 points
    for i in range(1, 11):
        points.append({
            "latitude": 18.5500 + (i * 0.0001),
            "longitude": 73.8700,
            "recorded_at": (now + timedelta(minutes=35, seconds=i * 5)).isoformat(),
            "is_gap": 0,
        })

    res = RouteSimplificationService.simplify_points(points)
    # Gap boundary points MUST be retained as protected anchors
    assert seg1_end in res.retained_indices
    assert seg2_start in res.retained_indices
    assert seg1_end in res.protected_indices
    assert seg2_start in res.protected_indices


def test_scenario_8_protected_events_and_start_end():
    """8. A route with protected events and start/end points."""
    now = datetime(2026, 10, 19, 10, 0, 0)
    points = [
        {"latitude": 18.5200 + (i * 0.0001), "longitude": 73.8500, "recorded_at": (now + timedelta(seconds=i * 5)).isoformat(), "is_gap": 0}
        for i in range(25)
    ]

    res = RouteSimplificationService.simplify_points(points)
    assert 0 in res.protected_indices
    assert (len(points) - 1) in res.protected_indices
    assert res.retained_indices[0] == 0
    assert res.retained_indices[-1] == len(points) - 1


def test_scenario_9_route_with_very_few_points():
    """9. A route with very few points (0, 1, 2 points)."""
    now = datetime(2026, 10, 19, 10, 0, 0)

    # Empty
    res0 = RouteSimplificationService.simplify_points([])
    assert res0.simplified_point_count == 0

    # 1 point
    pt1 = [{"latitude": 18.5200, "longitude": 73.8500, "recorded_at": now.isoformat(), "is_gap": 0}]
    res1 = RouteSimplificationService.simplify_points(pt1)
    assert res1.simplified_point_count == 1
    assert res1.max_deviation_meters == 0.0

    # 2 points
    pt2 = [
        {"latitude": 18.5200, "longitude": 73.8500, "recorded_at": now.isoformat(), "is_gap": 0},
        {"latitude": 18.5300, "longitude": 73.8600, "recorded_at": (now + timedelta(seconds=60)).isoformat(), "is_gap": 0},
    ]
    res2 = RouteSimplificationService.simplify_points(pt2)
    assert res2.simplified_point_count == 2
    assert res2.max_deviation_meters == 0.0


def test_scenario_10_incomplete_or_invalid_coordinate_data():
    """10. Incomplete or invalid coordinate data."""
    now = datetime(2026, 10, 19, 10, 0, 0)
    # Mixed dict with missing speed, accuracy, bearing
    points = [
        {"latitude": 18.5200, "longitude": 73.8500, "recorded_at": now.isoformat()},
        {"latitude": 18.5201, "longitude": 73.8500},
        {"latitude": 18.5202, "longitude": 73.8500, "recorded_at": (now + timedelta(seconds=20)).isoformat()},
    ]
    res = RouteSimplificationService.simplify_points(points)
    assert res.simplified_point_count >= 2
    assert res.max_deviation_meters >= 0.0


def test_benchmark_session_25_with_397_points():
    """Benchmark the actual real-world 397-point route from Session 25."""
    db = SessionLocal()
    try:
        raw_pts = (
            db.query(GpsRoutePoint)
            .filter(GpsRoutePoint.session_id == 25)
            .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.sequence_number.asc())
            .all()
        )
        assert len(raw_pts) == 397, f"Expected 397 points in database for Session 25, got {len(raw_pts)}"

        # Verify database records are unchanged before and after
        db_count_before = len(raw_pts)
        session_obj = db.query(TrackingSession).filter(TrackingSession.id == 25).first()
        initial_distance = session_obj.total_distance_meters

        # Apply hybrid simplification
        opts = RouteSimplificationOptions(
            base_epsilon_meters=0.8,
            turn_epsilon_meters=0.4,
            straight_epsilon_meters=1.2,
            radial_pre_filter_meters=1.0,
            min_turn_angle_degrees=15.0,
            max_allowed_deviation_meters=2.5,
        )
        res = RouteSimplificationService.simplify_points(raw_pts, opts)

        # Print detailed benchmark report
        print(f"\n--- BENCHMARK REPORT FOR SESSION 25 (397 POINTS) ---")
        print(f"Original point count: {res.original_point_count}")
        print(f"Simplified display point count: {res.simplified_point_count}")
        print(f"Points removed: {res.original_point_count - res.simplified_point_count}")
        print(f"Reduction percentage: {res.reduction_percentage:.2f}%")
        print(f"Max measured geometric deviation: {res.max_deviation_meters:.3f} meters")
        print(f"Protected anchors count: {len(res.protected_indices)}")

        # Verification constraints:
        # 1. Reduction must be substantial (>= 70%) while preserving path geometry
        assert res.reduction_percentage >= 70.0
        # 2. Maximum deviation must be within the configured tolerance (<= 2.5m)
        assert res.max_deviation_meters <= 2.5
        # 3. All protected anchors remain present in the output
        for anchor_idx in res.protected_indices:
            assert anchor_idx in res.retained_indices, f"Protected anchor {anchor_idx} was omitted!"
        # 4. Start (0) and End (396) preserved
        assert res.retained_indices[0] == 0
        assert res.retained_indices[-1] == 396
        # 5. Temporal order strictly preserved
        assert res.retained_indices == sorted(res.retained_indices)

        # Verify that original database records and distance were NOT modified
        db_count_after = db.query(GpsRoutePoint).filter(GpsRoutePoint.session_id == 25).count()
        assert db_count_before == db_count_after == 397
        db.refresh(session_obj)
        assert session_obj.total_distance_meters == initial_distance
    finally:
        db.close()
