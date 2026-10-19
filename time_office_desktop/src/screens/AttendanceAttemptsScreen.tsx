import React, { useState, useEffect } from 'react';
import { useTimeOffice } from '../context/TimeOfficeContext';
import { api } from '../services/api';
import { AttendanceAttemptItem } from '../types';
import { StatusBadge } from '../components/common/Badge';
import { ExportButtons } from '../components/common/ExportButtons';
import { 
  ShieldAlert, 
  Search, 
  ChevronLeft, 
  ChevronRight
} from 'lucide-react';

const REJECTION_REASONS = [
  'OUTSIDE_ASSIGNED_AREA',
  'FACE_MISMATCH',
  'LIVENESS_FAILED',
  'TIME_WINDOW_CLOSED',
  'DUPLICATE_ATTENDANCE',
  'NO_FACE_ENROLLED',
  'NO_GEOFENCE_ASSIGNED',
  'NO_SHIFT_ASSIGNED',
  'GPS_ACCURACY_LOW'
];

export const AttendanceAttemptsScreen: React.FC = () => {
  const { selectedDate, refreshKey } = useTimeOffice();
  const [attempts, setAttempts] = useState<AttendanceAttemptItem[]>([]);
  const [total, setTotal] = useState<number>(0);
  const [loading, setLoading] = useState<boolean>(true);
  const [employeeSearch, setEmployeeSearch] = useState<string>('');
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [reasonFilter, setReasonFilter] = useState<string>('');
  const [page, setPage] = useState<number>(1);
  const pageSize = 50;

  useEffect(() => {
    let isMounted = true;
    setLoading(true);

    api.getAttempts({
      date: selectedDate,
      employee_id: employeeSearch.trim() || undefined,
      status_filter: statusFilter || undefined,
      rejection_reason: reasonFilter || undefined,
      page,
      page_size: pageSize,
    })
      .then((res) => {
        if (isMounted) {
          setAttempts(res.records || []);
          setTotal(res.total || 0);
          setLoading(false);
        }
      })
      .catch((err) => {
        console.error('[Attempts] Fetch error:', err);
        if (isMounted) setLoading(false);
      });

    return () => {
      isMounted = false;
    };
  }, [selectedDate, employeeSearch, statusFilter, reasonFilter, page, refreshKey]);

  const totalPages = Math.ceil(total / pageSize) || 1;

  return (
    <div className="p-6 space-y-5 bg-[#090d16] min-h-screen text-slate-200">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-[#111622] p-5 rounded-2xl border border-[#1e2638] shadow-lg">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2.5 tracking-tight">
            <ShieldAlert className="w-6 h-6 text-rose-400" />
            <span>Attendance Attempts Telemetry & Rejection Investigation</span>
          </h2>
          <p className="text-xs text-slate-400 mt-1">
            Diagnose biometric mismatches, anti-spoofing flags, and out-of-geofence attempts for date ({selectedDate})
          </p>
        </div>

        <ExportButtons
          data={attempts.map((a) => ({
            'Employee ID': a.employee_id,
            'Name': a.full_name,
            'Timestamp': a.timestamp,
            'Attempt Status': a.attempt_status,
            'Rejection Reason': a.rejection_reason,
            'Distance (m)': a.calculated_distance ?? '--',
            'GPS Accuracy (m)': a.gps_accuracy ?? '--',
            'Face Score': a.face_similarity ?? '--',
            'Liveness Result': a.liveness_result,
            'Source': a.source,
            'Device': a.device
          }))}
          fileName={`Attendance_Attempts_${selectedDate}`}
        />
      </div>

      {/* Filter Bar */}
      <div className="flex flex-wrap items-center justify-between gap-3 bg-[#111622] p-4 rounded-xl border border-[#1e2638] text-xs shadow-md">
        <div className="flex flex-wrap items-center gap-3 flex-1 min-w-[280px]">
          {/* Employee search */}
          <div className="relative flex-1 max-w-sm">
            <Search className="w-4 h-4 text-slate-500 absolute left-3 top-2.5" />
            <input
              type="text"
              placeholder="Search by Employee ID..."
              value={employeeSearch}
              onChange={(e) => {
                setEmployeeSearch(e.target.value);
                setPage(1);
              }}
              className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl pl-9 pr-3 py-2 text-xs font-medium text-white placeholder-slate-500 focus:outline-none focus:border-[#f95700]"
            />
          </div>

          {/* Status filter */}
          <select
            value={statusFilter}
            onChange={(e) => {
              setStatusFilter(e.target.value);
              setPage(1);
            }}
            className="bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-xs font-medium text-white focus:outline-none focus:border-[#f95700]"
          >
            <option value="">All Attempts</option>
            <option value="REJECTED">REJECTED ONLY</option>
            <option value="SUCCESS">SUCCESS ONLY</option>
          </select>

          {/* Rejection reason filter */}
          <select
            value={reasonFilter}
            onChange={(e) => {
              setReasonFilter(e.target.value);
              setPage(1);
            }}
            className="bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-xs font-medium text-white focus:outline-none focus:border-[#f95700]"
          >
            <option value="">All Rejection Reasons</option>
            {REJECTION_REASONS.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
          </select>
        </div>

        {/* Counter & Pagination controls */}
        <div className="flex items-center gap-3">
          <span className="text-slate-400 font-mono text-xs">
            Attempts: <strong className="text-white">{total}</strong>
          </span>

          <div className="flex items-center gap-1 border border-[#242f48] rounded-xl bg-[#0c1018] px-1 py-0.5">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page <= 1}
              className="p-1 text-slate-400 hover:text-white disabled:opacity-30 rounded"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            <span className="text-[11px] font-mono px-2 text-slate-300">
              {page} / {totalPages}
            </span>
            <button
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={page >= totalPages}
              className="p-1 text-slate-400 hover:text-white disabled:opacity-30 rounded"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      {/* Main Table */}
      <div className="bg-[#111622] border border-[#1e2638] rounded-2xl overflow-hidden shadow-lg">
        <div className="overflow-x-auto max-h-[64vh]">
          <table className="w-full text-left table-dense">
            <thead>
              <tr>
                <th>Emp ID</th>
                <th>Employee Name</th>
                <th>Attempt Timestamp</th>
                <th>Status</th>
                <th>Rejection / Diagnostic Reason</th>
                <th>Distance (m)</th>
                <th>GPS Accuracy</th>
                <th>Face Similarity</th>
                <th>Liveness</th>
                <th>Source</th>
                <th>Device</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={11} className="text-center py-16 text-slate-400 text-xs font-mono">
                    <div className="w-7 h-7 border-2 border-[#f95700] border-t-transparent rounded-full animate-spin mx-auto mb-3" />
                    Fetching attempt logs and rejection diagnostics...
                  </td>
                </tr>
              ) : attempts.length === 0 ? (
                <tr>
                  <td colSpan={11} className="text-center py-16 text-slate-400 text-xs">
                    No attendance verification attempts logged matching current filters.
                  </td>
                </tr>
              ) : (
                attempts.map((a) => (
                  <tr key={a.id}>
                    <td className="font-mono font-bold text-[#f95700]">{a.employee_id}</td>
                    <td className="font-semibold text-white">{a.full_name}</td>
                    <td className="font-mono text-slate-300">{a.timestamp}</td>
                    <td>
                      <span className={`px-2.5 py-0.5 rounded-full text-[10px] font-mono font-bold border ${
                        a.attempt_status === 'SUCCESS' ? 'bg-emerald-500/15 text-emerald-400 border-emerald-500/30' : 'bg-rose-500/15 text-rose-400 border-rose-500/30'
                      }`}>
                        {a.attempt_status}
                      </span>
                    </td>
                    <td>
                      {a.rejection_reason ? (
                        <span className="text-rose-400 font-mono text-[11px] font-semibold">
                          {a.rejection_reason}
                        </span>
                      ) : (
                        <span className="text-emerald-400 font-mono text-[11px]">PASSED</span>
                      )}
                    </td>
                    <td className="font-mono text-slate-300">{a.calculated_distance !== undefined && a.calculated_distance !== null ? `${a.calculated_distance}m` : '--'}</td>
                    <td className="font-mono text-slate-400">{a.gps_accuracy !== undefined && a.gps_accuracy !== null ? `${a.gps_accuracy}m` : '--'}</td>
                    <td className="font-mono text-slate-300">{a.face_similarity !== undefined && a.face_similarity !== null ? `${(a.face_similarity * 100).toFixed(1)}%` : '--'}</td>
                    <td className="font-mono text-slate-400">{a.liveness_result || '--'}</td>
                    <td className="font-mono text-slate-300 text-[11px]">{a.source || 'APP'}</td>
                    <td className="font-mono text-slate-400 text-[11px]">{a.device || 'Android'}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default AttendanceAttemptsScreen;
