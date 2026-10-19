import React, { useState, useEffect, useRef } from 'react';
import {
  Calendar,
  RefreshCw,
  Clock,
  Route,
  User,
  MapPin,
  Layers,
  ZoomIn,
  ZoomOut,
  Eye,
  EyeOff,
  Crosshair,
  BarChart2,
  ArrowLeft,
  BookOpen
} from 'lucide-react';
import { useNavigate, useLocation } from 'react-router-dom';
import { api } from '../services/api';

interface TrackingSession {
  id: number;
  session_uuid: string;
  user_id: number;
  employee_id: string;
  employee_name?: string;
  status: string;
  start_time: string;
  end_time?: string;
  start_latitude?: number | null;
  start_longitude?: number | null;
  end_latitude?: number | null;
  end_longitude?: number | null;
  total_distance_meters: number;
  point_count: number;
}

interface RoutePoint {
  id: number;
  sequence_number: number;
  latitude: number;
  longitude: number;
  accuracy_meters: number;
  speed_mps?: number;
  recorded_at: string;
}

export const EmployeeTravelMapScreen: React.FC = () => {
  const navigate = useNavigate();
  const location = useLocation();

  // Navigation context parameters
  const queryParams = new URLSearchParams(location.search);
  const locationState = (location.state as any) || {};

  const resolvedUserId = locationState.userId || queryParams.get('userId') || queryParams.get('user_id');
  const employeeCode = locationState.employeeCode || queryParams.get('employeeCode') || queryParams.get('employee_id') || resolvedUserId || '';
  const employeeName = locationState.employeeName || queryParams.get('employeeName') || queryParams.get('name') || (employeeCode ? `Employee #${employeeCode}` : '');

  // Local date in YYYY-MM-DD
  const [selectedDate, setSelectedDate] = useState<string>(() => {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  });

  const [sessions, setSessions] = useState<TrackingSession[]>([]);
  const [selectedSessionId, setSelectedSessionId] = useState<number | null>(null);
  const [selectedSession, setSelectedSession] = useState<TrackingSession | null>(null);
  const [routePoints, setRoutePoints] = useState<RoutePoint[]>([]);

  const [isLoading, setIsLoading] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [showPoints, setShowPoints] = useState(true);
  const [zoomLevel, setZoomLevel] = useState(14);

  const hasEmployeeContext = Boolean(resolvedUserId || employeeCode);

  const formatTime = (iso?: string) => {
    if (!iso) return '--:--';
    try {
      const normalized = iso.includes('Z') || iso.includes('+') ? iso : `${iso}Z`;
      const dt = new Date(normalized);
      return dt.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: true });
    } catch {
      return iso;
    }
  };

  const formatDateDisplay = (dateStr: string) => {
    try {
      const [y, m, d] = dateStr.split('-');
      const dt = new Date(Number(y), Number(m) - 1, Number(d));
      return dt.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
    } catch {
      return dateStr;
    }
  };

  const formatDayOfWeek = (dateStr: string) => {
    try {
      const [y, m, d] = dateStr.split('-');
      const dt = new Date(Number(y), Number(m) - 1, Number(d));
      return dt.toLocaleDateString('en-US', { weekday: 'long' });
    } catch {
      return '';
    }
  };

  const fetchRouteData = async (overrideSessionId?: number) => {
    if (!hasEmployeeContext) return;
    setIsLoading(true);
    setHasSearched(true);

    try {
      const paramKey = resolvedUserId ? `user_id=${resolvedUserId}` : `employee_id=${employeeCode}`;
      const res = await api.getClient().get(
        `/api/tracking/sessions?${paramKey}&work_date=${selectedDate}`
      );

      if (Array.isArray(res.data) && res.data.length > 0) {
        setSessions(res.data);
        
        // Pick target session: override, previously selected, or first
        let target = res.data[0];
        if (overrideSessionId) {
          target = res.data.find((s: any) => s.id === overrideSessionId) || res.data[0];
        } else if (selectedSessionId) {
          target = res.data.find((s: any) => s.id === selectedSessionId) || res.data[0];
        }

        setSelectedSessionId(target.id);
        setSelectedSession(target);

        // Fetch route points for session
        const routeRes = await api.getClient().get(
          `/api/tracking/sessions/${target.id}/route`
        );

        if (routeRes.data) {
          const pts = routeRes.data.points || routeRes.data.route_points || [];
          setRoutePoints(pts);
          if (routeRes.data.session) {
            setSelectedSession(routeRes.data.session);
          }
        }
      } else {
        setSessions([]);
        setSelectedSessionId(null);
        setSelectedSession(null);
        setRoutePoints([]);
      }
    } catch (err) {
      console.error('Failed to load travel route', err);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    if (hasEmployeeContext) {
      fetchRouteData();
    }
  }, [resolvedUserId, employeeCode, selectedDate]);

  // Auto-refresh active/recording sessions every 12 seconds
  useEffect(() => {
    const status = (selectedSession?.status || '').toUpperCase();
    if (status === 'RECORDING' || status === 'ACTIVE') {
      const timer = setInterval(() => {
        fetchRouteData(selectedSessionId || undefined);
      }, 12000);
      return () => clearInterval(timer);
    }
  }, [selectedSession?.status, selectedSessionId, selectedDate]);

  const distanceKm = selectedSession
    ? (selectedSession.total_distance_meters / 1000).toFixed(2)
    : '0.00';

  const totalPoints = routePoints.length > 0
    ? routePoints.length
    : (selectedSession?.point_count ?? (selectedSession as any)?.points_count ?? 0);

  const displayEmployeeName = selectedSession?.employee_name || (selectedSession as any)?.user_name || employeeName;

  const status = (selectedSession?.status || 'COMPLETED').toUpperCase();
  const isCompleted = status === 'COMPLETED';
  const isActive = status === 'ACTIVE' || status === 'RECORDING';

  // Generate interactive Leaflet Map with all N route points and polyline
  const generateLeafletHtml = () => {
    const pts = JSON.stringify(routePoints.map(p => ({
      lat: p.latitude,
      lng: p.longitude,
      seq: p.sequence_number,
      accuracy: p.accuracy_meters,
      time: p.recorded_at,
      speed: p.speed_mps,
    })));

    const startLat = selectedSession?.start_latitude || 18.5204;
    const startLng = selectedSession?.start_longitude || 73.8567;

    return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    html, body, #map { height: 100%; width: 100%; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    .badge-pin {
      padding: 3px 8px;
      border-radius: 6px;
      font-weight: 700;
      font-size: 11px;
      color: white;
      text-align: center;
      white-space: nowrap;
      box-shadow: 0 2px 6px rgba(0,0,0,0.3);
      border: 1.5px solid white;
    }
    .badge-start { background: #10B981; }
    .badge-end { background: #DC2626; }
    .badge-live {
      background: #2563EB;
      box-shadow: 0 0 12px rgba(37, 99, 235, 0.8);
      animation: pulse 1.5s infinite;
    }
    @keyframes pulse {
      0% { transform: scale(1); }
      50% { transform: scale(1.08); }
      100% { transform: scale(1); }
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    const points = ${pts};
    const hasPoints = points.length > 0;
    const fallbackLat = ${startLat};
    const fallbackLng = ${startLng};

    const initialLat = hasPoints ? points[0].lat : fallbackLat;
    const initialLng = hasPoints ? points[0].lng : fallbackLng;

    const map = L.map('map', { zoomControl: false }).setView([initialLat, initialLng], 14);

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap contributors',
      maxZoom: 19
    }).addTo(map);

    if (hasPoints) {
      const latlngs = points.map(p => [p.lat, p.lng]);

      // Route Polyline
      const polyline = L.polyline(latlngs, {
        color: '#1D4ED8',
        weight: 4.5,
        opacity: 0.9,
        lineCap: 'round',
        lineJoin: 'round'
      }).addTo(map);

      // Start Marker
      const startIcon = L.divIcon({
        className: 'custom-div-icon',
        html: '<div class="badge-pin badge-start">Start</div>',
        iconSize: [46, 22],
        iconAnchor: [23, 11]
      });
      L.marker([points[0].lat, points[0].lng], { icon: startIcon })
        .addTo(map)
        .bindPopup('<b>Start Location</b><br>Point #1<br>' + points[0].lat.toFixed(5) + ', ' + points[0].lng.toFixed(5));

      // End / Live Marker
      if (points.length > 1) {
        const last = points[points.length - 1];
        const isLiveActive = ${isActive ? 'true' : 'false'};
        const endIcon = L.divIcon({
          className: 'custom-div-icon',
          html: isLiveActive 
            ? '<div class="badge-pin badge-live">● Live Location</div>'
            : '<div class="badge-pin badge-end">End</div>',
          iconSize: [isLiveActive ? 100 : 46, 22],
          iconAnchor: [isLiveActive ? 50 : 23, 11]
        });
        L.marker([last.lat, last.lng], { icon: endIcon })
          .addTo(map)
          .bindPopup('<b>' + (isLiveActive ? 'Live Location' : 'End Location') + '</b><br>Point #' + last.seq + '<br>' + last.lat.toFixed(5) + ', ' + last.lng.toFixed(5));
      }

      // Intermediate Checkpoint Dots
      ${showPoints ? `
      if (points.length > 2) {
        points.slice(1, -1).forEach(p => {
          L.circleMarker([p.lat, p.lng], {
            radius: 4,
            fillColor: '#3B82F6',
            color: '#FFFFFF',
            weight: 1.5,
            fillOpacity: 0.95
          }).addTo(map).bindPopup('Point #' + p.seq + '<br>' + p.lat.toFixed(5) + ', ' + p.lng.toFixed(5));
        });
      }
      ` : ''}

      map.fitBounds(polyline.getBounds(), { padding: [50, 50], maxZoom: 16 });
    }

    // Expose control functions to parent window
    window.leafletMap = map;
  </script>
</body>
</html>`;
  };

  return (
    <div className="p-6 space-y-6 max-w-7xl mx-auto">
      {/* A. Header */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <button
            onClick={() => navigate(-1)}
            className="p-2 text-slate-500 hover:text-slate-800 hover:bg-slate-100 rounded-lg transition"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <div>
            <h1 className="text-xl font-bold text-slate-900 tracking-tight">
              Employee Travel Map
            </h1>
            <p className="text-xs text-slate-500 mt-0.5">
              Review and audit GPS path breadcrumbs recorded during shift duty.
            </p>
          </div>
        </div>
      </div>

      {!hasEmployeeContext ? (
        <div className="bg-white p-12 rounded-2xl border border-[#DCE4F0] text-center max-w-md mx-auto my-12 shadow-sm">
          <div className="w-14 h-14 bg-blue-50 text-[#203F92] rounded-full flex items-center justify-center mx-auto mb-4">
            <User className="w-7 h-7" />
          </div>
          <h2 className="text-lg font-bold text-slate-900 mb-1">
            No Employee Selected
          </h2>
          <p className="text-xs text-slate-500 mb-6">
            Please open this page from Employee Directory or Attendance logs with an employee selected.
          </p>
          <button
            onClick={() => navigate('/employees')}
            className="px-5 py-2.5 bg-[#203F92] text-white text-sm font-semibold rounded-lg hover:bg-[#1a3375] transition"
          >
            Go to Employee List
          </button>
        </div>
      ) : (
        <>
          {/* B. Travel Map Configuration */}
          <div className="bg-white p-6 rounded-2xl border border-[#DCE4F0] shadow-sm">
            <h2 className="text-base font-bold text-slate-900 mb-4">
              Travel Map Configuration
            </h2>
            <div className="flex flex-col md:flex-row items-stretch md:items-center gap-4">
              {/* Select Date */}
              <div className="flex-1 relative">
                <label className="block text-xs font-medium text-slate-500 mb-1">
                  Select Date *
                </label>
                <div className="flex items-center gap-3 px-4 py-2.5 bg-white border border-slate-300 rounded-xl focus-within:ring-2 focus-within:ring-[#203F92] focus-within:border-transparent">
                  <Calendar className="w-4 h-4 text-slate-500" />
                  <input
                    type="date"
                    value={selectedDate}
                    onChange={(e) => setSelectedDate(e.target.value)}
                    className="w-full bg-transparent text-sm font-semibold text-slate-900 focus:outline-none cursor-pointer"
                  />
                </div>
              </div>

              {/* Session Selector (Prevents Start Time Mismatch When Multiple Sessions Exist) */}
              {sessions.length > 1 && (
                <div className="flex-1 relative">
                  <label className="block text-xs font-medium text-slate-500 mb-1">
                    Duty Session ({sessions.length} Available)
                  </label>
                  <select
                    value={selectedSessionId || ''}
                    onChange={(e) => {
                      const sid = Number(e.target.value);
                      setSelectedSessionId(sid);
                      fetchRouteData(sid);
                    }}
                    className="w-full px-4 py-2.5 bg-white border border-slate-300 rounded-xl text-sm font-semibold text-slate-900 focus:outline-none focus:ring-2 focus:ring-[#203F92]"
                  >
                    {sessions.map((s, idx) => (
                      <option key={s.id} value={s.id}>
                        Session #{sessions.length - idx}: {formatTime(s.start_time)} ({s.status}) — {s.point_count || 0} pts
                      </option>
                    ))}
                  </select>
                </div>
              )}

              {/* View Travel Route Button */}
              <div className="flex items-end">
                <button
                  onClick={() => fetchRouteData()}
                  disabled={isLoading}
                  className="w-full md:w-auto flex items-center justify-center gap-2 px-6 py-3 bg-[#203F92] hover:bg-[#1a3375] text-white text-sm font-semibold rounded-xl shadow-sm transition disabled:opacity-50"
                >
                  <BookOpen className="w-4 h-4" />
                  {isLoading ? 'Loading Route...' : 'View Travel Route'}
                </button>
              </div>
            </div>
          </div>

          {/* C. Travel Summary */}
          <div className="bg-white p-6 rounded-2xl border border-[#DCE4F0] shadow-sm">
            <div className="flex items-center gap-2 mb-4">
              <BarChart2 className="w-5 h-5 text-[#203F92]" />
              <h2 className="text-base font-bold text-slate-900">
                Travel Summary
              </h2>
            </div>
            <div className="flex flex-wrap gap-3">
              {/* Employee */}
              <div className="flex items-center gap-3 px-4 py-3 bg-[#F8FAFC] border border-[#E2E8F0] rounded-xl min-w-[150px]">
                <div className="w-9 h-9 rounded-full bg-[#EFF6FF] text-[#2563EB] flex items-center justify-center">
                  <User className="w-5 h-5" />
                </div>
                <div>
                  <div className="text-[11px] font-medium text-slate-500">Employee</div>
                  <div className="text-sm font-bold text-slate-900">{displayEmployeeName}</div>
                  <div className="text-[11px] text-slate-400">ID: {employeeCode}</div>
                </div>
              </div>

              {/* Date */}
              <div className="flex items-center gap-3 px-4 py-3 bg-[#F8FAFC] border border-[#E2E8F0] rounded-xl min-w-[140px]">
                <div className="w-9 h-9 rounded-full bg-[#EFF6FF] text-[#2563EB] flex items-center justify-center">
                  <Calendar className="w-5 h-5" />
                </div>
                <div>
                  <div className="text-[11px] font-medium text-slate-500">Date</div>
                  <div className="text-sm font-bold text-slate-900">{formatDateDisplay(selectedDate)}</div>
                  <div className="text-[11px] text-slate-400">{formatDayOfWeek(selectedDate)}</div>
                </div>
              </div>

              {/* Tracking Status */}
              <div className="flex items-center gap-3 px-4 py-3 bg-[#F8FAFC] border border-[#E2E8F0] rounded-xl min-w-[150px]">
                <div className={`w-9 h-9 rounded-full flex items-center justify-center ${isCompleted ? 'bg-[#ECFDF5]' : 'bg-[#EFF6FF]'}`}>
                  <span className={`w-3 h-3 rounded-full ${isCompleted ? 'bg-[#10B981]' : 'bg-[#3B82F6]'}`} />
                </div>
                <div>
                  <div className="text-[11px] font-medium text-slate-500">Tracking Status</div>
                  <span className={`inline-block px-2.5 py-0.5 mt-1 rounded text-xs font-bold ${
                    isCompleted ? 'bg-[#DEF7EC] text-[#047857]' : isActive ? 'bg-[#DBEAFE] text-[#1E40AF]' : 'bg-slate-100 text-slate-600'
                  }`}>
                    {isCompleted ? 'Completed' : isActive ? 'Active' : 'Pending'}
                  </span>
                </div>
              </div>

              {/* Start Time */}
              <div className="flex items-center gap-3 px-4 py-3 bg-[#F8FAFC] border border-[#E2E8F0] rounded-xl min-w-[130px]">
                <div className="w-9 h-9 rounded-full bg-[#EFF6FF] text-[#2563EB] flex items-center justify-center">
                  <Clock className="w-5 h-5" />
                </div>
                <div>
                  <div className="text-[11px] font-medium text-slate-500">Start Time</div>
                  <div className="text-sm font-bold text-slate-900">{formatTime(selectedSession?.start_time)}</div>
                </div>
              </div>

              {/* End Time */}
              <div className="flex items-center gap-3 px-4 py-3 bg-[#F8FAFC] border border-[#E2E8F0] rounded-xl min-w-[130px]">
                <div className="w-9 h-9 rounded-full bg-[#FFF7ED] text-[#F97316] flex items-center justify-center">
                  <Clock className="w-5 h-5" />
                </div>
                <div>
                  <div className="text-[11px] font-medium text-slate-500">End Time</div>
                  <div className="text-sm font-bold text-slate-900">{formatTime(selectedSession?.end_time)}</div>
                </div>
              </div>

              {/* Travel Distance */}
              <div className="flex items-center gap-3 px-4 py-3 bg-[#F8FAFC] border border-[#E2E8F0] rounded-xl min-w-[140px]">
                <div className="w-9 h-9 rounded-full bg-[#FAF5FF] text-[#9333EA] flex items-center justify-center">
                  <Route className="w-5 h-5" />
                </div>
                <div>
                  <div className="text-[11px] font-medium text-slate-500">Travel Distance</div>
                  <div className="text-sm font-bold text-slate-900">{distanceKm} km</div>
                </div>
              </div>

              {/* Total Points */}
              <div className="flex items-center gap-3 px-4 py-3 bg-[#F8FAFC] border border-[#E2E8F0] rounded-xl min-w-[130px]">
                <div className="w-9 h-9 rounded-full bg-[#FDF2F8] text-[#DB2777] flex items-center justify-center">
                  <MapPin className="w-5 h-5" />
                </div>
                <div>
                  <div className="text-[11px] font-medium text-slate-500">Total Points</div>
                  <div className="text-sm font-bold text-slate-900">{totalPoints}</div>
                </div>
              </div>
            </div>
          </div>

          {/* D. Recorded Travel Route */}
          <div className="bg-white p-6 rounded-2xl border border-[#DCE4F0] shadow-sm">
            <div className="flex flex-wrap items-center justify-between gap-3 mb-4">
              <div className="flex items-center gap-2">
                <Route className="w-5 h-5 text-[#203F92]" />
                <h2 className="text-base font-bold text-slate-900">
                  Recorded Travel Route
                </h2>
                {isActive && (
                  <span className="flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200">
                    <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
                    Live Route Active
                  </span>
                )}
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setShowPoints(!showPoints)}
                  className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg border transition ${
                    showPoints
                      ? 'border-[#203F92] text-[#203F92] bg-blue-50/50'
                      : 'border-slate-300 text-slate-700 bg-white hover:bg-slate-50'
                  }`}
                >
                  {showPoints ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                  {showPoints ? 'Hide Points' : 'Show Points'}
                </button>
                <button
                  onClick={() => fetchRouteData()}
                  className="p-1.5 text-slate-700 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 transition"
                  title="Refresh Route"
                >
                  <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? 'animate-spin' : ''}`} />
                </button>
              </div>
            </div>

            {/* Map Area */}
            <div className="relative h-[520px] rounded-xl border border-slate-200 overflow-hidden bg-slate-100">
              <iframe
                title="Leaflet Live Route"
                className="w-full h-full border-none"
                srcDoc={generateLeafletHtml()}
              />

              {/* Start & End Marker Overlay Simulation */}
              {routePoints.length > 0 && (
                <div className="absolute top-4 left-4 bg-white/95 backdrop-blur-sm p-3 rounded-xl border border-slate-200 shadow-lg text-xs space-y-2 pointer-events-none">
                  <div className="flex items-center gap-2">
                    <span className="w-2.5 h-2.5 rounded-full bg-emerald-500" />
                    <span className="font-semibold text-slate-700">Start:</span>
                    <span className="text-slate-500">{routePoints[0].latitude.toFixed(4)}, {routePoints[0].longitude.toFixed(4)}</span>
                  </div>
                  {routePoints.length > 1 && (
                    <div className="flex items-center gap-2">
                      <span className={`w-2.5 h-2.5 rounded-full ${isActive ? 'bg-blue-500 animate-pulse' : 'bg-red-500'}`} />
                      <span className="font-semibold text-slate-700">{isActive ? 'Live Position:' : 'End:'}</span>
                      <span className="text-slate-500">
                        {routePoints[routePoints.length - 1].latitude.toFixed(4)}, {routePoints[routePoints.length - 1].longitude.toFixed(4)}
                      </span>
                    </div>
                  )}
                </div>
              )}

              {/* Bottom Right Layer Pill */}
              <div className="absolute bottom-4 right-4 flex items-center gap-1.5 px-2.5 py-1.5 bg-white/95 rounded-lg border border-slate-300 shadow-md text-xs font-semibold text-slate-700">
                <Layers className="w-3.5 h-3.5" />
                <span>OpenStreetMap & Leaflet</span>
              </div>

              {/* Loading State */}
              {isLoading && (
                <div className="absolute inset-0 bg-white/70 backdrop-blur-xs flex items-center justify-center">
                  <div className="flex items-center gap-2 text-sm font-semibold text-[#203F92]">
                    <RefreshCw className="w-5 h-5 animate-spin" />
                    Loading recorded route...
                  </div>
                </div>
              )}

              {/* Empty / Honest State */}
              {!isLoading && hasSearched && routePoints.length === 0 && (
                <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
                  <div className="bg-white/95 backdrop-blur-sm p-6 rounded-2xl border border-slate-200 shadow-xl text-center max-w-sm pointer-events-auto">
                    <MapPin className="w-8 h-8 text-blue-500 mx-auto mb-2 animate-bounce" />
                    <h3 className="text-sm font-bold text-slate-800 mb-1">
                      {isActive ? 'Session Active — No GPS Points Yet' : 'No Recorded Route Found'}
                    </h3>
                    <p className="text-xs text-slate-500">
                      {isActive
                        ? `Session started at ${formatTime(selectedSession?.start_time)}. GPS coordinates will appear as the employee travels.`
                        : `No GPS breadcrumbs logged for ${formatDateDisplay(selectedDate)}.`}
                    </p>
                  </div>
                </div>
              )}
            </div>
          </div>
        </>
      )}
    </div>
  );
};
