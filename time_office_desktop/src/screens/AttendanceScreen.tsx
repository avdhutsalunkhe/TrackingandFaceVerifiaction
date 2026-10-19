import React, { useState, useEffect } from 'react';
import { useTimeOffice } from '../context/TimeOfficeContext';
import { api } from '../services/api';
import { AttendanceItem } from '../types';
import { StatusBadge } from '../components/common/Badge';
import { ExportButtons } from '../components/common/ExportButtons';
import { AttendanceDetailsModal } from './AttendanceDetailsModal';
import { CorrectionModal } from './CorrectionModal';
import { 
  Search, 
  ChevronLeft, 
  ChevronRight, 
  CalendarCheck,
  Edit2
} from 'lucide-react';

interface AttendanceScreenProps {
  fixedStatusFilter?: string;
  pageTitle?: string;
  pageSubtitle?: string;
}

export const AttendanceScreen: React.FC<AttendanceScreenProps> = ({
  fixedStatusFilter,
  pageTitle = "Today's Attendance Master View",
  pageSubtitle = "Complete verification telemetry and status for scheduled employees",
}) => {
  const { selectedDate, refreshKey } = useTimeOffice();
  const [items, setItems] = useState<AttendanceItem[]>([]);
  const [total, setTotal] = useState<number>(0);
  const [loading, setLoading] = useState<boolean>(true);
  const [search, setSearch] = useState<string>('');
  const [shiftFilter, setShiftFilter] = useState<number | undefined>(undefined);
  const [statusFilter, setStatusFilter] = useState<string>(fixedStatusFilter || '');
  const [shifts, setShifts] = useState<{ id: number; shift_code: string; shift_name: string }[]>([]);
  const [page, setPage] = useState<number>(1);
  const pageSize = 50;

  // Modals state
  const [selectedRecord, setSelectedRecord] = useState<AttendanceItem | null>(null);
  const [correctionTarget, setCorrectionTarget] = useState<{ employeeId: string; date: string; vNo: number } | null>(null);

  // Load shifts for filter
  useEffect(() => {
    api.getShifts()
      .then((data) => {
        const arr = Array.isArray(data) ? data : (data?.shifts ?? data?.data ?? []);
        setShifts(arr);
      })
      .catch(console.error);
  }, []);

  const dateToUse = selectedDate || new Date().toISOString().slice(0, 10);

  // Load attendance data
  useEffect(() => {
    let isMounted = true;
    setLoading(true);

    const effectiveStatus = fixedStatusFilter || statusFilter || undefined;

    api.getTodayAttendance({
      date: dateToUse,
      shift_id: shiftFilter,
      status_filter: effectiveStatus,
      search: search.trim() || undefined,
      page,
      page_size: pageSize,
    })
      .then((res) => {
        if (isMounted) {
          setItems(res.records || []);
          setTotal(res.total || 0);
          setLoading(false);
        }
      })
      .catch((err) => {
        console.error('[Attendance] Fetch error:', err);
        if (isMounted) setLoading(false);
      });

    return () => {
      isMounted = false;
    };
  }, [dateToUse, shiftFilter, statusFilter, fixedStatusFilter, search, page, refreshKey]);

  const totalPages = Math.ceil(total / pageSize) || 1;

  return (
    <div className="p-6 space-y-5 bg-[#090d16] min-h-screen text-slate-200">
      {/* Header & Controls */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-[#111622] p-5 rounded-2xl border border-[#1e2638] shadow-lg">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2.5 tracking-tight">
            <CalendarCheck className="w-6 h-6 text-[#f95700]" />
            <span>{pageTitle}</span>
          </h2>
          <p className="text-xs text-slate-400 mt-1">{pageSubtitle} ({selectedDate})</p>
        </div>

        <ExportButtons
          data={items.map((r) => ({
            'Employee ID': r.employee_id,
            'Name': r.employee_name,
            'Shift': r.shift_name,
            'Verification Window': r.current_verification_period,
            'Punch No': r.verification_no,
            'Status': r.status,
            'Punch Time': r.attendance_time,
            'Server Time': r.server_time,
            'Face Match': r.face_result,
            'Liveness': r.liveness_result,
            'GPS Distance (m)': r.gps_distance,
            'GPS Accuracy (m)': r.gps_accuracy ?? '--',
            'Source': r.source,
            'Device': r.device
          }))}
          fileName={`Attendance_${selectedDate}`}
        />
      </div>

      {/* Filter Bar */}
      <div className="flex flex-wrap items-center justify-between gap-3 bg-[#111622] p-4 rounded-xl border border-[#1e2638] text-xs shadow-md">
        <div className="flex flex-wrap items-center gap-3 flex-1 min-w-[280px]">
          {/* Search box */}
          <div className="relative flex-1 max-w-sm">
            <Search className="w-4 h-4 text-slate-500 absolute left-3 top-2.5" />
            <input
              type="text"
              placeholder="Search by Employee ID or Name..."
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setPage(1);
              }}
              className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl pl-9 pr-3 py-2 text-xs font-medium text-white placeholder-slate-500 focus:outline-none focus:border-[#f95700]"
            />
          </div>

          {/* Shift filter */}
          <select
            value={shiftFilter || ''}
            onChange={(e) => {
              setShiftFilter(e.target.value ? Number(e.target.value) : undefined);
              setPage(1);
            }}
            className="bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-xs font-medium text-white focus:outline-none focus:border-[#f95700]"
          >
            <option value="">All Shifts</option>
            {Array.isArray(shifts) && shifts.map((s) => (
              <option key={s.id} value={s.id}>
                {s.shift_name} ({s.shift_code})
              </option>
            ))}
          </select>

          {/* Status filter (if not fixed) */}
          {!fixedStatusFilter && (
            <select
              value={statusFilter}
              onChange={(e) => {
                setStatusFilter(e.target.value);
                setPage(1);
              }}
              className="bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-xs font-medium text-white focus:outline-none focus:border-[#f95700]"
            >
              <option value="">All Attendance Status</option>
              <option value="PRESENT">PRESENT</option>
              <option value="LATE">LATE</option>
            </select>
          )}
        </div>

        {/* Counter & Pagination controls */}
        <div className="flex items-center gap-3">
          <span className="text-slate-400 font-mono text-xs">
            Showing <strong className="text-white">{items.length}</strong> of <strong className="text-white">{total}</strong> records
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

      {/* Main Dense Data Table */}
      <div className="bg-[#111622] border border-[#1e2638] rounded-2xl overflow-hidden shadow-lg">
        <div className="overflow-x-auto max-h-[64vh]">
          <table className="w-full text-left table-dense">
            <thead>
              <tr>
                <th>Emp ID</th>
                <th>Employee Name</th>
                <th>Shift</th>
                <th>Verification Window</th>
                <th>Punch #</th>
                <th>Attendance Status</th>
                <th>Punch Time</th>
                <th>Server Time</th>
                <th>Face Match</th>
                <th>Live Person</th>
                <th>GPS Distance</th>
                <th>GPS Accuracy</th>
                <th>Source</th>
                <th>Device</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={15} className="text-center py-16 text-slate-400 text-xs font-mono">
                    <div className="w-7 h-7 border-2 border-[#f95700] border-t-transparent rounded-full animate-spin mx-auto mb-3" />
                    Querying authoritative attendance records...
                  </td>
                </tr>
              ) : items.length === 0 ? (
                <tr>
                  <td colSpan={15} className="text-center py-16 text-slate-400 text-xs">
                    No attendance records found matching filters.
                  </td>
                </tr>
              ) : (
                items.map((r) => (
                  <tr key={r.id}>
                    <td className="font-mono font-bold text-[#f95700]">{r.employee_id}</td>
                    <td className="font-semibold text-white">{r.employee_name}</td>
                    <td className="text-slate-300">{r.shift_name}</td>
                    <td className="font-mono text-slate-300">{r.current_verification_period}</td>
                    <td className="font-mono text-slate-400 text-center">#{r.verification_no}</td>
                    <td>
                      <StatusBadge status={r.status} />
                    </td>
                    <td className="font-mono font-bold text-emerald-400">{r.attendance_time}</td>
                    <td className="font-mono text-slate-400">{r.server_time}</td>
                    <td>
                      <span className={`px-2 py-0.5 rounded text-[10px] font-mono font-bold ${
                        r.face_result === 'MATCH' ? 'bg-emerald-500/15 text-emerald-400 border border-emerald-500/30' : 'bg-slate-800 text-slate-400'
                      }`}>
                        {r.face_result || 'N/A'}
                      </span>
                    </td>
                    <td>
                      <span className={`px-2 py-0.5 rounded text-[10px] font-mono font-bold ${
                        r.liveness_result === 'REAL' ? 'bg-emerald-500/15 text-emerald-400 border border-emerald-500/30' : 'bg-slate-800 text-slate-400'
                      }`}>
                        {r.liveness_result || 'N/A'}
                      </span>
                    </td>
                    <td className="font-mono text-slate-300">{r.gps_distance ? `${r.gps_distance}m` : '--'}</td>
                    <td className="font-mono text-slate-400">{r.gps_accuracy ? `${r.gps_accuracy}m` : '--'}</td>
                    <td className="text-slate-300 font-mono">{r.source || 'APP'}</td>
                    <td className="text-slate-400 font-mono text-[11px]">{r.device || 'Android'}</td>
                    <td>
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => setSelectedRecord(r)}
                          className="px-2.5 py-1 text-xs rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 font-semibold transition-colors"
                        >
                          View
                        </button>
                        <button
                          onClick={() => setCorrectionTarget({ employeeId: r.employee_id, date: selectedDate, vNo: r.verification_no })}
                          className="p-1 text-amber-400 hover:text-amber-300 hover:bg-amber-500/10 rounded-lg transition-colors"
                          title="Correct Record"
                        >
                          <Edit2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Attendance Record Detail Modal */}
      {selectedRecord && (
        <AttendanceDetailsModal
          isOpen={!!selectedRecord}
          onClose={() => setSelectedRecord(null)}
          punchId={selectedRecord.id}
          initialData={selectedRecord}
        />
      )}

      {/* Controlled Attendance Correction Modal */}
      {correctionTarget && (
        <CorrectionModal
          isOpen={!!correctionTarget}
          onClose={() => setCorrectionTarget(null)}
          initialEmployeeId={correctionTarget.employeeId}
          initialDate={correctionTarget.date}
          initialVerificationNo={correctionTarget.vNo}
        />
      )}
    </div>
  );
};

export default AttendanceScreen;
