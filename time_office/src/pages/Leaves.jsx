import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { 
  CalendarClock, Plus, Search, Filter, Trash2, CheckCircle2, 
  XCircle, Clock, AlertCircle, RefreshCw, User, Calendar, FileText, X, Check
} from 'lucide-react';
import { API_BASE } from '../api/client';
import { useAuth } from '../context/AuthContext';

const LEAVE_TYPES = [
  { code: 'CL', label: 'Casual Leave (CL)', color: 'bg-blue-50 text-blue-700 border-blue-200' },
  { code: 'SL', label: 'Sick Leave (SL)', color: 'bg-rose-50 text-rose-700 border-rose-200' },
  { code: 'PL', label: 'Paid / Earned Leave (PL)', color: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
  { code: 'LWP', label: 'Leave Without Pay (LWP)', color: 'bg-amber-50 text-amber-700 border-amber-200' },
  { code: 'HD', label: 'Half Day Leave', color: 'bg-purple-50 text-purple-700 border-purple-200' },
  { code: 'COMP', label: 'Compensatory Off', color: 'bg-indigo-50 text-indigo-700 border-indigo-200' },
  { code: 'EMG', label: 'Emergency Leave', color: 'bg-orange-50 text-orange-700 border-orange-200' },
];

export default function Leaves() {
  const { currentUser, isAdmin } = useAuth();
  const [leaves, setLeaves] = useState([]);
  const [employees, setEmployees] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [successMsg, setSuccessMsg] = useState(null);

  // Filters
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('ALL');
  const [selectedMonth, setSelectedMonth] = useState(new Date().getMonth() + 1);
  const [selectedYear, setSelectedYear] = useState(new Date().getFullYear());

  // Modal State
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [leaveForm, setLeaveForm] = useState({
    employee_id: '',
    leave_type: 'Casual Leave (CL)',
    start_date: new Date().toISOString().split('T')[0],
    end_date: new Date().toISOString().split('T')[0],
    is_half_day: false,
    half_day_session: 'first_half',
    reason: ''
  });

  const fetchData = async () => {
    setLoading(true);
    setError(null);
    try {
      const [leavesRes, empRes] = await Promise.all([
        axios.get(`${API_BASE}/leaves/`, {
          params: {
            year: selectedYear,
            month: selectedMonth,
            status: statusFilter
          }
        }),
        axios.get(`${API_BASE}/employees/`, { params: { limit: 500 } })
      ]);

      setLeaves(leavesRes.data || []);
      const empData = Array.isArray(empRes.data) ? empRes.data : (empRes.data?.items || []);
      setEmployees(empData.filter(e => e.status !== 'Inactive'));
      if (empData.length > 0 && !leaveForm.employee_id) {
        setLeaveForm(prev => ({ ...prev, employee_id: empData[0].id }));
      }
    } catch (err) {
      console.error(err);
      setError('Failed to fetch leaves or employees data.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [selectedMonth, selectedYear, statusFilter]);

  const handleOpenModal = () => {
    setLeaveForm({
      employee_id: employees.length > 0 ? employees[0].id : '',
      leave_type: 'Casual Leave (CL)',
      start_date: new Date().toISOString().split('T')[0],
      end_date: new Date().toISOString().split('T')[0],
      is_half_day: false,
      half_day_session: 'first_half',
      reason: ''
    });
    setIsModalOpen(true);
  };

  const handleSubmitLeave = async (e) => {
    e.preventDefault();
    if (!leaveForm.employee_id) {
      alert('Please select an employee');
      return;
    }

    setSubmitting(true);
    setError(null);
    try {
      await axios.post(`${API_BASE}/leaves/`, {
        ...leaveForm,
        employee_id: parseInt(leaveForm.employee_id, 10),
        applied_by: currentUser?.username || 'clerk'
      });

      setIsModalOpen(false);
      setSuccessMsg('Leave logged successfully! Daily attendance updated.');
      setTimeout(() => setSuccessMsg(null), 4000);
      fetchData();
    } catch (err) {
      const msg = err.response?.data?.detail || err.message || 'Error saving leave';
      alert(`Failed to save leave: ${msg}`);
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteLeave = async (leaveId) => {
    if (!window.confirm('Are you sure you want to delete this leave record? Attendance for affected dates will be recalculated.')) {
      return;
    }

    try {
      await axios.delete(`${API_BASE}/leaves/${leaveId}`);
      setSuccessMsg('Leave removed and attendance recalculated.');
      setTimeout(() => setSuccessMsg(null), 3000);
      fetchData();
    } catch (err) {
      alert('Failed to delete leave');
    }
  };

  const handleStatusChange = async (leaveId, newStatus) => {
    try {
      await axios.patch(`${API_BASE}/leaves/${leaveId}/status`, {
        status: newStatus,
        approved_by: currentUser?.username || 'admin'
      });
      fetchData();
    } catch (err) {
      alert('Failed to update status');
    }
  };

  const filteredLeaves = leaves.filter(l => {
    if (!searchTerm.trim()) return true;
    const term = searchTerm.toLowerCase();
    const nameMatch = l.employee_name?.toLowerCase().includes(term);
    const codeMatch = l.employee_code?.toLowerCase().includes(term);
    const typeMatch = l.leave_type?.toLowerCase().includes(term);
    const reasonMatch = l.reason?.toLowerCase().includes(term);
    return nameMatch || codeMatch || typeMatch || reasonMatch;
  });

  const totalLeavesCount = filteredLeaves.length;
  const approvedCount = filteredLeaves.filter(l => l.status === 'APPROVED').length;
  const pendingCount = filteredLeaves.filter(l => l.status === 'PENDING').length;

  return (
    <div className="p-8 space-y-6 max-w-7xl mx-auto">
      {/* Top Banner / Alerts */}
      {successMsg && (
        <div className="p-3.5 bg-emerald-50 border border-emerald-200 text-emerald-800 rounded-xl text-xs font-semibold flex items-center gap-2 shadow-xs animate-in fade-in">
          <CheckCircle2 size={16} className="text-emerald-600 shrink-0" />
          <span>{successMsg}</span>
        </div>
      )}

      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <div className="flex items-center gap-2.5">
            <div className="p-2 bg-orange-100 text-orange-600 rounded-xl">
              <CalendarClock size={22} className="stroke-[2.5]" />
            </div>
            <div>
              <h1 className="text-2xl font-black text-slate-900 tracking-tight">Leave & Absence Records</h1>
              <p className="text-xs text-slate-500 font-medium">
                Log employee leaves, sick days, and half-day absences with automatic attendance synchronization
              </p>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={fetchData}
            title="Refresh leaves"
            className="p-2 text-slate-600 hover:text-slate-900 hover:bg-slate-100 rounded-xl border border-slate-200 transition-colors cursor-pointer"
          >
            <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
          </button>
          <button
            onClick={handleOpenModal}
            className="px-4 py-2.5 bg-orange-600 hover:bg-orange-700 active:bg-orange-800 text-white rounded-xl text-xs font-bold shadow-md shadow-orange-600/20 transition-all flex items-center gap-2 cursor-pointer"
          >
            <Plus size={16} className="stroke-[3]" />
            <span>Record / Fill Leave</span>
          </button>
        </div>
      </div>

      {/* Metrics Row */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="bg-white p-4 rounded-2xl border border-slate-200/80 shadow-xs">
          <span className="text-[11px] font-bold text-slate-400 uppercase tracking-wider block">Total Leaves Logged</span>
          <div className="text-2xl font-black text-slate-900 mt-1">{totalLeavesCount}</div>
          <span className="text-[10px] text-slate-500 font-medium">In selected month / filter</span>
        </div>
        <div className="bg-white p-4 rounded-2xl border border-slate-200/80 shadow-xs">
          <span className="text-[11px] font-bold text-emerald-600 uppercase tracking-wider block">Approved & Applied</span>
          <div className="text-2xl font-black text-emerald-700 mt-1">{approvedCount}</div>
          <span className="text-[10px] text-emerald-600/80 font-medium">Synchronized with daily attendance</span>
        </div>
        <div className="bg-white p-4 rounded-2xl border border-slate-200/80 shadow-xs">
          <span className="text-[11px] font-bold text-amber-600 uppercase tracking-wider block">Pending Approval</span>
          <div className="text-2xl font-black text-amber-700 mt-1">{pendingCount}</div>
          <span className="text-[10px] text-amber-600/80 font-medium">Awaiting administrator review</span>
        </div>
      </div>

      {/* Filter Bar */}
      <div className="bg-white p-4 rounded-2xl border border-slate-200 shadow-xs flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2 flex-1 min-w-[240px]">
          <div className="relative w-full max-w-xs">
            <Search size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
            <input
              type="text"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              placeholder="Search employee, type, or reason..."
              className="w-full pl-9 pr-3.5 py-2 text-xs border border-slate-200 rounded-xl focus:ring-2 focus:ring-orange-500 focus:outline-none"
            />
          </div>

          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="px-3 py-2 text-xs border border-slate-200 rounded-xl focus:ring-2 focus:ring-orange-500 focus:outline-none text-slate-700 font-medium cursor-pointer"
          >
            <option value="ALL">All Statuses</option>
            <option value="APPROVED">Approved Only</option>
            <option value="PENDING">Pending Only</option>
            <option value="REJECTED">Rejected</option>
          </select>
        </div>

        <div className="flex items-center gap-2">
          <select
            value={selectedMonth}
            onChange={(e) => setSelectedMonth(parseInt(e.target.value, 10))}
            className="px-3 py-2 text-xs border border-slate-200 rounded-xl focus:ring-2 focus:ring-orange-500 focus:outline-none text-slate-700 font-medium cursor-pointer"
          >
            {Array.from({ length: 12 }, (_, i) => i + 1).map(m => (
              <option key={m} value={m}>
                {new Date(2026, m - 1).toLocaleString('default', { month: 'long' })}
              </option>
            ))}
          </select>

          <select
            value={selectedYear}
            onChange={(e) => setSelectedYear(parseInt(e.target.value, 10))}
            className="px-3 py-2 text-xs border border-slate-200 rounded-xl focus:ring-2 focus:ring-orange-500 focus:outline-none text-slate-700 font-medium cursor-pointer"
          >
            {[2025, 2026, 2027].map(y => (
              <option key={y} value={y}>{y}</option>
            ))}
          </select>
        </div>
      </div>

      {/* Leaves Table */}
      <div className="bg-white rounded-2xl border border-slate-200 shadow-xs overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-slate-400 text-xs flex flex-col items-center gap-2">
            <RefreshCw size={20} className="animate-spin text-orange-500" />
            <span>Loading leave records...</span>
          </div>
        ) : filteredLeaves.length === 0 ? (
          <div className="p-12 text-center space-y-3">
            <div className="w-12 h-12 rounded-full bg-slate-100 flex items-center justify-center text-slate-400 mx-auto">
              <CalendarClock size={24} />
            </div>
            <h3 className="text-sm font-bold text-slate-700">No Leave Records Found</h3>
            <p className="text-xs text-slate-500 max-w-sm mx-auto">
              There are no leaves recorded for the selected month and filters. Click "+ Record / Fill Leave" to log an employee absence.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="bg-slate-50/80 border-b border-slate-200 text-slate-500 font-bold uppercase tracking-wider text-[10px]">
                  <th className="py-3.5 px-4">Employee</th>
                  <th className="py-3.5 px-4">Leave Type</th>
                  <th className="py-3.5 px-4">Duration & Dates</th>
                  <th className="py-3.5 px-4">Reason / Notes</th>
                  <th className="py-3.5 px-4">Logged By</th>
                  <th className="py-3.5 px-4">Status</th>
                  <th className="py-3.5 px-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                {filteredLeaves.map((l) => (
                  <tr key={l.id} className="hover:bg-slate-50/60 transition-colors">
                    {/* Employee */}
                    <td className="py-3 px-4">
                      <div className="flex items-center gap-2.5">
                        <div className="w-8 h-8 rounded-full bg-orange-100 text-orange-700 flex items-center justify-center font-bold text-xs shrink-0">
                          {l.employee_name ? l.employee_name[0] : 'E'}
                        </div>
                        <div>
                          <div className="font-bold text-slate-900">{l.employee_name || `Emp #${l.employee_id}`}</div>
                          <div className="text-[10px] text-slate-400 font-mono">
                            {l.employee_code || `#${l.employee_id}`} • {l.department || 'General'}
                          </div>
                        </div>
                      </div>
                    </td>

                    {/* Leave Type */}
                    <td className="py-3 px-4">
                      <span className="inline-flex items-center px-2.5 py-1 rounded-lg text-[11px] font-bold bg-blue-50 text-blue-700 border border-blue-200/80">
                        {l.leave_type}
                      </span>
                    </td>

                    {/* Duration & Dates */}
                    <td className="py-3 px-4 font-mono text-[11px]">
                      <div>
                        {l.start_date === l.end_date ? (
                          <span>{l.start_date}</span>
                        ) : (
                          <span>{l.start_date} → {l.end_date}</span>
                        )}
                      </div>
                      <div className="text-[10px] text-slate-500 font-sans mt-0.5">
                        {l.is_half_day ? (
                          <span className="text-purple-600 font-semibold">Half Day ({l.half_day_session === 'first_half' ? '1st Half' : '2nd Half'})</span>
                        ) : (
                          <span>{l.days_count} Full Day{l.days_count > 1 ? 's' : ''}</span>
                        )}
                      </div>
                    </td>

                    {/* Reason */}
                    <td className="py-3 px-4 max-w-xs truncate text-slate-600">
                      {l.reason || <span className="text-slate-400 italic">None provided</span>}
                    </td>

                    {/* Logged By */}
                    <td className="py-3 px-4">
                      <span className="px-2 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider bg-slate-100 text-slate-700">
                        {l.applied_by || 'Staff'}
                      </span>
                    </td>

                    {/* Status */}
                    <td className="py-3 px-4">
                      {l.status === 'APPROVED' ? (
                        <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                          <CheckCircle2 size={11} /> Approved
                        </span>
                      ) : l.status === 'PENDING' ? (
                        <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold bg-amber-50 text-amber-700 border border-amber-200">
                          <Clock size={11} /> Pending
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold bg-rose-50 text-rose-700 border border-rose-200">
                          <XCircle size={11} /> Rejected
                        </span>
                      )}
                    </td>

                    {/* Actions */}
                    <td className="py-3 px-4 text-right">
                      <div className="flex items-center justify-end gap-1.5">
                        {isAdmin && l.status === 'PENDING' && (
                          <>
                            <button
                              onClick={() => handleStatusChange(l.id, 'APPROVED')}
                              title="Approve Leave"
                              className="p-1.5 text-emerald-600 hover:bg-emerald-50 rounded-lg transition-colors cursor-pointer"
                            >
                              <Check size={15} />
                            </button>
                            <button
                              onClick={() => handleStatusChange(l.id, 'REJECTED')}
                              title="Reject Leave"
                              className="p-1.5 text-rose-600 hover:bg-rose-50 rounded-lg transition-colors cursor-pointer"
                            >
                              <X size={15} />
                            </button>
                          </>
                        )}
                        <button
                          onClick={() => handleDeleteLeave(l.id)}
                          title="Delete Leave"
                          className="p-1.5 text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded-lg transition-colors cursor-pointer"
                        >
                          <Trash2 size={15} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Record / Fill Leave Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4 animate-in fade-in duration-150">
          <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 w-full max-w-lg overflow-hidden">
            <div className="px-6 py-4 bg-slate-900 text-white flex items-center justify-between">
              <div className="flex items-center gap-2.5">
                <div className="p-1.5 rounded-lg bg-orange-500/20 text-orange-400">
                  <CalendarClock size={18} />
                </div>
                <div>
                  <h3 className="text-sm font-bold text-white">Record Employee Leave</h3>
                  <p className="text-[11px] text-slate-400">Apply leave and update attendance calculation</p>
                </div>
              </div>
              <button
                onClick={() => setIsModalOpen(false)}
                className="p-1 text-slate-400 hover:text-white rounded-lg hover:bg-slate-800 transition-colors cursor-pointer"
              >
                <X size={18} />
              </button>
            </div>

            <form onSubmit={handleSubmitLeave} className="p-6 space-y-4">
              {/* Employee Selection */}
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1.5">
                  Select Employee <span className="text-rose-500">*</span>
                </label>
                <select
                  required
                  value={leaveForm.employee_id}
                  onChange={(e) => setLeaveForm({ ...leaveForm, employee_id: e.target.value })}
                  className="w-full px-3.5 py-2 text-xs border border-slate-300 rounded-xl focus:ring-2 focus:ring-orange-500 focus:outline-none"
                >
                  <option value="">-- Choose Employee --</option>
                  {employees.map(emp => (
                    <option key={emp.id} value={emp.id}>
                      {emp.name} ({emp.employee_code || `#${emp.id}`}) - {emp.department || 'General'}
                    </option>
                  ))}
                </select>
              </div>

              {/* Leave Type */}
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1.5">
                  Leave Type <span className="text-rose-500">*</span>
                </label>
                <select
                  value={leaveForm.leave_type}
                  onChange={(e) => setLeaveForm({ ...leaveForm, leave_type: e.target.value })}
                  className="w-full px-3.5 py-2 text-xs border border-slate-300 rounded-xl focus:ring-2 focus:ring-orange-500 focus:outline-none font-medium"
                >
                  {LEAVE_TYPES.map(t => (
                    <option key={t.code} value={t.label}>{t.label}</option>
                  ))}
                </select>
              </div>

              {/* Date Range */}
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1.5">
                    Start Date <span className="text-rose-500">*</span>
                  </label>
                  <input
                    type="date"
                    required
                    value={leaveForm.start_date}
                    onChange={(e) => {
                      const newStart = e.target.value;
                      setLeaveForm(prev => ({
                        ...prev,
                        start_date: newStart,
                        end_date: prev.end_date < newStart ? newStart : prev.end_date
                      }));
                    }}
                    className="w-full px-3.5 py-2 text-xs border border-slate-300 rounded-xl focus:ring-2 focus:ring-orange-500 focus:outline-none font-mono"
                  />
                </div>

                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1.5">
                    End Date <span className="text-rose-500">*</span>
                  </label>
                  <input
                    type="date"
                    required
                    min={leaveForm.start_date}
                    value={leaveForm.end_date}
                    onChange={(e) => setLeaveForm({ ...leaveForm, end_date: e.target.value })}
                    className="w-full px-3.5 py-2 text-xs border border-slate-300 rounded-xl focus:ring-2 focus:ring-orange-500 focus:outline-none font-mono"
                  />
                </div>
              </div>

              {/* Half Day Option */}
              <div className="p-3 bg-slate-50 border border-slate-200 rounded-xl space-y-2">
                <label className="flex items-center gap-2 cursor-pointer text-xs font-bold text-slate-700">
                  <input
                    type="checkbox"
                    checked={leaveForm.is_half_day}
                    onChange={(e) => setLeaveForm({ ...leaveForm, is_half_day: e.target.checked })}
                    className="w-4 h-4 text-orange-600 rounded border-slate-300 focus:ring-orange-500"
                  />
                  <span>Half Day Leave (0.5 Day)</span>
                </label>

                {leaveForm.is_half_day && (
                  <div className="grid grid-cols-2 gap-2 pt-1 pl-6">
                    <label className="flex items-center gap-2 text-xs text-slate-600 cursor-pointer">
                      <input
                        type="radio"
                        name="half_session"
                        checked={leaveForm.half_day_session === 'first_half'}
                        onChange={() => setLeaveForm({ ...leaveForm, half_day_session: 'first_half' })}
                        className="text-orange-600"
                      />
                      <span>First Half (Morning)</span>
                    </label>
                    <label className="flex items-center gap-2 text-xs text-slate-600 cursor-pointer">
                      <input
                        type="radio"
                        name="half_session"
                        checked={leaveForm.half_day_session === 'second_half'}
                        onChange={() => setLeaveForm({ ...leaveForm, half_day_session: 'second_half' })}
                        className="text-orange-600"
                      />
                      <span>Second Half (Afternoon)</span>
                    </label>
                  </div>
                )}
              </div>

              {/* Reason / Remarks */}
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1.5">
                  Reason / Remarks
                </label>
                <textarea
                  rows={2}
                  value={leaveForm.reason}
                  onChange={(e) => setLeaveForm({ ...leaveForm, reason: e.target.value })}
                  placeholder="e.g. Doctor appointment, family function, urgent personal work..."
                  className="w-full px-3.5 py-2 text-xs border border-slate-300 rounded-xl focus:ring-2 focus:ring-orange-500 focus:outline-none resize-none"
                />
              </div>

              {/* Action Buttons */}
              <div className="flex items-center justify-end gap-2.5 pt-2 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition-colors cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting}
                  className="px-5 py-2 text-xs font-bold bg-orange-600 hover:bg-orange-700 text-white rounded-xl shadow-xs transition-colors cursor-pointer disabled:opacity-50"
                >
                  {submitting ? 'Recording...' : 'Submit & Apply Leave'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
