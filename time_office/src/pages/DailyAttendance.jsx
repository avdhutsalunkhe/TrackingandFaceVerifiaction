import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { 
  Calendar, ChevronLeft, ChevronRight, RefreshCw, Plus, 
  Search, Filter, Edit3, CheckCircle2, Clock, AlertTriangle, 
  Download, Sparkles, X, UserCheck, ShieldAlert, CalendarDays,
  ArrowRight
} from 'lucide-react';

import { API_BASE } from '../api/client';
import MonthlyShiftModal from '../components/MonthlyShiftModal';

export default function DailyAttendance() {
  const [targetDate, setTargetDate] = useState(() => {
    return new Date().toISOString().split('T')[0];
  });
  const [records, setRecords] = useState([]);
  const [summary, setSummary] = useState(null);
  const [departments, setDepartments] = useState([]);
  const [activeShifts, setActiveShifts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [recalculating, setRecalculating] = useState(false);

  // Filters
  const [department, setDepartment] = useState('All');
  const [statusFilter, setStatusFilter] = useState('All');
  const [shiftFilter, setShiftFilter] = useState('All');
  const [search, setSearch] = useState('');

  // Modals
  const [editRecord, setEditRecord] = useState(null);
  const [isManualPunchOpen, setIsManualPunchOpen] = useState(false);
  const [manualPunchData, setManualPunchData] = useState({
    employee_id: '',
    time: '09:00',
    direction: 'IN'
  });
  const [shiftModalEmployee, setShiftModalEmployee] = useState(null);

  const fetchData = async () => {
    setLoading(true);
    try {
      const [recRes, sumRes, deptRes, shiftsRes] = await Promise.all([
        axios.get(`${API_BASE}/attendance/daily`, {
          params: {
            date: targetDate,
            department: department !== 'All' ? department : undefined,
            status: statusFilter !== 'All' ? statusFilter : undefined,
            shift: shiftFilter !== 'All' ? shiftFilter : undefined,
            search: search || undefined,
            size: 100
          }
        }),
        axios.get(`${API_BASE}/attendance/daily/summary`, {
          params: {
            date: targetDate,
            department: department !== 'All' ? department : undefined
          }
        }),
        axios.get(`${API_BASE}/employees/departments`),
        axios.get(`${API_BASE}/shifts/active`)
      ]);

      setRecords(recRes.data.items || []);
      setSummary(sumRes.data);
      setDepartments(deptRes.data || []);
      setActiveShifts(shiftsRes.data || []);
      if (recRes.data.target_date && recRes.data.target_date !== targetDate && !search && department === 'All' && shiftFilter === 'All') {
        setTargetDate(recRes.data.target_date);
      }
    } catch (err) {
      console.error('Failed to fetch daily attendance data:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [targetDate, department, statusFilter, shiftFilter, search]);

  const changeDateBy = (days) => {
    const cur = new Date(targetDate);
    cur.setDate(cur.getDate() + days);
    setTargetDate(cur.toISOString().split('T')[0]);
  };

  const setDateToday = () => {
    setTargetDate(new Date().toISOString().split('T')[0]);
  };

  const handleRecalculate = async () => {
    setRecalculating(true);
    try {
      const res = await axios.post(`${API_BASE}/attendance/daily/recalculate`, { date: targetDate });
      alert(res.data.message);
      fetchData();
    } catch (err) {
      alert('Recalculation error: ' + (err.response?.data?.detail || err.message));
    } finally {
      setRecalculating(false);
    }
  };

  const handleEditSubmit = async (e) => {
    e.preventDefault();
    if (!editRecord) return;
    try {
      await axios.put(`${API_BASE}/attendance/daily/${editRecord.id}`, {
        attendance_status: editRecord.attendance_status,
        first_valid_in_at: editRecord.first_valid_in_at === '—' ? null : editRecord.first_valid_in_at,
        last_valid_out_at: editRecord.last_valid_out_at === '—' ? null : editRecord.last_valid_out_at,
        remarks: editRecord.remarks
      });
      setEditRecord(null);
      fetchData();
    } catch (err) {
      alert('Failed to update record: ' + (err.response?.data?.detail || err.message));
    }
  };

  const handleManualPunchSubmit = async (e) => {
    e.preventDefault();
    try {
      const fullTimestamp = `${targetDate} ${manualPunchData.time}:00`;
      await axios.post(`${API_BASE}/attendance/daily/manual-punch`, {
        employee_id: manualPunchData.employee_id,
        timestamp: fullTimestamp,
        direction: manualPunchData.direction
      });
      setIsManualPunchOpen(false);
      setManualPunchData({ employee_id: '', time: '09:00', direction: 'IN' });
      alert('Manual punch recorded successfully.');
      fetchData();
    } catch (err) {
      alert('Failed to add manual punch: ' + (err.response?.data?.detail || err.message));
    }
  };

  const openShiftModalForEmployee = (r) => {
    const curD = new Date(targetDate);
    setShiftModalEmployee({
      id: r.employee_id,
      name: r.employee_name,
      department: r.department,
      designation: r.designation,
      targetYear: curD.getFullYear(),
      targetMonth: curD.getMonth() + 1
    });
  };

  const exportDailyCsv = () => {
    if (records.length === 0) return;
    const headers = [
      "Employee ID", "Employee Name", "Department", "Designation", 
      "Shift Code", "Shift Name", "Timing", "In Time", "Out Time", 
      "Work Hours", "Status", "1st Half", "2nd Half", "Late Mins", "Remarks"
    ];
    const rows = records.map(r => [
      r.employee_id,
      `"${r.employee_name}"`,
      `"${r.department}"`,
      `"${r.designation}"`,
      r.shift_code || 'UNASSIGNED',
      `"${r.shift_name || ''}"`,
      `"${r.shift_timing || ''}"`,
      r.first_valid_in_at,
      r.last_valid_out_at,
      r.work_hours,
      r.attendance_status,
      r.first_half_status,
      r.second_half_status,
      r.late_minutes,
      `"${r.remarks || ''}"`
    ]);

    const csvContent = "data:text/csv;charset=utf-8," + [headers.join(','), ...rows.map(e => e.join(','))].join('\n');
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement("a");
    link.setAttribute("href", encodedUri);
    link.setAttribute("download", `daily_attendance_${targetDate}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const getShiftBadgeStyle = (code, color) => {
    if (code === 'OFF') return "bg-slate-100 text-slate-700 border-slate-200";
    if (color === 'emerald') return "bg-emerald-50 text-emerald-800 border-emerald-200";
    if (color === 'blue') return "bg-blue-50 text-blue-800 border-blue-200";
    if (color === 'amber') return "bg-amber-50 text-amber-800 border-amber-200";
    if (color === 'purple') return "bg-purple-50 text-purple-800 border-purple-200";
    if (color === 'rose') return "bg-rose-50 text-rose-800 border-rose-200";
    return "bg-slate-50 text-slate-700 border-slate-200";
  };

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-8 animate-in fade-in duration-200">
      
      {/* Date Navigation & Actions Header */}
      <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4 bg-white p-6 rounded-xl border border-slate-200/80 shadow-sm">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Daily Attendance Sheet</h1>
          <p className="text-slate-500 text-sm mt-0.5">
            Shift-wise punch verification, first & second half validation, and manual roster adjustments.
          </p>
        </div>

        {/* Date Selector Pill & Controls */}
        <div className="flex flex-wrap items-center gap-2.5">
          <div className="flex items-center bg-slate-100 p-1 rounded-xl border border-slate-200">
            <button
              onClick={() => changeDateBy(-1)}
              className="p-1.5 hover:bg-white text-slate-600 hover:text-slate-900 rounded-lg transition-colors"
              title="Previous Day"
            >
              <ChevronLeft size={18} />
            </button>
            <div className="flex items-center gap-2 px-3">
              <Calendar size={16} className="text-brand-600" />
              <input
                type="date"
                value={targetDate}
                onChange={(e) => setTargetDate(e.target.value)}
                className="bg-transparent text-sm font-bold text-slate-800 focus:outline-none cursor-pointer"
              />
            </div>
            <button
              onClick={() => changeDateBy(1)}
              className="p-1.5 hover:bg-white text-slate-600 hover:text-slate-900 rounded-lg transition-colors"
              title="Next Day"
            >
              <ChevronRight size={18} />
            </button>
          </div>

          <button
            onClick={setDateToday}
            className="px-3 py-2 text-xs font-semibold text-slate-700 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors"
          >
            Today
          </button>
          <button
            onClick={handleRecalculate}
            disabled={recalculating}
            className="flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold text-brand-700 bg-brand-50 border border-brand-200 rounded-lg hover:bg-brand-100 transition-colors disabled:opacity-50"
          >
            <RefreshCw size={14} className={recalculating ? 'animate-spin' : ''} />
            Recalculate Day
          </button>
          <button
            onClick={() => setIsManualPunchOpen(true)}
            className="flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold text-white bg-slate-900 rounded-lg hover:bg-slate-800 transition-colors shadow-sm"
          >
            <Plus size={14} /> Add Manual Punch
          </button>
          <button
            onClick={exportDailyCsv}
            className="flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-slate-700 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors"
          >
            <Download size={14} /> Export CSV
          </button>
        </div>
      </div>

      {/* Day Summary Counters */}
      {summary && (
        <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-3">
          <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm text-center">
            <p className="text-[11px] font-bold uppercase tracking-wider text-slate-400">Total Staff</p>
            <p className="text-2xl font-bold text-slate-800 mt-1">{summary.total}</p>
          </div>
          <div className="bg-white p-4 rounded-xl border border-emerald-100 shadow-sm text-center">
            <p className="text-[11px] font-bold uppercase tracking-wider text-emerald-600">Present (P)</p>
            <p className="text-2xl font-bold text-emerald-600 mt-1">{summary.present}</p>
          </div>
          <div className="bg-white p-4 rounded-xl border border-yellow-100 shadow-sm text-center">
            <p className="text-[11px] font-bold uppercase tracking-wider text-yellow-600">Half Day (HD)</p>
            <p className="text-2xl font-bold text-yellow-600 mt-1">{summary.half_day}</p>
          </div>
          <div className="bg-white p-4 rounded-xl border border-rose-100 shadow-sm text-center">
            <p className="text-[11px] font-bold uppercase tracking-wider text-rose-600">Absent (A)</p>
            <p className="text-2xl font-bold text-rose-600 mt-1">{summary.absent}</p>
          </div>
          <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm text-center">
            <p className="text-[11px] font-bold uppercase tracking-wider text-slate-500">Weekly Off</p>
            <p className="text-2xl font-bold text-slate-700 mt-1">{summary.weekly_off || 0}</p>
          </div>
          <div className="bg-white p-4 rounded-xl border border-amber-100 shadow-sm text-center">
            <p className="text-[11px] font-bold uppercase tracking-wider text-amber-600">Late Arrivals</p>
            <p className="text-2xl font-bold text-amber-600 mt-1">{summary.late}</p>
          </div>
          <div className={`p-4 rounded-xl border shadow-sm text-center ${
            (summary.unassigned || 0) > 0 ? 'bg-rose-50/80 border-rose-300' : 'bg-white border-slate-200'
          }`}>
            <p className={`text-[11px] font-bold uppercase tracking-wider ${
              (summary.unassigned || 0) > 0 ? 'text-rose-700' : 'text-slate-400'
            }`}>
              No Shift Assigned
            </p>
            <p className={`text-2xl font-bold mt-1 ${
              (summary.unassigned || 0) > 0 ? 'text-rose-700' : 'text-slate-700'
            }`}>
              {summary.unassigned || 0}
            </p>
          </div>
        </div>
      )}

      {/* Main Table Section */}
      <div className="bg-white rounded-xl border border-slate-200/80 shadow-sm overflow-hidden">
        {/* Table Filters */}
        <div className="p-4 border-b border-slate-200 bg-slate-50/70 flex flex-wrap gap-3 items-center justify-between">
          <div className="flex flex-wrap items-center gap-3">
            {/* Search */}
            <div className="relative w-60">
              <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
              <input
                type="text"
                placeholder="Search employee..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="w-full pl-9 pr-3 py-1.5 text-xs bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
              />
            </div>

            {/* Department Filter */}
            <select
              value={department}
              onChange={(e) => setDepartment(e.target.value)}
              className="px-3 py-1.5 text-xs bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium text-slate-700"
            >
              <option value="All">All Departments</option>
              {departments.map((d) => (
                <option key={d} value={d}>{d}</option>
              ))}
            </select>

            {/* Shift Filter (Dynamic from DB) */}
            <select
              value={shiftFilter}
              onChange={(e) => setShiftFilter(e.target.value)}
              className="px-3 py-1.5 text-xs bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium text-slate-700"
            >
              <option value="All">All Shifts</option>
              {activeShifts.map((s) => (
                <option key={s.id} value={s.code}>{s.code} - {s.name}</option>
              ))}
              <option value="OFF">Weekly Off (OFF)</option>
              <option value="UNASSIGNED">Shift Not Assigned</option>
            </select>

            {/* Status Filter */}
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="px-3 py-1.5 text-xs bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium text-slate-700"
            >
              <option value="All">All Statuses</option>
              <option value="P">Present (P)</option>
              <option value="HD">Half Day (HD)</option>
              <option value="A">Absent (A)</option>
              <option value="WO">Weekly Off (WO)</option>
              <option value="Late">Late Arrivals</option>
              <option value="Missing Punch">Missing Punch Flag</option>
            </select>
          </div>

          <span className="text-xs text-slate-500 font-medium">
            {records.length} records shown for <span className="font-semibold text-slate-800">{targetDate}</span>
          </span>
        </div>

        {/* Attendance Records Table */}
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs border-collapse">
            <thead>
              <tr className="bg-slate-100/70 border-b border-slate-200 text-slate-600 font-semibold uppercase tracking-wider">
                <th className="p-3.5">Employee</th>
                <th className="p-3.5">Department</th>
                <th className="p-3.5">Assigned Shift</th>
                <th className="p-3.5">Shift Timing</th>
                <th className="p-3.5">In Time</th>
                <th className="p-3.5">Out Time</th>
                <th className="p-3.5">Hours</th>
                <th className="p-3.5">1st Half</th>
                <th className="p-3.5">2nd Half</th>
                <th className="p-3.5">Final Status</th>
                <th className="p-3.5">Flags / Late</th>
                <th className="p-3.5 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {loading ? (
                <tr>
                  <td colSpan="12" className="p-8 text-center text-slate-400">Loading daily attendance records...</td>
                </tr>
              ) : records.length === 0 ? (
                <tr>
                  <td colSpan="12" className="p-8 text-center text-slate-400">
                    No attendance records for {targetDate}. Click "Recalculate Day" or seed biometric data.
                  </td>
                </tr>
              ) : (
                records.map((r) => {
                  let badgeClass = "bg-slate-100 text-slate-700";
                  let label = r.attendance_status;
                  if (r.attendance_status === 'P') {
                    badgeClass = "bg-emerald-100 text-emerald-800";
                    label = "Present (P)";
                  } else if (r.attendance_status === 'HD') {
                    badgeClass = "bg-yellow-100 text-yellow-800";
                    label = "Half Day (HD)";
                  } else if (r.attendance_status === 'A') {
                    badgeClass = "bg-rose-100 text-rose-800";
                    label = "Absent (A)";
                  } else if (r.attendance_status === 'WO') {
                    badgeClass = "bg-slate-100 text-slate-600";
                    label = "Weekly Off (WO)";
                  } else if (r.attendance_status === 'LEAVE' || r.attendance_status?.startsWith('LEAVE')) {
                    badgeClass = "bg-indigo-50 text-indigo-700 border border-indigo-200 font-bold";
                    label = "On Leave";
                  } else if (r.attendance_status === 'UNASSIGNED') {
                    badgeClass = "bg-rose-50 text-rose-700 border border-rose-200";
                    label = "Unassigned";
                  }

                  const hasShift = r.shift_code && r.shift_code !== 'UNASSIGNED';

                  return (
                    <tr key={r.id} className="hover:bg-slate-50 transition-colors">
                      {/* Employee */}
                      <td className="p-3.5">
                        <div className="flex items-center gap-2.5">
                          <div className="w-7 h-7 rounded-full bg-brand-100 text-brand-700 flex items-center justify-center font-bold text-xs shrink-0">
                            {r.employee_name?.charAt(0) || 'E'}
                          </div>
                          <div>
                            <span className="font-semibold text-slate-900 block">{r.employee_name}</span>
                            <span className="font-mono text-[11px] text-slate-400">ID: {r.employee_id}</span>
                          </div>
                        </div>
                      </td>

                      {/* Department */}
                      <td className="p-3.5 text-slate-600">
                        <div>
                          <span>{r.department}</span>
                          <span className="block text-[11px] text-slate-400">{r.designation}</span>
                        </div>
                      </td>

                      {/* Assigned Shift */}
                      <td className="p-3.5">
                        {hasShift ? (
                          <span className={`inline-flex px-2 py-0.5 rounded text-[11px] font-bold border ${getShiftBadgeStyle(r.shift_code, r.shift_color)}`}>
                            {r.shift_code} - {r.shift_name}
                          </span>
                        ) : (
                          <button
                            type="button"
                            onClick={() => openShiftModalForEmployee(r)}
                            className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-bold bg-rose-50 text-rose-700 border border-rose-200 hover:bg-rose-100 transition-colors cursor-pointer"
                            title="Click to assign monthly shift roster"
                          >
                            <AlertTriangle size={11} />
                            Shift Not Assigned
                          </button>
                        )}
                      </td>

                      {/* Shift Timing */}
                      <td className="p-3.5 font-mono text-[11px] text-slate-600">
                        {r.shift_timing || '—'}
                      </td>

                      {/* In & Out Punches */}
                      <td className="p-3.5 font-mono font-medium text-slate-700">{r.first_valid_in_at}</td>
                      <td className="p-3.5 font-mono font-medium text-slate-700">{r.last_valid_out_at}</td>

                      {/* Total Hours */}
                      <td className="p-3.5 font-mono font-bold text-slate-800">
                        {r.work_hours > 0 ? `${r.work_hours}h` : '0h'}
                      </td>

                      {/* First Half Status */}
                      <td className="p-3.5">
                        <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${
                          r.first_half_status === 'Present' 
                            ? 'bg-emerald-50 text-emerald-700 border border-emerald-200' 
                            : r.first_half_status === 'Missing' 
                              ? 'bg-amber-50 text-amber-700 border border-amber-200' 
                              : 'bg-slate-100 text-slate-500'
                        }`}>
                          {r.first_half_status || '—'}
                        </span>
                      </td>

                      {/* Second Half Status */}
                      <td className="p-3.5">
                        <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${
                          r.second_half_status === 'Present' 
                            ? 'bg-emerald-50 text-emerald-700 border border-emerald-200' 
                            : r.second_half_status === 'Missing' 
                              ? 'bg-amber-50 text-amber-700 border border-amber-200' 
                              : 'bg-slate-100 text-slate-500'
                        }`}>
                          {r.second_half_status || '—'}
                        </span>
                      </td>

                      {/* Final Status */}
                      <td className="p-3.5">
                        <span className={`inline-flex px-2 py-0.5 rounded text-[11px] font-semibold ${badgeClass}`}>
                          {label}
                        </span>
                      </td>

                      {/* Flags & Late */}
                      <td className="p-3.5">
                        <div className="flex flex-wrap gap-1">
                          {r.late_minutes > 0 && (
                            <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-semibold bg-amber-50 text-amber-700 border border-amber-200">
                              <Clock size={10} /> +{r.late_minutes}m Late
                            </span>
                          )}
                          {r.early_departure_minutes > 0 && (
                            <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-semibold bg-blue-50 text-blue-700 border border-blue-200">
                              -{r.early_departure_minutes}m Early
                            </span>
                          )}
                          {r.missing_punch_flag && (
                            <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-semibold bg-purple-50 text-purple-700 border border-purple-200">
                              <ShieldAlert size={10} /> Incomplete
                            </span>
                          )}
                          {!r.late_minutes && !r.missing_punch_flag && !r.early_departure_minutes && (
                            <span className="text-slate-400 text-[11px]">Normal</span>
                          )}
                        </div>
                      </td>

                      {/* Actions */}
                      <td className="p-3.5 text-right">
                        <div className="inline-flex items-center gap-1">
                          <button
                            type="button"
                            onClick={() => openShiftModalForEmployee(r)}
                            className="p-1 text-slate-400 hover:text-brand-600 hover:bg-brand-50 rounded transition-colors"
                            title="Manage Employee Monthly Shifts"
                          >
                            <CalendarDays size={15} />
                          </button>
                          <button
                            type="button"
                            onClick={() => setEditRecord({ ...r })}
                            className="px-2 py-1 text-slate-600 hover:text-brand-600 hover:bg-brand-50 rounded transition-colors inline-flex items-center gap-1"
                            title="Override attendance details"
                          >
                            <Edit3 size={13} /> Edit
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Manual Override Modal */}
      {editRecord && (
        <div className="fixed inset-0 bg-slate-900/50 backdrop-blur-xs flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl shadow-2xl max-w-md w-full overflow-hidden">
            <div className="p-5 border-b border-slate-100 flex items-center justify-between bg-slate-50">
              <div>
                <h3 className="font-bold text-slate-900">Manual Attendance Override</h3>
                <p className="text-xs text-slate-500">{editRecord.employee_name} ({editRecord.employee_id})</p>
              </div>
              <button onClick={() => setEditRecord(null)} className="text-slate-400 hover:text-slate-600">
                <X size={18} />
              </button>
            </div>

            <form onSubmit={handleEditSubmit} className="p-5 space-y-4 text-xs">
              <div>
                <label className="block font-semibold text-slate-700 mb-1">Attendance Status</label>
                <select
                  value={editRecord.attendance_status}
                  onChange={(e) => setEditRecord({ ...editRecord, attendance_status: e.target.value })}
                  className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium"
                >
                  <option value="P">Present (P)</option>
                  <option value="HD">Half Day (HD)</option>
                  <option value="A">Absent (A)</option>
                  <option value="WO">Weekly Off (WO)</option>
                </select>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">In Time (HH:MM)</label>
                  <input
                    type="text"
                    value={editRecord.first_valid_in_at === '—' ? '' : editRecord.first_valid_in_at}
                    placeholder="09:00"
                    onChange={(e) => setEditRecord({ ...editRecord, first_valid_in_at: e.target.value })}
                    className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono"
                  />
                </div>
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Out Time (HH:MM)</label>
                  <input
                    type="text"
                    value={editRecord.last_valid_out_at === '—' ? '' : editRecord.last_valid_out_at}
                    placeholder="18:00"
                    onChange={(e) => setEditRecord({ ...editRecord, last_valid_out_at: e.target.value })}
                    className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono"
                  />
                </div>
              </div>

              <div>
                <label className="block font-semibold text-slate-700 mb-1">HR Audit Note / Remarks</label>
                <input
                  type="text"
                  placeholder="e.g. Biometric scanner issue / Approved work from home"
                  value={editRecord.remarks || ''}
                  onChange={(e) => setEditRecord({ ...editRecord, remarks: e.target.value })}
                  className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
                />
              </div>

              <div className="pt-2 flex justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setEditRecord(null)}
                  className="px-4 py-2 border border-slate-200 rounded-lg text-slate-600 hover:bg-slate-50 font-semibold"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg font-semibold"
                >
                  Apply Override
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Manual Add Punch Modal */}
      {isManualPunchOpen && (
        <div className="fixed inset-0 bg-slate-900/50 backdrop-blur-xs flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl shadow-2xl max-w-md w-full overflow-hidden">
            <div className="p-5 border-b border-slate-100 flex items-center justify-between bg-slate-50">
              <div>
                <h3 className="font-bold text-slate-900">Add Biometric Punch</h3>
                <p className="text-xs text-slate-500">Record missing punch for date: {targetDate}</p>
              </div>
              <button onClick={() => setIsManualPunchOpen(false)} className="text-slate-400 hover:text-slate-600">
                <X size={18} />
              </button>
            </div>

            <form onSubmit={handleManualPunchSubmit} className="p-5 space-y-4 text-xs">
              <div>
                <label className="block font-semibold text-slate-700 mb-1">Employee ID *</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. EMP101"
                  value={manualPunchData.employee_id}
                  onChange={(e) => setManualPunchData({ ...manualPunchData, employee_id: e.target.value })}
                  className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Punch Time (HH:MM) *</label>
                  <input
                    type="time"
                    required
                    value={manualPunchData.time}
                    onChange={(e) => setManualPunchData({ ...manualPunchData, time: e.target.value })}
                    className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono"
                  />
                </div>
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Direction</label>
                  <select
                    value={manualPunchData.direction}
                    onChange={(e) => setManualPunchData({ ...manualPunchData, direction: e.target.value })}
                    className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium"
                  >
                    <option value="IN">IN</option>
                    <option value="OUT">OUT</option>
                    <option value="AUTO">AUTO</option>
                  </select>
                </div>
              </div>

              <div className="pt-2 flex justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setIsManualPunchOpen(false)}
                  className="px-4 py-2 border border-slate-200 rounded-lg text-slate-600 hover:bg-slate-50 font-semibold"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-4 py-2 bg-slate-900 hover:bg-slate-800 text-white rounded-lg font-semibold"
                >
                  Save Punch & Recalculate
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Monthly Shift Assignment Modal */}
      {shiftModalEmployee && (
        <MonthlyShiftModal
          employee={shiftModalEmployee}
          initialYear={shiftModalEmployee.targetYear}
          initialMonth={shiftModalEmployee.targetMonth}
          onClose={() => setShiftModalEmployee(null)}
          onSaved={fetchData}
        />
      )}

    </div>
  );
}
