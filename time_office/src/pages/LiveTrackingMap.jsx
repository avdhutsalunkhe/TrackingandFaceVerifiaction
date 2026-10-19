import React, { useState, useEffect, useRef, useMemo } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import {
  Navigation,
  Compass,
  MapPin,
  RefreshCw,
  Search,
  Crosshair,
  Wifi,
  WifiOff,
  Radio,
  Clock,
  ShieldCheck,
  Building,
  User,
  AlertCircle,
  Copy,
  Check,
  Layers,
  ChevronRight,
  Route,
  Zap
} from 'lucide-react';
import axios from 'axios';
import { BACKEND_URL, API_BASE } from '../api/client';

// Fix standard Leaflet icon paths in Vite
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
});

// Custom SVG Pulsing Marker for Live Employee Tracking
const createLiveMarkerIcon = (heading = 0, isFollowed = false) => {
  const rotation = heading || 0;
  return L.divIcon({
    className: 'custom-live-marker',
    html: `
      <div style="position: relative; width: 44px; height: 44px; display: flex; align-items: center; justify-content: center;">
        <div style="
          position: absolute;
          width: 36px;
          height: 36px;
          border-radius: 50%;
          background: rgba(37, 99, 235, 0.25);
          animation: ping 1.5s cubic-bezier(0, 0, 0.2, 1) infinite;
        "></div>
        <div style="
          position: relative;
          width: 28px;
          height: 28px;
          border-radius: 50%;
          background: ${isFollowed ? '#2563EB' : '#1D4ED8'};
          border: 3px solid #ffffff;
          box-shadow: 0 4px 10px rgba(0,0,0,0.3);
          display: flex;
          align-items: center;
          justify-content: center;
          color: white;
          transform: rotate(${rotation}deg);
          transition: transform 0.3s ease;
        ">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <polygon points="12 2 19 21 12 17 5 21 12 2"></polygon>
          </svg>
        </div>
      </div>
    `,
    iconSize: [44, 44],
    iconAnchor: [22, 22],
    popupAnchor: [0, -20],
  });
};

export default function LiveTrackingMap() {
  const mapContainerRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersRef = useRef({});
  const polylineRef = useRef(null);
  const wsRef = useRef(null);

  const [employees, setEmployees] = useState([]);
  const [selectedUserId, setSelectedUserId] = useState(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [followLive, setFollowLive] = useState(true);
  const [connectionStatus, setConnectionStatus] = useState('connecting'); // 'websocket' | 'polling' | 'disconnected'
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [routeHistory, setRouteHistory] = useState([]);
  const [copiedCoord, setCopiedCoord] = useState(false);
  const [inspectingAddress, setInspectingAddress] = useState(false);

  const getAuthToken = () => {
    return localStorage.getItem('report_auth_token') || localStorage.getItem('hrreport_auth_token') || '';
  };

  // Initialize Leaflet Map
  useEffect(() => {
    if (!mapContainerRef.current || mapInstanceRef.current) return;

    // Default center: Maharashtra (Kolhapur/Sangli region)
    const initialLat = 16.8524;
    const initialLng = 74.5815;

    const map = L.map(mapContainerRef.current, {
      center: [initialLat, initialLng],
      zoom: 13,
      zoomControl: false,
    });

    // High quality OpenStreetMap standard tiles
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank">OpenStreetMap</a> contributors',
      referrerPolicy: 'no-referrer-when-downgrade',
    }).addTo(map);

    // Zoom control at bottom-right
    L.control.zoom({ position: 'bottomright' }).addTo(map);

    // Dynamic Route Polyline
    const line = L.polyline([], {
      color: '#2563EB',
      weight: 5,
      opacity: 0.85,
      lineCap: 'round',
      lineJoin: 'round',
      dashArray: null,
    }).addTo(map);

    mapInstanceRef.current = map;
    polylineRef.current = line;

    return () => {
      map.remove();
      mapInstanceRef.current = null;
    };
  }, []);

  // Fetch initial live employees and fallback polling
  const fetchLiveLocations = async (manual = false) => {
    if (manual) setIsRefreshing(true);
    const token = getAuthToken();
    try {
      const res = await axios.get(`${API_BASE}/tracking/live`, {
        headers: token ? { Authorization: `Bearer ${token}` } : {},
        timeout: 6000,
      });

      if (Array.isArray(res.data)) {
        setEmployees(res.data);
        if (connectionStatus === 'disconnected') {
          setConnectionStatus('polling');
        }
      }
    } catch (err) {
      console.warn('[LiveTrackingMap] Failed to fetch live locations:', err.message);
      if (connectionStatus !== 'websocket') {
        setConnectionStatus('disconnected');
      }
    } finally {
      if (manual) setIsRefreshing(false);
    }
  };

  // WebSocket connection management with automatic reconnection & fallback
  useEffect(() => {
    let isCancelled = false;
    let reconnectTimeout = null;

    const connectWebSocket = () => {
      if (isCancelled) return;

      const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const hostPart = BACKEND_URL.replace(/^https?:\/\//, '');
      const wsUrl = `${wsProtocol}//${hostPart}/api/tracking/ws/live`;

      console.log('[LiveTrackingMap] Connecting to WebSocket:', wsUrl);
      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;

      ws.onopen = () => {
        if (isCancelled) return;
        console.log('[LiveTrackingMap] WebSocket connected.');
        setConnectionStatus('websocket');
      };

      ws.onmessage = (event) => {
        try {
          const payload = JSON.parse(event.data);
          if (payload.type === 'LIVE_PING' && payload.data) {
            handleLivePing(payload.data);
          }
        } catch (e) {
          console.error('[LiveTrackingMap] WebSocket message parse error:', e);
        }
      };

      ws.onerror = (e) => {
        console.warn('[LiveTrackingMap] WebSocket error, falling back to polling.');
        setConnectionStatus('polling');
      };

      ws.onclose = () => {
        if (isCancelled) return;
        console.log('[LiveTrackingMap] WebSocket closed, scheduling retry in 5s.');
        setConnectionStatus('polling');
        reconnectTimeout = setTimeout(connectWebSocket, 5000);
      };
    };

    connectWebSocket();
    fetchLiveLocations();

    // 5-second polling fallback interval (active if ws is disconnected)
    const pollInterval = setInterval(() => {
      if (connectionStatus !== 'websocket') {
        fetchLiveLocations();
      }
    }, 5000);

    return () => {
      isCancelled = true;
      if (reconnectTimeout) clearTimeout(reconnectTimeout);
      clearInterval(pollInterval);
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, []);

  // Handle incoming live GPS ping event
  const handleLivePing = (pingData) => {
    setEmployees((prev) => {
      const idx = prev.findIndex((e) => e.user_id === pingData.user_id);
      if (idx >= 0) {
        const updated = [...prev];
        updated[idx] = { ...updated[idx], ...pingData, updated_at: new Date().toISOString() };
        return updated;
      } else {
        return [{ ...pingData, updated_at: new Date().toISOString() }, ...prev];
      }
    });

    // If this ping is for the currently followed/selected employee, append to polyline
    if (selectedUserId === null || selectedUserId === pingData.user_id) {
      const newCoord = [pingData.latitude, pingData.longitude];
      setRouteHistory((prev) => [...prev, newCoord]);

      if (polylineRef.current) {
        polylineRef.current.addLatLng(newCoord);
      }

      if (followLive && mapInstanceRef.current) {
        mapInstanceRef.current.panTo(newCoord, { animate: true, duration: 0.8 });
      }
    }
  };

  // Sync Leaflet markers when employees or selection changes
  useEffect(() => {
    const map = mapInstanceRef.current;
    if (!map) return;

    employees.forEach((emp) => {
      const { user_id, latitude, longitude, bearing_degrees, employee_name, employee_id, address, speed_mps, accuracy_meters } = emp;
      if (!latitude || !longitude) return;

      const pos = [latitude, longitude];
      const isSelected = selectedUserId === user_id;

      let marker = markersRef.current[user_id];
      if (!marker) {
        marker = L.marker(pos, {
          icon: createLiveMarkerIcon(bearing_degrees, isSelected),
        }).addTo(map);

        marker.on('click', () => {
          setSelectedUserId(user_id);
        });

        markersRef.current[user_id] = marker;
      } else {
        marker.setLatLng(pos);
        marker.setIcon(createLiveMarkerIcon(bearing_degrees, isSelected));
      }

      // Update rich popup content
      const speedKmh = speed_mps ? (speed_mps * 3.6).toFixed(1) : '0.0';
      const addrVillage = address?.village || '—';
      const addrLocality = address?.locality || '—';
      const addrRoad = address?.road || '—';
      const addrDistrict = address?.district || '—';
      const addrState = address?.state || 'Maharashtra';
      const fullDisplay = address?.display_name || 'Resolving location details...';

      const popupContent = `
        <div style="font-family: system-ui, sans-serif; font-size: 13px; color: #0f172a; min-width: 260px; max-width: 300px;">
          <div style="display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px; margin-bottom: 8px;">
            <div>
              <div style="font-weight: 700; font-size: 14px; color: #1e293b;">${employee_name}</div>
              <div style="font-size: 11px; color: #64748b; font-weight: 500;">ID: ${employee_id}</div>
            </div>
            <span style="background: #dcfce7; color: #15803d; font-size: 10px; font-weight: 700; padding: 2px 6px; border-radius: 4px;">LIVE</span>
          </div>

          <div style="display: flex; gap: 8px; margin-bottom: 8px; font-size: 11px;">
            <div style="flex: 1; background: #f8fafc; border: 1px solid #e2e8f0; padding: 4px 6px; border-radius: 6px;">
              <span style="color: #64748b;">Speed:</span> <b>${speedKmh} km/h</b>
            </div>
            <div style="flex: 1; background: #f8fafc; border: 1px solid #e2e8f0; padding: 4px 6px; border-radius: 6px;">
              <span style="color: #64748b;">Acc:</span> <b>±${accuracy_meters?.toFixed(0) || 10}m</b>
            </div>
          </div>

          <div style="background: #f1f5f9; border-radius: 6px; padding: 8px; font-size: 11px; line-height: 1.4; border-left: 3px solid #2563eb;">
            <div style="color: #334155; font-weight: 600; margin-bottom: 4px;">📍 Resolved Address (OSM):</div>
            <div><b>Village:</b> ${addrVillage}</div>
            <div><b>Locality:</b> ${addrLocality}</div>
            <div><b>Road:</b> ${addrRoad}</div>
            <div><b>District:</b> ${addrDistrict}</div>
            <div style="margin-top: 4px; color: #64748b; font-size: 10px;">${fullDisplay}</div>
          </div>

          <div style="margin-top: 8px; font-size: 10px; color: #94a3b8; text-align: right;">
            ${latitude.toFixed(6)}, ${longitude.toFixed(6)}
          </div>
        </div>
      `;

      marker.bindPopup(popupContent);
    });

    // Clean up markers for removed employees
    const activeIds = new Set(employees.map((e) => e.user_id));
    Object.keys(markersRef.current).forEach((id) => {
      if (!activeIds.has(Number(id))) {
        markersRef.current[id].remove();
        delete markersRef.current[id];
      }
    });

    // If an employee is selected, pan to them
    if (selectedUserId) {
      const active = employees.find((e) => e.user_id === selectedUserId);
      if (active && active.latitude && active.longitude && followLive) {
        map.panTo([active.latitude, active.longitude], { animate: true });
      }
    }
  }, [employees, selectedUserId, followLive]);

  // When selected employee changes, load their session route points if available
  useEffect(() => {
    if (!selectedUserId) return;
    const emp = employees.find((e) => e.user_id === selectedUserId);
    if (!emp) return;

    if (emp.latitude && emp.longitude) {
      const pos = [emp.latitude, emp.longitude];
      if (mapInstanceRef.current) {
        mapInstanceRef.current.setView(pos, 16);
      }
      setRouteHistory([pos]);
      if (polylineRef.current) {
        polylineRef.current.setLatLngs([pos]);
      }
    }
  }, [selectedUserId]);

  const selectedEmployee = useMemo(() => {
    if (selectedUserId) {
      return employees.find((e) => e.user_id === selectedUserId) || employees[0];
    }
    return employees[0] || null;
  }, [employees, selectedUserId]);

  const filteredEmployees = useMemo(() => {
    if (!searchQuery.trim()) return employees;
    const q = searchQuery.toLowerCase();
    return employees.filter(
      (e) =>
        (e.employee_name && e.employee_name.toLowerCase().includes(q)) ||
        (e.employee_id && e.employee_id.toLowerCase().includes(q)) ||
        (e.department && e.department.toLowerCase().includes(q))
    );
  }, [employees, searchQuery]);

  const handleCopyCoords = (lat, lon) => {
    const text = `${lat.toFixed(6)}, ${lon.toFixed(6)}`;
    navigator.clipboard.writeText(text);
    setCopiedCoord(true);
    setTimeout(() => setCopiedCoord(false), 2000);
  };

  const handleForceInspectAddress = async (lat, lon) => {
    if (!lat || !lon) return;
    setInspectingAddress(true);
    const token = getAuthToken();
    try {
      const res = await axios.get(`${API_BASE}/tracking/reverse-geocode?lat=${lat}&lon=${lon}&force=true`, {
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      });
      if (res.data && res.data.address) {
        // Update local employee address state
        setEmployees((prev) =>
          prev.map((emp) =>
            emp.user_id === selectedEmployee?.user_id
              ? { ...emp, address: res.data.address }
              : emp
          )
        );
      }
    } catch (e) {
      console.warn('On-demand geocoding error:', e);
    } finally {
      setInspectingAddress(false);
    }
  };

  const handleFitBounds = () => {
    if (!mapInstanceRef.current || employees.length === 0) return;
    const validCoords = employees
      .filter((e) => e.latitude && e.longitude)
      .map((e) => [e.latitude, e.longitude]);

    if (validCoords.length === 1) {
      mapInstanceRef.current.setView(validCoords[0], 16);
    } else if (validCoords.length > 1) {
      const bounds = L.latLngBounds(validCoords);
      mapInstanceRef.current.fitBounds(bounds, { padding: [50, 50] });
    }
  };

  return (
    <div className="flex flex-col h-[calc(100vh-4rem)] bg-slate-100 overflow-hidden font-sans">
      {/* Top Bar Header */}
      <div className="bg-white border-b border-slate-200 px-6 py-3.5 flex flex-wrap items-center justify-between gap-4 shrink-0 shadow-xs">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-blue-600 flex items-center justify-center text-white shadow-md shadow-blue-500/20">
            <Radio size={20} className="animate-pulse" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-lg font-bold text-slate-900 tracking-tight">Live GPS Map & Trail</h1>
              <span className="px-2 py-0.5 rounded-full text-[11px] font-bold bg-blue-100 text-blue-700">
                OpenStreetMap
              </span>
            </div>
            <p className="text-xs text-slate-500">
              Real-time continuous GPS tracking with smart reverse-geocoding (Maharashtra / Sangli / Kolhapur)
            </p>
          </div>
        </div>

        {/* Live Controls & Telemetry Badges */}
        <div className="flex items-center gap-3">
          {/* Connection Status Indicator */}
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg border text-xs font-semibold bg-white border-slate-200">
            {connectionStatus === 'websocket' ? (
              <>
                <span className="w-2.5 h-2.5 rounded-full bg-emerald-500 shadow-sm shadow-emerald-500/50 animate-pulse" />
                <span className="text-emerald-700 flex items-center gap-1">
                  <Wifi size={13} /> WebSocket Live
                </span>
              </>
            ) : connectionStatus === 'polling' ? (
              <>
                <span className="w-2.5 h-2.5 rounded-full bg-amber-500 animate-pulse" />
                <span className="text-amber-700 flex items-center gap-1">
                  <RefreshCw size={13} className="animate-spin" /> REST Polling (5s)
                </span>
              </>
            ) : (
              <>
                <span className="w-2.5 h-2.5 rounded-full bg-rose-500" />
                <span className="text-rose-700 flex items-center gap-1">
                  <WifiOff size={13} /> Offline
                </span>
              </>
            )}
          </div>

          {/* Follow Live Toggle */}
          <button
            onClick={() => setFollowLive(!followLive)}
            className={`flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all shadow-xs cursor-pointer ${
              followLive
                ? 'bg-blue-600 text-white shadow-blue-500/20 hover:bg-blue-700'
                : 'bg-white border border-slate-300 text-slate-700 hover:bg-slate-50'
            }`}
          >
            <Crosshair size={14} className={followLive ? 'animate-spin' : ''} />
            {followLive ? 'Following Live' : 'Follow Off'}
          </button>

          {/* Fit Bounds */}
          <button
            onClick={handleFitBounds}
            title="Fit map to all active staff"
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-white border border-slate-300 text-slate-700 hover:bg-slate-50 transition-colors shadow-xs cursor-pointer"
          >
            <Layers size={14} />
            Fit All
          </button>

          {/* Manual Refresh */}
          <button
            onClick={() => fetchLiveLocations(true)}
            disabled={isRefreshing}
            className="p-2 rounded-lg bg-white border border-slate-300 text-slate-700 hover:bg-slate-50 disabled:opacity-50 transition-colors shadow-xs cursor-pointer"
            title="Refresh positions"
          >
            <RefreshCw size={14} className={isRefreshing ? 'animate-spin text-blue-600' : ''} />
          </button>
        </div>
      </div>

      {/* Main Container: Sidebar + Leaflet Map */}
      <div className="flex-1 flex overflow-hidden relative">
        {/* Left Side: Employees List */}
        <div className="w-80 md:w-96 bg-white border-r border-slate-200 flex flex-col shrink-0 z-10 shadow-sm">
          {/* Search Header */}
          <div className="p-3 border-b border-slate-200 bg-slate-50/70">
            <div className="relative">
              <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
              <input
                type="text"
                placeholder="Search employee by name, ID..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-3 py-1.5 text-xs bg-white border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 text-slate-800 placeholder-slate-400"
              />
            </div>
            <div className="flex items-center justify-between mt-2 px-1 text-[11px] text-slate-500 font-medium">
              <span>{filteredEmployees.length} Field Staff Tracking</span>
              <span className="text-emerald-600 font-semibold">
                {employees.filter((e) => e.session_status === 'RECORDING').length} Recording Duty
              </span>
            </div>
          </div>

          {/* Employee Cards List */}
          <div className="flex-1 overflow-y-auto divide-y divide-slate-100 p-2 space-y-1">
            {filteredEmployees.length === 0 ? (
              <div className="p-8 text-center text-slate-400 text-xs">
                <MapPin size={32} className="mx-auto mb-2 opacity-40 text-slate-400" />
                No active employee locations found. Ensure employees have punched in on mobile app.
              </div>
            ) : (
              filteredEmployees.map((emp) => {
                const isSelected = selectedUserId === emp.user_id;
                const isRecording = emp.session_status === 'RECORDING';
                const speedKmh = emp.speed_mps ? (emp.speed_mps * 3.6).toFixed(1) : '0.0';

                return (
                  <div
                    key={emp.user_id}
                    onClick={() => setSelectedUserId(emp.user_id)}
                    className={`p-3 rounded-xl cursor-pointer transition-all ${
                      isSelected
                        ? 'bg-blue-50/90 border-2 border-blue-600 shadow-xs'
                        : 'hover:bg-slate-50 border border-transparent'
                    }`}
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div className="flex items-center gap-2.5">
                        <div
                          className={`w-9 h-9 rounded-full flex items-center justify-center font-bold text-xs shrink-0 ${
                            isSelected
                              ? 'bg-blue-600 text-white'
                              : 'bg-slate-100 text-slate-700 border border-slate-200'
                          }`}
                        >
                          {emp.employee_name ? emp.employee_name.charAt(0).toUpperCase() : 'E'}
                        </div>
                        <div className="truncate">
                          <h4 className="text-xs font-bold text-slate-900 truncate">{emp.employee_name}</h4>
                          <span className="text-[11px] text-slate-500 font-mono">ID: {emp.employee_id}</span>
                        </div>
                      </div>

                      <span
                        className={`px-2 py-0.5 rounded-full text-[10px] font-bold uppercase shrink-0 ${
                          isRecording
                            ? 'bg-emerald-100 text-emerald-800'
                            : 'bg-slate-100 text-slate-600'
                        }`}
                      >
                        {isRecording ? 'On Duty' : 'Standby'}
                      </span>
                    </div>

                    {/* Telemetry Chips */}
                    <div className="grid grid-cols-2 gap-1.5 mt-2.5 text-[11px]">
                      <div className="bg-white/80 border border-slate-200 px-2 py-1 rounded-md flex items-center justify-between text-slate-600">
                        <span className="text-[10px] text-slate-400">Speed:</span>
                        <span className="font-semibold text-slate-800">{speedKmh} km/h</span>
                      </div>
                      <div className="bg-white/80 border border-slate-200 px-2 py-1 rounded-md flex items-center justify-between text-slate-600">
                        <span className="text-[10px] text-slate-400">Accuracy:</span>
                        <span className="font-semibold text-slate-800">±{emp.accuracy_meters?.toFixed(0) || 10}m</span>
                      </div>
                    </div>

                    {/* Resolved Location Snippet */}
                    <div className="mt-2 text-[11px] text-slate-600 flex items-start gap-1.5 bg-slate-50 p-2 rounded-lg border border-slate-100">
                      <MapPin size={13} className="text-blue-600 shrink-0 mt-0.5" />
                      <div className="truncate">
                        <div className="font-medium text-slate-800 truncate">
                          {emp.address?.village || emp.address?.locality || 'Resolving location...'}
                        </div>
                        <div className="text-[10px] text-slate-400 truncate">
                          {emp.address?.district ? `${emp.address.district}, Maharashtra` : `${emp.latitude.toFixed(4)}, ${emp.longitude.toFixed(4)}`}
                        </div>
                      </div>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>

        {/* Map Center & Bottom Overlay */}
        <div className="flex-1 flex flex-col relative">
          {/* Leaflet Map Canvas */}
          <div ref={mapContainerRef} className="w-full h-full z-0" />

          {/* Bottom Floating Telemetry & Reverse-Geocoding Inspector Drawer */}
          {selectedEmployee && (
            <div className="absolute bottom-4 left-4 right-4 z-20 pointer-events-none">
              <div className="max-w-4xl mx-auto bg-white/95 backdrop-blur-md rounded-2xl shadow-xl border border-slate-200/80 p-4 pointer-events-auto transition-all">
                <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4 border-b border-slate-100 pb-3">
                  <div className="flex items-center gap-3">
                    <div className="w-11 h-11 rounded-xl bg-gradient-to-br from-blue-600 to-indigo-700 flex items-center justify-center text-white font-bold shadow-md shadow-blue-500/20">
                      <User size={20} />
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <h3 className="text-sm font-bold text-slate-900">{selectedEmployee.employee_name}</h3>
                        <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-blue-100 text-blue-700">
                          {selectedEmployee.department || 'Field Staff'}
                        </span>
                      </div>
                      <div className="flex items-center gap-3 text-xs text-slate-500 mt-0.5">
                        <span>ID: <code className="font-mono text-slate-700">{selectedEmployee.employee_id}</code></span>
                        <span>•</span>
                        <span className="flex items-center gap-1 text-slate-600">
                          <Clock size={12} />
                          {selectedEmployee.recorded_at
                            ? new Date(selectedEmployee.recorded_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
                            : 'Just now'}
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Exact Raw Coordinates with Copy */}
                  <div className="flex items-center gap-2 bg-slate-50 border border-slate-200 px-3 py-1.5 rounded-xl">
                    <div className="text-right">
                      <div className="text-[10px] uppercase font-bold text-slate-400">Raw GNSS Coordinates</div>
                      <div className="text-xs font-mono font-bold text-slate-800">
                        {selectedEmployee.latitude.toFixed(6)}, {selectedEmployee.longitude.toFixed(6)}
                      </div>
                    </div>
                    <button
                      onClick={() => handleCopyCoords(selectedEmployee.latitude, selectedEmployee.longitude)}
                      title="Copy exact coordinates"
                      className="p-1.5 rounded-lg hover:bg-slate-200 text-slate-600 transition-colors cursor-pointer"
                    >
                      {copiedCoord ? <Check size={14} className="text-emerald-600" /> : <Copy size={14} />}
                    </button>
                  </div>
                </div>

                {/* Resolved Reverse-Geocoded Address Grid */}
                <div className="mt-3">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-[11px] font-bold uppercase tracking-wider text-slate-500 flex items-center gap-1.5">
                      <MapPin size={13} className="text-blue-600" />
                      Resolved Address (OpenStreetMap Engine)
                    </span>
                    <button
                      onClick={() => handleForceInspectAddress(selectedEmployee.latitude, selectedEmployee.longitude)}
                      disabled={inspectingAddress}
                      className="text-[11px] text-blue-600 hover:text-blue-700 font-semibold flex items-center gap-1 cursor-pointer disabled:opacity-50"
                    >
                      <RefreshCw size={11} className={inspectingAddress ? 'animate-spin' : ''} />
                      {inspectingAddress ? 'Resolving...' : 'Re-verify Address'}
                    </button>
                  </div>

                  <div className="grid grid-cols-2 sm:grid-cols-5 gap-2">
                    {/* Village */}
                    <div className="bg-slate-50 border border-slate-200/80 rounded-xl p-2.5">
                      <div className="text-[10px] font-semibold text-slate-400 uppercase">Village / Town</div>
                      <div className="text-xs font-bold text-slate-800 truncate mt-0.5">
                        {selectedEmployee.address?.village || <span className="text-slate-300 font-normal">—</span>}
                      </div>
                    </div>

                    {/* Locality */}
                    <div className="bg-slate-50 border border-slate-200/80 rounded-xl p-2.5">
                      <div className="text-[10px] font-semibold text-slate-400 uppercase">Locality / Suburb</div>
                      <div className="text-xs font-bold text-slate-800 truncate mt-0.5">
                        {selectedEmployee.address?.locality || <span className="text-slate-300 font-normal">—</span>}
                      </div>
                    </div>

                    {/* Road */}
                    <div className="bg-slate-50 border border-slate-200/80 rounded-xl p-2.5">
                      <div className="text-[10px] font-semibold text-slate-400 uppercase">Road / Street</div>
                      <div className="text-xs font-bold text-slate-800 truncate mt-0.5">
                        {selectedEmployee.address?.road || <span className="text-slate-300 font-normal">—</span>}
                      </div>
                    </div>

                    {/* District */}
                    <div className="bg-slate-50 border border-slate-200/80 rounded-xl p-2.5">
                      <div className="text-[10px] font-semibold text-slate-400 uppercase">District</div>
                      <div className="text-xs font-bold text-slate-800 truncate mt-0.5">
                        {selectedEmployee.address?.district || <span className="text-slate-300 font-normal">—</span>}
                      </div>
                    </div>

                    {/* State */}
                    <div className="bg-slate-50 border border-slate-200/80 rounded-xl p-2.5">
                      <div className="text-[10px] font-semibold text-slate-400 uppercase">State</div>
                      <div className="text-xs font-bold text-slate-800 truncate mt-0.5">
                        {selectedEmployee.address?.state || 'Maharashtra'}
                      </div>
                    </div>
                  </div>

                  {/* Full Formatted Display Name */}
                  <div className="mt-2 text-xs text-slate-600 bg-blue-50/60 border border-blue-200/60 rounded-xl px-3 py-2 flex items-center justify-between">
                    <span className="truncate">
                      <b>Display:</b> {selectedEmployee.address?.display_name || 'Resolving OpenStreetMap address details...'}
                    </span>
                    <span className="text-[10px] text-blue-700 font-mono font-semibold uppercase px-2 py-0.5 rounded bg-blue-100 shrink-0 ml-2">
                      {selectedEmployee.address?.provider || 'OSM'}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
