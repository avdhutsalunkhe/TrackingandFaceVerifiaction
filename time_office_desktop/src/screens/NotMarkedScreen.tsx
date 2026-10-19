import React, { useState, useEffect } from 'react';
import { useTimeOffice } from '../context/TimeOfficeContext';
import { api } from '../services/api';
import { NotMarkedItem } from '../types';
import { StatusBadge } from '../components/common/Badge';
import { ExportButtons } from '../components/common/ExportButtons';
import { CorrectionModal } from './CorrectionModal';
import { 
  UserX, 
  Search, 
  ChevronLeft, 
  ChevronRight, 
  FileCheck
} from 'lucide-react';

export const NotMarkedScreen: React.FC = () => {
  const { selectedDate, refreshKey } = useTimeOffice();
  const [items, setItems] = useState<NotMarkedItem[]>([]);
  const [total, setTotal] = useState<number>(0);
  const [loading, setLoading] = useState<boolean>(true);
  const [search, setSearch] = useState<string>('');
  const [shiftFilter, setShiftFilter] = useState<number | undefined>(undefined);
  const [shifts, setShifts] = useState<{ id: number; shift_code: string; shift_name: string }[]>([]);
  const [page, setPage] = useState<number>(1);
  const pageSize = 50;

  const [correctionTarget, setCorrectionTarget] = useState<{ employeeId: string; date: string; vNo: number } | null>(null);

  // Load shifts for filter
  useEffect(() => {
    api.getShifts()
      .then((data) => {
        const arr = Array.isArray(data) ? data : (data?.shifts ?? data?.data ?? []);
        setShifts(arr);
      })
      .catch((err) => {
        console.error('[NotMarked] getShifts error:', err);
        setShifts([]);
      });
  }, []);

  const dateToUse = selectedDate || new Date().toISOString().slice(0, 10);

  useEffect(() => {
    let isMounted = true;
    setLoading(true);

    api.getNotMarkedEmployees({
      date: dateToUse,
      shift_id: shiftFilter,
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
        console.error('[NotMarked] Error:', err);
        if (isMounted) setLoading(false);
      });

    return () => {
      isMounted = false;
    };
  }, [dateToUse, shiftFilter, search, page, refreshKey]);

  const totalPages = Math.ceil(total / pageSize) || 1;

  return (
    <div className="p-6 space-y-5 bg-[#090d16] min-h-screen text-slate-200">
      {/* Header Banner */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-[#111622] p-5 rounded-2xl border border-[#1e2638] shadow-lg">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2.5 tracking-tight">
            <UserX className="w-6 h-6 text-rose-400" />
            <span>Not Marked Employees (Missing Attendance)</span>
          </h2>
          <p className="text-xs text-slate-400 mt-1">
            Scheduled employees who have not completed valid verification for date ({selectedDate})
          </p>
        </div>

        <ExportButtons
          data={items.map((i) => ({
            'Employee ID': i.employee_id,
            'Name': i.full_name,
            'Shift': i.shift_name,
            'Expected Window': i.expected_time_window,
            'Punch #': i.verification_no,
            'Current Server Time': i.current_server_time,
            'Rule Status': i.rule_status,
            'Time Remaining': i.time_remaining
          }))}
          fileName={`NotMarked_${selectedDate}`}
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
              placeholder="Search by ID or Name..."
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
        </div>

        {/* Counter & Pagination controls */}
        <div className="flex items-center gap-3">
          <span className="text-slate-400 font-mono text-xs">
            Missing: <strong className="text-rose-400">{total}</strong> employees
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

      {/* Not Marked Table */}
      <div className="bg-[#111622] border border-[#1e2638] rounded-2xl overflow-hidden shadow-lg">
        <div className="overflow-x-auto max-h-[64vh]">
          <table className="w-full text-left table-dense">
            <thead>
              <tr>
                <th>Emp ID</th>
                <th>Employee Name</th>
                <th>Assigned Shift</th>
                <th>Expected Time Window</th>
                <th>Punch #</th>
                <th>Status</th>
                <th>Rule State</th>
                <th>Time Remaining / Elapsed</th>
                <th>Current Server Time</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={10} className="text-center py-16 text-slate-400 text-xs font-mono">
                    <div className="w-7 h-7 border-2 border-[#f95700] border-t-transparent rounded-full animate-spin mx-auto mb-3" />
                    Calculating scheduled missing attendance...
                  </td>
                </tr>
              ) : items.length === 0 ? (
                <tr>
                  <td colSpan={10} className="text-center py-16 text-slate-400 text-xs">
                    All scheduled employees have marked attendance!
                  </td>
                </tr>
              ) : (
                items.map((emp) => (
                  <tr key={emp.employee_id}>
                    <td className="font-mono font-bold text-[#f95700]">{emp.employee_id}</td>
                    <td className="font-semibold text-white">{emp.full_name}</td>
                    <td className="text-slate-300">
                      {emp.shift_name} <span className="text-[10px] text-slate-500 font-mono">({emp.shift_code})</span>
                    </td>
                    <td className="font-mono text-slate-300">{emp.expected_time_window}</td>
                    <td className="font-mono text-slate-400 text-center">#{emp.verification_no}</td>
                    <td>
                      <StatusBadge status="NOT_MARKED" />
                    </td>
                    <td>
                      <span
                        className={`text-xs px-2.5 py-0.5 rounded-full font-mono font-bold border ${
                          emp.rule_status === 'WINDOW_OPEN'
                            ? 'bg-blue-500/15 text-blue-400 border-blue-500/30 animate-pulse'
                            : emp.rule_status === 'UPCOMING'
                            ? 'bg-amber-500/15 text-amber-400 border-amber-500/30'
                            : 'bg-rose-500/15 text-rose-400 border-rose-500/30'
                        }`}
                      >
                        {emp.rule_status}
                      </span>
                    </td>
                    <td className="font-mono text-slate-300">{emp.time_remaining}</td>
                    <td className="font-mono text-slate-400">{emp.current_server_time}</td>
                    <td>
                      <button
                        onClick={() => setCorrectionTarget({ employeeId: emp.employee_id, date: selectedDate, vNo: emp.verification_no })}
                        className="px-3 py-1 text-xs rounded-lg bg-[#f95700]/10 hover:bg-[#f95700]/20 text-[#f95700] border border-[#f95700]/30 flex items-center gap-1.5 font-bold transition-colors shadow-sm"
                      >
                        <FileCheck className="w-3.5 h-3.5" />
                        Correct
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

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

export default NotMarkedScreen;
