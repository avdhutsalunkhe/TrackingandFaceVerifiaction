import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useTimeOffice } from '../context/TimeOfficeContext';
import { api } from '../services/api';
import { DashboardData, RecentPunch } from '../types';
import { StatusBadge, VerificationResultBadge } from '../components/common/Badge';
import { AttendanceDetailsModal } from './AttendanceDetailsModal';
import {
  Users,
  UserCheck,
  ClockAlert,
  UserX,
  FileClock,
  ShieldAlert,
  Layers,
  ArrowRight,
  TrendingUp,
  MapPin,
  Smile,
  Shield,
  Activity
} from 'lucide-react';

export const DashboardScreen: React.FC = () => {
  const navigate = useNavigate();
  const { selectedDate, refreshKey } = useTimeOffice();
  const [data, setData] = useState<DashboardData | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [selectedPunch, setSelectedPunch] = useState<RecentPunch | null>(null);

  const dateToUse = selectedDate || new Date().toISOString().slice(0, 10);

  useEffect(() => {
    let isMounted = true;
    setLoading(true);
    api.getDashboard(dateToUse)
      .then((res) => {
        if (isMounted) {
          // API returns { date, metrics: {...}, shift_activity?, recent_punches? }
          // Normalise to the DashboardData shape the UI expects
          const normalised = {
            ...res,
            kpis: res.kpis ?? res.metrics ?? {},
            shift_activity: res.shift_activity ?? [],
            recent_punches: res.recent_punches ?? res.records ?? [],
          };
          setData(normalised);
          setLoading(false);
        }
      })
      .catch((err) => {
        console.error('[Dashboard] Error fetching dashboard data:', err);
        if (isMounted) setLoading(false);
      });

    return () => {
      isMounted = false;
    };
  }, [dateToUse, refreshKey]);

  if (loading && !data) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-slate-400 gap-3">
        <div className="w-8 h-8 border-2 border-brand-500 border-t-transparent rounded-full animate-spin" />
        <span className="text-xs uppercase tracking-wider">Loading Time Office Metrics...</span>
      </div>
    );
  }

  const kpis = data?.kpis || {
    scheduled: 0,
    present: 0,
    late: 0,
    not_marked: 0,
    pending_requests: 0,
    rejected_attempts: 0,
  };

  const attendancePercentage = kpis.scheduled > 0 
    ? Math.round((kpis.present / kpis.scheduled) * 100) 
    : 0;

  return (
    <div className="space-y-5 animate-in fade-in duration-150">
      {/* Page Header */}
      <div className="flex items-center justify-between bg-white p-5 rounded-xl border border-slate-200/80 shadow-sm">
        <div>
          <h2 className="text-xl font-bold tracking-tight text-slate-900 flex items-center gap-2">
            <span>OPERATIONAL ATTENDANCE DASHBOARD</span>
          </h2>
          <p className="text-xs text-slate-500 mt-0.5">
            Real-time biometric attendance monitoring for date <span className="font-mono text-brand-600 font-bold">{data?.selected_date || selectedDate}</span>
          </p>
        </div>

        <div className="flex items-center gap-3">
          <div className="text-right">
            <span className="text-xs text-slate-500 block leading-tight">Overall Attendance Rate</span>
            <span className="text-base font-extrabold text-emerald-600 font-mono">{attendancePercentage}%</span>
          </div>
          <div className="w-12 h-12 rounded-full bg-emerald-50 border-2 border-emerald-500 flex items-center justify-center text-xs font-bold text-emerald-700">
            {attendancePercentage}%
          </div>
        </div>
      </div>

      {/* KPI Cards Grid */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3.5">
        {/* Scheduled Employees */}
        <div
          onClick={() => navigate('/attendance')}
          className="bg-white border border-slate-200 hover:border-brand-500 p-4 rounded-xl cursor-pointer transition-all shadow-sm hover:shadow-md"
        >
          <div className="flex items-center justify-between text-slate-500 mb-2">
            <span className="text-xs font-bold uppercase tracking-wider text-slate-600">Scheduled</span>
            <Users className="w-4 h-4 text-brand-500" />
          </div>
          <div className="text-2xl font-bold font-mono text-slate-900">{kpis.scheduled}</div>
          <div className="text-[11px] text-slate-500 mt-1 flex items-center gap-1">
            <span>Active shift assignments</span>
          </div>
        </div>

        {/* Present Employees */}
        <div
          onClick={() => navigate('/present')}
          className="bg-white border border-emerald-200 hover:border-emerald-500 p-4 rounded-xl cursor-pointer transition-all shadow-sm hover:shadow-md"
        >
          <div className="flex items-center justify-between text-emerald-600 mb-2">
            <span className="text-xs font-bold uppercase tracking-wider text-emerald-700">Present</span>
            <UserCheck className="w-4 h-4 text-emerald-600" />
          </div>
          <div className="text-2xl font-bold font-mono text-emerald-600">{kpis.present}</div>
          <div className="text-[11px] text-slate-500 mt-1">
            <span>{attendancePercentage}% of scheduled</span>
          </div>
        </div>

        {/* Late Employees */}
        <div
          onClick={() => navigate('/late')}
          className="bg-white border border-amber-200 hover:border-amber-500 p-4 rounded-xl cursor-pointer transition-all shadow-sm hover:shadow-md"
        >
          <div className="flex items-center justify-between text-amber-600 mb-2">
            <span className="text-xs font-bold uppercase tracking-wider text-amber-700">Late</span>
            <ClockAlert className="w-4 h-4 text-amber-600" />
          </div>
          <div className="text-2xl font-bold font-mono text-amber-600">{kpis.late}</div>
          <div className="text-[11px] text-slate-500 mt-1">
            <span>Punched outside window</span>
          </div>
        </div>

        {/* Not Marked */}
        <div
          onClick={() => navigate('/not-marked')}
          className="bg-white border border-rose-200 hover:border-rose-500 p-4 rounded-xl cursor-pointer transition-all shadow-sm hover:shadow-md"
        >
          <div className="flex items-center justify-between text-rose-600 mb-2">
            <span className="text-xs font-bold uppercase tracking-wider text-rose-700">Not Marked</span>
            <UserX className="w-4 h-4 text-rose-600" />
          </div>
          <div className="text-2xl font-bold font-mono text-rose-600">{kpis.not_marked}</div>
          <div className="text-[11px] text-slate-500 mt-1">
            <span>No valid punch recorded</span>
          </div>
        </div>

        {/* Pending Requests */}
        <div
          onClick={() => navigate('/requests')}
          className="bg-white border border-slate-200 hover:border-blue-500 p-4 rounded-xl cursor-pointer transition-all shadow-sm hover:shadow-md"
        >
          <div className="flex items-center justify-between text-blue-600 mb-2">
            <span className="text-xs font-bold uppercase tracking-wider text-blue-700">Pending Review</span>
            <FileClock className="w-4 h-4 text-blue-600" />
          </div>
          <div className="text-2xl font-bold font-mono text-blue-600">{kpis.pending_requests}</div>
          <div className="text-[11px] text-slate-500 mt-1">
            <span>Fallback requests</span>
          </div>
        </div>

        {/* Rejected Attempts */}
        <div
          onClick={() => navigate('/attempts')}
          className="bg-white border border-slate-200 hover:border-slate-400 p-4 rounded-xl cursor-pointer transition-all shadow-sm hover:shadow-md"
        >
          <div className="flex items-center justify-between text-slate-600 mb-2">
            <span className="text-xs font-bold uppercase tracking-wider text-slate-700">Rejected</span>
            <ShieldAlert className="w-4 h-4 text-rose-500" />
          </div>
          <div className="text-2xl font-bold font-mono text-slate-800">{kpis.rejected_attempts}</div>
          <div className="text-[11px] text-slate-500 mt-1">
            <span>Biometric/GPS failures</span>
          </div>
        </div>
      </div>

      {/* Middle Section: Dynamic Shift Activity Breakdown */}
      <div className="bg-white border border-slate-200/90 rounded-xl p-5 shadow-sm">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <Layers className="w-4 h-4 text-brand-600" />
            <h3 className="text-sm font-bold text-slate-800 uppercase tracking-wider">
              Dynamic Shift Progress & Completion
            </h3>
          </div>
          <button
            onClick={() => navigate('/shift-monitoring')}
            className="text-xs text-brand-600 hover:text-brand-700 inline-flex items-center gap-1 font-semibold transition-colors"
          >
            <span>View Full Shift Rules</span>
            <ArrowRight className="w-3.5 h-3.5" />
          </button>
        </div>

        {(!data?.shift_activity || data.shift_activity.length === 0) ? (
          <div className="py-6 text-center text-xs text-slate-400">
            No shift activity recorded for this date.
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {data.shift_activity.map((shift) => (
              <div
                key={shift.shift_id}
                className="bg-slate-50/70 border border-slate-200 rounded-lg p-3.5 flex flex-col justify-between"
              >
                <div>
                  <div className="flex items-center justify-between mb-1.5">
                    <div>
                      <span className="text-xs font-bold text-slate-900">{shift.shift_name}</span>
                      <span className="text-[10px] text-white bg-slate-900 px-1.5 py-0.5 rounded font-mono ml-1.5">{shift.shift_code}</span>
                    </div>
                    <span className="text-xs font-mono font-bold text-emerald-600">
                      {shift.completion_percentage}%
                    </span>
                  </div>

                  <div className="text-[11px] text-slate-600 mb-2">
                    Window: <span className="font-mono text-slate-800 font-semibold">{shift.current_rule}</span>
                  </div>

                  {/* Progress bar */}
                  <div className="w-full bg-slate-200 h-2 rounded-full overflow-hidden mb-2">
                    <div
                      className="bg-brand-500 h-full rounded-full transition-all duration-500"
                      style={{ width: `${Math.min(100, shift.completion_percentage)}%` }}
                    />
                  </div>
                </div>

                <div className="flex items-center justify-between text-[11px] text-slate-600 pt-2 border-t border-slate-200 font-mono">
                  <span>Completed: <strong className="text-emerald-700">{shift.completed_count}</strong> / {shift.total_scheduled}</span>
                  <span>Pending: <strong className="text-rose-600">{shift.remaining_count}</strong></span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Bottom Section: Recent Live Attendance Stream */}
      <div className="bg-white border border-slate-200/90 rounded-xl overflow-hidden shadow-sm">
        <div className="px-5 py-4 border-b border-slate-200 flex items-center justify-between bg-slate-50/80">
          <div className="flex items-center gap-2">
            <Activity className="w-4 h-4 text-emerald-600" />
            <h3 className="text-sm font-bold text-slate-800 uppercase tracking-wider">
              Recent Verified Punches (Live Stream)
            </h3>
          </div>
          <button
            onClick={() => navigate('/attendance')}
            className="text-xs text-brand-600 hover:text-brand-700 inline-flex items-center gap-1 font-semibold transition-colors"
          >
            <span>View All Attendance</span>
            <ArrowRight className="w-3.5 h-3.5" />
          </button>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left table-dense">
            <thead>
              <tr>
                <th>Emp ID</th>
                <th>Employee Name</th>
                <th>Shift</th>
                <th>Verification Window</th>
                <th>Status</th>
                <th>Punch Time</th>
                <th>Face Result</th>
                <th>Liveness</th>
                <th>Distance</th>
                <th>Source</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {(!data?.recent_punches || data.recent_punches.length === 0) ? (
                <tr>
                  <td colSpan={11} className="text-center py-8 text-slate-400 text-xs">
                    No attendance punches recorded yet for today.
                  </td>
                </tr>
              ) : (
                data.recent_punches.map((punch) => (
                  <tr key={punch.id} className="cursor-pointer">
                    <td className="font-mono font-bold text-slate-900 bg-slate-100 px-2 py-1 rounded inline-block text-[11px]">{punch.employee_id}</td>
                    <td className="font-semibold text-slate-800">{punch.full_name}</td>
                    <td className="text-slate-600 font-medium">{punch.shift_name}</td>
                    <td className="font-mono text-slate-700">{punch.verification_window}</td>
                    <td>
                      <StatusBadge status={punch.status} />
                    </td>
                    <td className="font-mono text-slate-800 font-semibold">{punch.formatted_time}</td>
                    <td>
                      <span className="text-[11px] text-emerald-700 font-bold">MATCH</span>
                    </td>
                    <td>
                      <span className="text-[11px] text-emerald-700 font-bold">REAL</span>
                    </td>
                    <td className="font-mono text-slate-700">
                      {punch.gps_distance}m
                    </td>
                    <td>
                      <span className="text-[10px] px-2 py-0.5 rounded bg-slate-900 text-white font-mono font-semibold">
                        {punch.source}
                      </span>
                    </td>
                    <td>
                      <button
                        onClick={() => setSelectedPunch(punch)}
                        className="text-xs text-brand-600 hover:text-brand-700 font-bold underline"
                      >
                        Details
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Attendance Record Details Modal */}
      {selectedPunch && (
        <AttendanceDetailsModal
          isOpen={!!selectedPunch}
          onClose={() => setSelectedPunch(null)}
          punchId={selectedPunch.id}
          initialData={selectedPunch}
        />
      )}
    </div>
  );
};
