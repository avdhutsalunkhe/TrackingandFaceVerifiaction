import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { 
  Users, CheckCircle2, XCircle, Clock, AlertTriangle, 
  TrendingUp, ArrowRight, RefreshCw, Sparkles, Building2, 
  LogIn, LogOut, CalendarCheck
} from 'lucide-react';
import { Link } from 'react-router-dom';
import { API_BASE } from '../api/client';

export default function Dashboard() {
  const [stats, setStats] = useState(null);
  const [trends, setTrends] = useState([]);
  const [deptStats, setDeptStats] = useState([]);
  const [recentPunches, setRecentPunches] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const fetchDashboardData = async () => {
    try {
      const [statsRes, trendsRes, deptRes, punchesRes] = await Promise.all([
        axios.get(`${API_BASE}/dashboard/stats`),
        axios.get(`${API_BASE}/dashboard/trends?days=7`),
        axios.get(`${API_BASE}/dashboard/department-stats`),
        axios.get(`${API_BASE}/dashboard/recent-punches?limit=6`)
      ]);
      setStats(statsRes.data);
      setTrends(trendsRes.data);
      setDeptStats(deptRes.data);
      setRecentPunches(punchesRes.data);
    } catch (err) {
      console.error('Failed to load dashboard data:', err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    fetchDashboardData();
  }, []);

  const handleRefresh = () => {
    setRefreshing(true);
    fetchDashboardData();
  };

  const handleSeedDemo = async () => {
    if (!window.confirm("Initialize or refresh demo attendance dataset (12 employees, 30 days of punches)?")) return;
    setRefreshing(true);
    try {
      await axios.post(`${API_BASE}/settings/seed-demo`);
      await fetchDashboardData();
    } catch (err) {
      alert("Failed to seed demo data: " + (err.response?.data?.detail || err.message));
    } finally {
      setRefreshing(false);
    }
  };

  if (loading) {
    return (
      <div className="p-8 flex items-center justify-center min-h-[60vh]">
        <div className="flex flex-col items-center gap-3 text-slate-500">
          <RefreshCw className="animate-spin text-brand-500" size={32} />
          <p className="text-sm font-medium">Loading Attendance Intelligence...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-8">
      {/* Top Banner / Welcome */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-white p-6 rounded-xl border border-slate-200/80 shadow-sm">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-2xl font-bold text-slate-900">Attendance Intelligence Overview</h1>
            <span className="px-2.5 py-0.5 text-xs font-semibold rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">
              Live Engine
            </span>
          </div>
          <p className="text-slate-500 text-sm mt-1">
            Data snapshot for <span className="font-semibold text-slate-700">{stats?.today_date || 'Today'}</span>. Shift hours: 09:00 AM – 06:00 PM.
          </p>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={handleRefresh}
            disabled={refreshing}
            className="flex items-center gap-2 px-3.5 py-2 text-sm font-medium text-slate-700 bg-slate-100 hover:bg-slate-200 rounded-lg transition-colors border border-slate-200 disabled:opacity-50"
          >
            <RefreshCw size={16} className={refreshing ? 'animate-spin' : ''} />
            Refresh
          </button>
          <button
            onClick={handleSeedDemo}
            className="flex items-center gap-2 px-3.5 py-2 text-sm font-medium text-brand-700 bg-brand-50 hover:bg-brand-100 rounded-lg transition-colors border border-brand-200"
          >
            <Sparkles size={16} />
            Seed Demo Data
          </button>
          <Link
            to="/daily"
            className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-brand-600 hover:bg-brand-700 rounded-lg shadow-sm transition-colors"
          >
            <CalendarCheck size={16} />
            View Daily Sheet
          </Link>
        </div>
      </div>

      {/* Main KPI Stats Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        {/* Total Staff */}
        <div className="bg-white p-5 rounded-xl border border-slate-200/80 shadow-sm flex items-start justify-between">
          <div>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Total Staff</p>
            <p className="text-3xl font-extrabold text-slate-900 mt-2">{stats?.total_employees || 0}</p>
            <p className="text-xs text-slate-500 mt-1 flex items-center gap-1">
              Active employees in roster
            </p>
          </div>
          <div className="w-11 h-11 rounded-lg bg-slate-100 text-slate-700 flex items-center justify-center">
            <Users size={22} />
          </div>
        </div>

        {/* Present Today */}
        <div className="bg-white p-5 rounded-xl border border-slate-200/80 shadow-sm flex items-start justify-between">
          <div>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Present Today</p>
            <div className="flex items-baseline gap-2 mt-2">
              <p className="text-3xl font-extrabold text-emerald-600">{stats?.present_today || 0}</p>
              <span className="text-xs font-semibold text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-100">
                {stats?.attendance_rate || 0}%
              </span>
            </div>
            <p className="text-xs text-slate-500 mt-1">
              + {stats?.half_day_today || 0} half-day entries
            </p>
          </div>
          <div className="w-11 h-11 rounded-lg bg-emerald-50 text-emerald-600 flex items-center justify-center">
            <CheckCircle2 size={22} />
          </div>
        </div>

        {/* Absent */}
        <div className="bg-white p-5 rounded-xl border border-slate-200/80 shadow-sm flex items-start justify-between">
          <div>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Absent Today</p>
            <p className="text-3xl font-extrabold text-rose-600 mt-2">{stats?.absent_today || 0}</p>
            <p className="text-xs text-slate-500 mt-1">
              No biometric punches registered
            </p>
          </div>
          <div className="w-11 h-11 rounded-lg bg-rose-50 text-rose-600 flex items-center justify-center">
            <XCircle size={22} />
          </div>
        </div>

        {/* Late / Missing Punches */}
        <div className="bg-white p-5 rounded-xl border border-slate-200/80 shadow-sm flex items-start justify-between">
          <div>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Late Arrivals</p>
            <div className="flex items-baseline gap-2 mt-2">
              <p className="text-3xl font-extrabold text-amber-600">{stats?.late_today || 0}</p>
              <span className="text-xs text-purple-700 bg-purple-50 px-2 py-0.5 rounded-full font-medium border border-purple-100">
                {stats?.missing_punches_today || 0} missing punch
              </span>
            </div>
            <p className="text-xs text-slate-500 mt-1">
              Avg work hours: <span className="font-semibold text-slate-700">{stats?.average_work_hours || 0} hrs</span>
            </p>
          </div>
          <div className="w-11 h-11 rounded-lg bg-amber-50 text-amber-600 flex items-center justify-center">
            <Clock size={22} />
          </div>
        </div>
      </div>

      {/* Middle Grid: Weekly Trend & Department Breakdown */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Attendance Trend (2 cols) */}
        <div className="lg:col-span-2 bg-white p-6 rounded-xl border border-slate-200/80 shadow-sm">
          <div className="flex items-center justify-between mb-6">
            <div>
              <h2 className="text-base font-bold text-slate-900 flex items-center gap-2">
                <TrendingUp size={18} className="text-brand-600" />
                7-Day Attendance Trend
              </h2>
              <p className="text-xs text-slate-500 mt-0.5">Historical present and absence distribution</p>
            </div>
            <div className="flex items-center gap-4 text-xs font-medium">
              <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full bg-emerald-500"></span> Present</span>
              <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full bg-amber-500"></span> Late</span>
              <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full bg-rose-500"></span> Absent</span>
            </div>
          </div>

          {trends.length === 0 ? (
            <div className="p-8 text-center text-slate-400 text-sm">
              No trend data available. Click "Seed Demo Data" above to generate realistic biometric records.
            </div>
          ) : (
            <div className="space-y-4">
              {trends.map((t) => {
                const total = (t.present + t.absent + t.half_day) || 1;
                const pPct = Math.round((t.present / total) * 100);
                const lPct = Math.round((t.late / total) * 100);
                const aPct = Math.round((t.absent / total) * 100);

                return (
                  <div key={t.date} className="space-y-1.5">
                    <div className="flex justify-between text-xs font-medium text-slate-700">
                      <span className="w-24 text-slate-600">{t.day_label || t.date}</span>
                      <div className="flex items-center gap-3 text-slate-500">
                        <span className="text-emerald-700 font-semibold">{t.present} Pres</span>
                        {t.late > 0 && <span className="text-amber-700">{t.late} Late</span>}
                        {t.half_day > 0 && <span className="text-yellow-700">{t.half_day} HD</span>}
                        <span className="text-rose-700">{t.absent} Abs</span>
                      </div>
                    </div>
                    {/* Visual Segmented Progress Bar */}
                    <div className="h-3 w-full bg-slate-100 rounded-full overflow-hidden flex">
                      <div style={{ width: `${pPct}%` }} className="bg-emerald-500 h-full transition-all" title={`Present: ${t.present}`} />
                      <div style={{ width: `${aPct}%` }} className="bg-rose-400 h-full transition-all" title={`Absent: ${t.absent}`} />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Department Distribution (1 col) */}
        <div className="bg-white p-6 rounded-xl border border-slate-200/80 shadow-sm flex flex-col justify-between">
          <div>
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-base font-bold text-slate-900 flex items-center gap-2">
                <Building2 size={18} className="text-brand-600" />
                Department Attendance
              </h2>
              <span className="text-xs text-slate-400">Today</span>
            </div>

            {deptStats.length === 0 ? (
              <p className="text-xs text-slate-400 text-center py-6">No departments configured yet.</p>
            ) : (
              <div className="space-y-4">
                {deptStats.slice(0, 5).map((d) => (
                  <div key={d.department} className="space-y-1">
                    <div className="flex justify-between text-xs font-medium">
                      <span className="text-slate-800">{d.department}</span>
                      <span className="text-slate-500 font-semibold">{d.present}/{d.total} ({d.attendance_rate}%)</span>
                    </div>
                    <div className="w-full bg-slate-100 h-2 rounded-full overflow-hidden">
                      <div 
                        className={`h-full rounded-full transition-all ${d.attendance_rate >= 80 ? 'bg-emerald-500' : d.attendance_rate >= 60 ? 'bg-amber-500' : 'bg-rose-500'}`}
                        style={{ width: `${d.attendance_rate}%` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          <Link
            to="/employees"
            className="mt-6 flex items-center justify-center gap-1.5 text-xs font-semibold text-brand-600 hover:text-brand-700 pt-3 border-t border-slate-100"
          >
            Manage Department Rosters <ArrowRight size={14} />
          </Link>
        </div>
      </div>

      {/* Bottom Section: Live Punch Feed & Quick Actions */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Live Biometric Punch Log (2 cols) */}
        <div className="lg:col-span-2 bg-white p-6 rounded-xl border border-slate-200/80 shadow-sm">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-base font-bold text-slate-900">Recent Biometric Punch Feed</h2>
              <p className="text-xs text-slate-500">Live check-in events recorded by the biometric engine</p>
            </div>
            <Link to="/imports" className="text-xs font-semibold text-brand-600 hover:text-brand-700 flex items-center gap-1">
              View Punch Logs <ArrowRight size={14} />
            </Link>
          </div>

          {recentPunches.length === 0 ? (
            <div className="p-8 text-center text-slate-400 text-sm">
              No punch events logged. Import biometric logs or seed demo data.
            </div>
          ) : (
            <div className="divide-y divide-slate-100">
              {recentPunches.map((punch) => {
                const isOut = punch.direction === 'OUT';
                return (
                  <div key={punch.id} className="py-3 flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      <div className={`w-8 h-8 rounded-full flex items-center justify-center font-bold text-xs ${
                        isOut ? 'bg-slate-100 text-slate-700' : 'bg-emerald-50 text-emerald-700'
                      }`}>
                        {isOut ? <LogOut size={14} /> : <LogIn size={14} />}
                      </div>
                      <div>
                        <p className="text-sm font-semibold text-slate-900">{punch.employee_name}</p>
                        <p className="text-xs text-slate-400">{punch.department} • ID: {punch.employee_id}</p>
                      </div>
                    </div>
                    <div className="text-right">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold ${
                        isOut ? 'bg-slate-100 text-slate-700' : 'bg-emerald-50 text-emerald-700'
                      }`}>
                        {punch.direction}
                      </span>
                      <p className="text-xs text-slate-500 mt-1 font-mono">{punch.time_str}</p>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Quick Portal Shortcuts (1 col) */}
        <div className="bg-slate-900 text-white p-6 rounded-xl flex flex-col justify-between shadow-sm">
          <div>
            <div className="flex items-center gap-2 text-brand-400 mb-2">
              <Sparkles size={18} />
              <span className="text-xs uppercase tracking-wider font-bold">Automation Hub</span>
            </div>
            <h3 className="text-lg font-bold text-white mb-2">Intelligent Attendance Engine</h3>
            <p className="text-slate-400 text-xs leading-relaxed mb-6">
              Calculates daily check-ins, applies grace periods, flags missing punches, and generates monthly HR payroll matrices.
            </p>

            <div className="space-y-2.5">
              <Link
                to="/imports"
                className="w-full flex items-center justify-between p-3 rounded-lg bg-slate-800 hover:bg-slate-750 transition-colors text-xs font-semibold text-slate-200 hover:text-white border border-slate-700/50"
              >
                <span>Upload .xlsx / .dat Biometric File</span>
                <ArrowRight size={14} />
              </Link>
              <Link
                to="/daily"
                className="w-full flex items-center justify-between p-3 rounded-lg bg-slate-800 hover:bg-slate-750 transition-colors text-xs font-semibold text-slate-200 hover:text-white border border-slate-700/50"
              >
                <span>Manual Punch Adjustment & Recalculate</span>
                <ArrowRight size={14} />
              </Link>
              <Link
                to="/reports"
                className="w-full flex items-center justify-between p-3 rounded-lg bg-slate-800 hover:bg-slate-750 transition-colors text-xs font-semibold text-slate-200 hover:text-white border border-slate-700/50"
              >
                <span>Download Monthly Excel & PDF Reports</span>
                <ArrowRight size={14} />
              </Link>
            </div>
          </div>

          <p className="text-[11px] text-slate-500 mt-6 pt-4 border-t border-slate-800 text-center">
            System Version 2.0.0 • SQLite Powered
          </p>
        </div>
      </div>
    </div>
  );
}
