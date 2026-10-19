import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { 
  Settings as SettingsIcon, Plus, RefreshCw, Edit, Copy, 
  Power, Trash2, Clock, CheckCircle2, AlertTriangle, 
  RotateCcw, Sparkles, ShieldCheck, X, Check, Calendar, Users, Wrench
} from 'lucide-react';
import { API_BASE } from '../api/client';
import { useAuth } from '../context/AuthContext';
import UserManagement from '../components/UserManagement';

export default function Settings() {
  const { isAdmin } = useAuth();
  const [activeTab, setActiveTab] = useState('shifts'); // 'shifts', 'users', 'maintenance'
  const [shifts, setShifts] = useState([]);

  const [loadingShifts, setLoadingShifts] = useState(true);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('All');
  
  // Selected Shift for Rules Section
  const [selectedShiftId, setSelectedShiftId] = useState(null);
  const [shiftRules, setShiftRules] = useState({
    first_half_start_cutoff: '05:45:00',
    first_half_end_start: '06:00:00',
    first_half_end_end: '11:30:00',
    second_half_start_start: '12:30:00',
    second_half_start_end: '14:00:00',
    second_half_end_cutoff: '14:00:00'
  });
  const [savingRules, setSavingRules] = useState(false);

  // Modal: Add / Edit Shift
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingShiftId, setEditingShiftId] = useState(null);
  const [shiftForm, setShiftForm] = useState({
    code: '',
    name: '',
    start_time: '09:00',
    end_time: '17:00',
    break_start_time: '13:00',
    break_end_time: '13:30',
    first_half_start_cutoff: '08:45:00',
    first_half_end_start: '09:00:00',
    first_half_end_end: '13:00:00',
    second_half_start_start: '13:30:00',
    second_half_start_end: '15:00:00',
    second_half_end_cutoff: '17:00:00',
    grace_period_mins: 15,
    half_day_min_hours: 4.0,
    full_day_min_hours: 8.0,
    is_overnight: false,
    is_active: true,
    color: 'emerald'
  });

  const [savingShift, setSavingShift] = useState(false);
  const [recalculating, setRecalculating] = useState(false);
  const [seeding, setSeeding] = useState(false);
  const [clearing, setClearing] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const fetchShifts = async () => {
    setLoadingShifts(true);
    try {
      const res = await axios.get(`${API_BASE}/shifts/`, {
        params: {
          search: search || undefined,
          status: statusFilter !== 'All' ? statusFilter : undefined
        }
      });
      const data = res.data || [];
      setShifts(data);
      if (data.length > 0) {
        if (!selectedShiftId || !data.some(s => s.id === selectedShiftId)) {
          setSelectedShiftId(data[0].id);
          populateShiftRules(data[0]);
        } else {
          const current = data.find(s => s.id === selectedShiftId);
          if (current) populateShiftRules(current);
        }
      }
    } catch (err) {
      console.error('Failed to load shifts:', err);
    } finally {
      setLoadingShifts(false);
    }
  };

  const populateShiftRules = (s) => {
    setShiftRules({
      first_half_start_cutoff: s.first_half_start_cutoff || '08:45:00',
      first_half_end_start: s.first_half_end_start || '09:00:00',
      first_half_end_end: s.first_half_end_end || '13:00:00',
      second_half_start_start: s.second_half_start_start || '13:30:00',
      second_half_start_end: s.second_half_start_end || '15:00:00',
      second_half_end_cutoff: s.second_half_end_cutoff || '17:00:00'
    });
  };

  useEffect(() => {
    fetchShifts();
  }, [search, statusFilter]);

  const handleSelectShiftForRules = (e) => {
    const sId = Number(e.target.value);
    setSelectedShiftId(sId);
    const found = shifts.find(s => s.id === sId);
    if (found) {
      populateShiftRules(found);
    }
  };

  const handleUpdateRules = async (e) => {
    e.preventDefault();
    if (!selectedShiftId) return;
    setSavingRules(true);
    setMessage('');
    setError('');
    try {
      await axios.put(`${API_BASE}/shifts/${selectedShiftId}/rules`, shiftRules);
      setMessage(`Shift rules updated successfully for ${shifts.find(s => s.id === selectedShiftId)?.code}.`);
      fetchShifts();
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to update shift rules.');
    } finally {
      setSavingRules(false);
    }
  };

  // Open Modal for Add
  const handleOpenAddModal = () => {
    setEditingShiftId(null);
    setShiftForm({
      code: '',
      name: '',
      start_time: '09:00',
      end_time: '17:00',
      break_start_time: '13:00',
      break_end_time: '13:30',
      first_half_start_cutoff: '08:45:00',
      first_half_end_start: '09:00:00',
      first_half_end_end: '13:00:00',
      second_half_start_start: '13:30:00',
      second_half_start_end: '15:00:00',
      second_half_end_cutoff: '17:00:00',
      grace_period_mins: 15,
      half_day_min_hours: 4.0,
      full_day_min_hours: 8.0,
      is_overnight: false,
      is_active: true,
      color: 'emerald'
    });
    setError('');
    setIsModalOpen(true);
  };

  // Open Modal for Edit
  const handleOpenEditModal = (shift) => {
    setEditingShiftId(shift.id);
    setShiftForm({
      code: shift.code,
      name: shift.name,
      start_time: shift.start_time,
      end_time: shift.end_time,
      break_start_time: shift.break_start_time || '13:00',
      break_end_time: shift.break_end_time || '13:30',
      first_half_start_cutoff: shift.first_half_start_cutoff,
      first_half_end_start: shift.first_half_end_start,
      first_half_end_end: shift.first_half_end_end,
      second_half_start_start: shift.second_half_start_start,
      second_half_start_end: shift.second_half_start_end,
      second_half_end_cutoff: shift.second_half_end_cutoff,
      grace_period_mins: shift.grace_period_mins || 15,
      half_day_min_hours: shift.half_day_min_hours || 4.0,
      full_day_min_hours: shift.full_day_min_hours || 8.0,
      is_overnight: Boolean(shift.is_overnight),
      is_active: Boolean(shift.is_active),
      color: shift.color || 'emerald'
    });
    setError('');
    setIsModalOpen(true);
  };

  // Duplicate shift
  const handleDuplicateShift = (shift) => {
    setEditingShiftId(null);
    setShiftForm({
      code: `${shift.code}_COPY`,
      name: `${shift.name} (Copy)`,
      start_time: shift.start_time,
      end_time: shift.end_time,
      break_start_time: shift.break_start_time || '13:00',
      break_end_time: shift.break_end_time || '13:30',
      first_half_start_cutoff: shift.first_half_start_cutoff,
      first_half_end_start: shift.first_half_end_start,
      first_half_end_end: shift.first_half_end_end,
      second_half_start_start: shift.second_half_start_start,
      second_half_start_end: shift.second_half_start_end,
      second_half_end_cutoff: shift.second_half_end_cutoff,
      grace_period_mins: shift.grace_period_mins || 15,
      half_day_min_hours: shift.half_day_min_hours || 4.0,
      full_day_min_hours: shift.full_day_min_hours || 8.0,
      is_overnight: Boolean(shift.is_overnight),
      is_active: true,
      color: shift.color || 'blue'
    });
    setError('');
    setIsModalOpen(true);
  };

  // Toggle active/inactive
  const handleToggleStatus = async (shift) => {
    try {
      await axios.patch(`${API_BASE}/shifts/${shift.id}/status`, {
        is_active: !shift.is_active
      });
      fetchShifts();
    } catch (err) {
      alert('Failed to update status: ' + (err.response?.data?.detail || err.message));
    }
  };

  // Delete shift
  const handleDeleteShift = async (shift) => {
    if (!window.confirm(`Are you sure you want to delete shift '${shift.code} - ${shift.name}'?`)) return;
    try {
      await axios.delete(`${API_BASE}/shifts/${shift.id}`);
      setMessage(`Shift ${shift.code} deleted successfully.`);
      fetchShifts();
    } catch (err) {
      alert('Delete failed: ' + (err.response?.data?.detail || err.message));
    }
  };

  // Submit Shift Modal Form
  const handleSaveShift = async (e) => {
    e.preventDefault();
    setSavingShift(true);
    setError('');
    try {
      if (editingShiftId) {
        await axios.put(`${API_BASE}/shifts/${editingShiftId}`, shiftForm);
        setMessage(`Shift '${shiftForm.code}' updated successfully.`);
      } else {
        await axios.post(`${API_BASE}/shifts/`, shiftForm);
        setMessage(`New shift '${shiftForm.code}' created successfully.`);
      }
      setIsModalOpen(false);
      fetchShifts();
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to save shift.');
    } finally {
      setSavingShift(false);
    }
  };

  const handleRecalculateAll = async () => {
    if (!window.confirm("Recalculate all historical daily attendance records against their assigned shifts?")) return;
    setRecalculating(true);
    try {
      const res = await axios.post(`${API_BASE}/attendance/daily/recalculate`, {});
      alert(res.data.message);
    } catch (err) {
      alert('Recalculation error: ' + (err.response?.data?.detail || err.message));
    } finally {
      setRecalculating(false);
    }
  };

  const handleSeedDemo = async () => {
    if (!window.confirm("Seed demo dataset with 12 employees, 30 days of biometric punches and assigned shifts?")) return;
    setSeeding(true);
    try {
      const res = await axios.post(`${API_BASE}/settings/seed-demo`);
      alert(res.data.message);
      fetchShifts();
    } catch (err) {
      alert('Seeding error: ' + (err.response?.data?.detail || err.message));
    } finally {
      setSeeding(false);
    }
  };

  const handleClearData = async () => {
    if (!window.confirm("WARNING: Are you sure you want to clear all biometric punches and daily attendance logs? Employee profiles and shift master will be preserved.")) return;
    setClearing(true);
    try {
      const res = await axios.post(`${API_BASE}/settings/clear-data`);
      alert(res.data.message);
    } catch (err) {
      alert('Clear error: ' + (err.response?.data?.detail || err.message));
    } finally {
      setClearing(false);
    }
  };

  const currentSelectedShift = shifts.find(s => s.id === selectedShiftId);

  return (
    <div className="p-8 max-w-6xl mx-auto space-y-6 animate-in fade-in duration-200">
      
      {/* Settings Navigation Tabs */}
      <div className="flex flex-wrap items-center gap-2 border-b border-slate-200 pb-3">
        <button
          type="button"
          onClick={() => setActiveTab('shifts')}
          className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold transition-all cursor-pointer ${
            activeTab === 'shifts'
              ? 'bg-brand-600 text-white shadow-xs'
              : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100'
          }`}
        >
          <SettingsIcon size={15} />
          Shifts & Punch Windows
        </button>

        {isAdmin && (
          <button
            type="button"
            onClick={() => setActiveTab('users')}
            className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold transition-all cursor-pointer ${
              activeTab === 'users'
                ? 'bg-brand-600 text-white shadow-xs'
                : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100'
            }`}
          >
            <Users size={15} />
            User Management & 15-Day Policy
            <span className="px-1.5 py-0.2 rounded text-[9px] bg-orange-100 text-orange-700 font-extrabold uppercase">
              Admin
            </span>
          </button>
        )}

        <button
          type="button"
          onClick={() => setActiveTab('maintenance')}
          className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold transition-all cursor-pointer ${
            activeTab === 'maintenance'
              ? 'bg-brand-600 text-white shadow-xs'
              : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100'
          }`}
        >
          <Wrench size={15} />
          Engine Utilities
        </button>
      </div>

      {/* Tab Content: Users Management */}
      {activeTab === 'users' && isAdmin && (
        <UserManagement />
      )}

      {/* Tab Content: Shifts & Rules */}
      {activeTab === 'shifts' && (
        <>
          {/* 1. Shift Configuration Section */}
          <div className="space-y-6">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
              <div>
                <h1 className="text-2xl font-bold text-slate-900 tracking-tight">Shift Configuration</h1>
                <p className="text-slate-500 text-sm mt-0.5">Manage shift masters and attendance windows.</p>
              </div>

              <button
                type="button"
                onClick={handleOpenAddModal}
                className="flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-brand-600 hover:bg-brand-700 rounded-lg shadow-sm transition-all hover:scale-[1.01] active:scale-[0.99] self-start sm:self-auto"
              >
                <Plus size={16} />
                + Add Shift
              </button>
            </div>

            {message && (
              <div className="bg-emerald-50 border border-emerald-200 rounded-xl p-3.5 flex items-center gap-2 text-emerald-800 text-xs font-semibold">
                <CheckCircle2 size={16} className="text-emerald-600 shrink-0" />
                {message}
              </div>
            )}


        {/* Filter Bar */}
        <div className="bg-white p-4 rounded-xl border border-slate-200/80 shadow-xs flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-3 flex-1">
            <div className="relative min-w-[240px] max-w-sm">
              <input
                type="text"
                placeholder="Search shift code or name..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="w-full px-3 py-1.5 text-xs bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
              />
            </div>

            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="px-3 py-1.5 text-xs bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium text-slate-700"
            >
              <option value="All">All Statuses</option>
              <option value="Enabled">Enabled</option>
              <option value="Disabled">Disabled</option>
            </select>
          </div>

          <button
            type="button"
            onClick={fetchShifts}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-slate-700 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors"
          >
            <RefreshCw size={14} className={loadingShifts ? "animate-spin" : ""} />
            Refresh
          </button>
        </div>

        {/* Shift Table */}
        <div className="bg-white rounded-xl border border-slate-200/80 shadow-sm overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs border-collapse">
              <thead>
                <tr className="bg-slate-50 border-b border-slate-200 text-slate-600 font-semibold uppercase tracking-wider">
                  <th className="p-3.5">SHIFT CODE</th>
                  <th className="p-3.5">SHIFT NAME</th>
                  <th className="p-3.5">START TIME</th>
                  <th className="p-3.5">END TIME</th>
                  <th className="p-3.5">BREAK</th>
                  <th className="p-3.5">STATUS</th>
                  <th className="p-3.5 text-right">ACTIONS</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {loadingShifts ? (
                  <tr>
                    <td colSpan="7" className="p-8 text-center text-slate-400">Loading shift masters...</td>
                  </tr>
                ) : shifts.length === 0 ? (
                  <tr>
                    <td colSpan="7" className="p-8 text-center text-slate-400">
                      No shifts found. Click "+ Add Shift" above to configure your first shift.
                    </td>
                  </tr>
                ) : (
                  shifts.map(shift => {
                    const isEnabled = shift.is_active;
                    const breakDisplay = (shift.break_start_time && shift.break_end_time) 
                      ? `${shift.break_start_time} - ${shift.break_end_time}` 
                      : '—';

                    return (
                      <tr key={shift.id} className="hover:bg-slate-50/70 transition-colors">
                        <td className="p-3.5 font-bold font-mono text-slate-900">
                          <span className="flex items-center gap-1.5">
                            {shift.code}
                            {shift.is_overnight && (
                              <span className="px-1.5 py-0.5 rounded text-[9px] font-bold bg-purple-50 text-purple-700 border border-purple-200">
                                Overnight
                              </span>
                            )}
                          </span>
                        </td>
                        <td className="p-3.5 font-medium text-slate-800">
                          {shift.name}
                        </td>
                        <td className="p-3.5 font-mono text-slate-600">
                          {shift.start_time}
                        </td>
                        <td className="p-3.5 font-mono text-slate-600">
                          {shift.end_time}
                        </td>
                        <td className="p-3.5 font-mono text-slate-500">
                          {breakDisplay}
                        </td>
                        <td className="p-3.5">
                          <span className={`inline-flex px-2 py-0.5 rounded-full text-[11px] font-semibold border ${
                            isEnabled 
                              ? 'bg-emerald-50 text-emerald-700 border-emerald-200' 
                              : 'bg-slate-100 text-slate-500 border-slate-200'
                          }`}>
                            {isEnabled ? 'Enabled' : 'Disabled'}
                          </span>
                        </td>
                        <td className="p-3.5 text-right">
                          <div className="inline-flex items-center gap-1">
                            <button
                              type="button"
                              onClick={() => handleOpenEditModal(shift)}
                              className="p-1.5 text-slate-400 hover:text-slate-800 hover:bg-slate-100 rounded-md transition-colors"
                              title="Edit Shift"
                            >
                              <Edit size={14} />
                            </button>
                            <button
                              type="button"
                              onClick={() => handleDuplicateShift(shift)}
                              className="p-1.5 text-slate-400 hover:text-brand-600 hover:bg-brand-50 rounded-md transition-colors"
                              title="Duplicate Shift"
                            >
                              <Copy size={14} />
                            </button>
                            <button
                              type="button"
                              onClick={() => handleToggleStatus(shift)}
                              className={`p-1.5 rounded-md transition-colors ${
                                isEnabled 
                                  ? 'text-slate-400 hover:text-rose-600 hover:bg-rose-50' 
                                  : 'text-slate-400 hover:text-emerald-600 hover:bg-emerald-50'
                              }`}
                              title={isEnabled ? "Deactivate Shift" : "Activate Shift"}
                            >
                              <Power size={14} />
                            </button>
                            <button
                              type="button"
                              onClick={() => handleDeleteShift(shift)}
                              className="p-1.5 text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded-md transition-colors"
                              title="Delete Shift"
                            >
                              <Trash2 size={14} />
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
      </div>

      {/* 2. Shift Rules (Time Windows) Section */}
      <div className="bg-white rounded-xl border border-slate-200/80 shadow-sm overflow-hidden">
        <div className="p-5 border-b border-slate-100 bg-slate-50/70 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-base font-bold text-slate-900">Shift Rules (Time Windows)</h2>
            <p className="text-xs text-slate-500 mt-0.5">Configure attendance time windows for each half of the shift.</p>
          </div>

          <div className="flex items-center gap-2 text-xs">
            <span className="font-semibold text-slate-600">Selected Shift:</span>
            <select
              value={selectedShiftId || ''}
              onChange={handleSelectShiftForRules}
              className="px-3 py-1.5 font-semibold bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 text-slate-800 shadow-2xs"
            >
              {shifts.map(s => (
                <option key={s.id} value={s.id}>{s.code} - {s.name}</option>
              ))}
            </select>
          </div>
        </div>

        <form onSubmit={handleUpdateRules} className="p-6 space-y-6 text-xs">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            
            {/* 1. FIRST HALF START */}
            <div className="p-4 bg-slate-50/70 rounded-xl border border-slate-200 space-y-2">
              <div className="flex items-center justify-between">
                <span className="font-bold text-slate-900">1. FIRST HALF START</span>
                <span className="text-[10px] uppercase font-bold px-2 py-0.5 bg-blue-50 text-blue-700 rounded border border-blue-200">
                  THROUGH CHECK-IN
                </span>
              </div>
              <label className="block text-[11px] text-slate-500">Allowed Time (HH:MM:SS)</label>
              <input
                type="text"
                value={shiftRules.first_half_start_cutoff}
                onChange={(e) => setShiftRules({ ...shiftRules, first_half_start_cutoff: e.target.value })}
                placeholder="05:45:00"
                className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono text-xs"
              />
              <span className="text-[11px] text-slate-500 block">
                Employees can check-in from <span className="font-semibold text-slate-700">{shiftRules.first_half_start_cutoff}</span> for First Half Start.
              </span>
            </div>

            {/* 2. FIRST HALF END */}
            <div className="p-4 bg-slate-50/70 rounded-xl border border-slate-200 space-y-2">
              <div className="flex items-center justify-between">
                <span className="font-bold text-slate-900">2. FIRST HALF END</span>
                <span className="text-[10px] uppercase font-bold px-2 py-0.5 bg-emerald-50 text-emerald-700 rounded border border-emerald-200">
                  WINDOW (INCLUSIVE)
                </span>
              </div>
              <label className="block text-[11px] text-slate-500">Time Range (HH:MM:SS)</label>
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={shiftRules.first_half_end_start}
                  onChange={(e) => setShiftRules({ ...shiftRules, first_half_end_start: e.target.value })}
                  placeholder="06:00:00"
                  className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono text-xs"
                />
                <span className="text-slate-400 font-bold">:</span>
                <input
                  type="text"
                  value={shiftRules.first_half_end_end}
                  onChange={(e) => setShiftRules({ ...shiftRules, first_half_end_end: e.target.value })}
                  placeholder="11:30:00"
                  className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono text-xs"
                />
              </div>
              <span className="text-[11px] text-slate-500 block">
                First half working window: <span className="font-semibold text-slate-700">{shiftRules.first_half_end_start}</span> through <span className="font-semibold text-slate-700">{shiftRules.first_half_end_end}</span>.
              </span>
            </div>

            {/* 3. SECOND HALF START */}
            <div className="p-4 bg-slate-50/70 rounded-xl border border-slate-200 space-y-2">
              <div className="flex items-center justify-between">
                <span className="font-bold text-slate-900">3. SECOND HALF START</span>
                <span className="text-[10px] uppercase font-bold px-2 py-0.5 bg-emerald-50 text-emerald-700 rounded border border-emerald-200">
                  WINDOW (INCLUSIVE)
                </span>
              </div>
              <label className="block text-[11px] text-slate-500">Time Range (HH:MM:SS)</label>
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={shiftRules.second_half_start_start}
                  onChange={(e) => setShiftRules({ ...shiftRules, second_half_start_start: e.target.value })}
                  placeholder="12:30:00"
                  className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono text-xs"
                />
                <span className="text-slate-400 font-bold">:</span>
                <input
                  type="text"
                  value={shiftRules.second_half_start_end}
                  onChange={(e) => setShiftRules({ ...shiftRules, second_half_start_end: e.target.value })}
                  placeholder="14:00:00"
                  className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono text-xs"
                />
              </div>
              <span className="text-[11px] text-slate-500 block">
                Second half working window: <span className="font-semibold text-slate-700">{shiftRules.second_half_start_start}</span> through <span className="font-semibold text-slate-700">{shiftRules.second_half_start_end}</span>.
              </span>
            </div>

            {/* 4. SECOND HALF END */}
            <div className="p-4 bg-slate-50/70 rounded-xl border border-slate-200 space-y-2">
              <div className="flex items-center justify-between">
                <span className="font-bold text-slate-900">4. SECOND HALF END</span>
                <span className="text-[10px] uppercase font-bold px-2 py-0.5 bg-purple-50 text-purple-700 rounded border border-purple-200">
                  STRICTLY AFTER
                </span>
              </div>
              <label className="block text-[11px] text-slate-500">Allowed Time (HH:MM:SS)</label>
              <input
                type="text"
                value={shiftRules.second_half_end_cutoff}
                onChange={(e) => setShiftRules({ ...shiftRules, second_half_end_cutoff: e.target.value })}
                placeholder="14:00:00"
                className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono text-xs"
              />
              <span className="text-[11px] text-slate-500 block">
                Employees can check-out after <span className="font-semibold text-slate-700">{shiftRules.second_half_end_cutoff}</span> for Second Half End.
              </span>
            </div>
          </div>

          <div className="flex justify-end pt-2">
            <button
              type="submit"
              disabled={savingRules}
              className="flex items-center gap-1.5 px-5 py-2.5 text-xs font-semibold text-white bg-brand-600 hover:bg-brand-700 rounded-lg shadow-sm transition-colors disabled:opacity-50"
            >
              <SettingsIcon size={14} />
              {savingRules ? 'Updating Rules...' : 'Update Rules'}
            </button>
          </div>
        </form>
      </div>
        </>
      )}

      {/* Tab Content: Maintenance Utilities */}
      {activeTab === 'maintenance' && (
        <div className="bg-white rounded-2xl border border-slate-200/80 shadow-xs p-6 space-y-4">
          <h3 className="font-bold text-sm text-slate-900 flex items-center gap-2">
            <RotateCcw size={16} className="text-brand-600" />
            Attendance Engine Utilities
          </h3>
          <p className="text-xs text-slate-500 leading-relaxed">
            Recalculate attendance records across historical dates using currently assigned employee shifts and their updated punch windows.
          </p>

          <div className="flex flex-wrap items-center gap-3 pt-2">
            <button
              type="button"
              onClick={handleRecalculateAll}
              disabled={recalculating}
              className="flex items-center gap-1.5 px-4 py-2 text-xs font-semibold text-slate-700 bg-slate-100 hover:bg-slate-200 rounded-lg border border-slate-300 transition-colors cursor-pointer"
            >
              <RefreshCw size={14} className={recalculating ? "animate-spin" : ""} />
              {recalculating ? 'Recalculating...' : 'Recalculate All Historical Attendance'}
            </button>

            <button
              type="button"
              onClick={handleSeedDemo}
              disabled={seeding}
              className="flex items-center gap-1.5 px-4 py-2 text-xs font-semibold text-brand-700 bg-brand-50 hover:bg-brand-100 rounded-lg border border-brand-200 transition-colors cursor-pointer"
            >
              <Sparkles size={14} />
              {seeding ? 'Seeding...' : 'Seed Demo Data (EMP101-EMP112)'}
            </button>

            <button
              type="button"
              onClick={handleClearData}
              disabled={clearing}
              className="flex items-center gap-1.5 px-4 py-2 text-xs font-semibold text-rose-700 bg-rose-50 hover:bg-rose-100 rounded-lg border border-rose-200 transition-colors ml-auto cursor-pointer"
            >
              <Trash2 size={14} />
              Clear Attendance Calculations
            </button>
          </div>
        </div>
      )}


      {/* 4. Add / Edit Shift Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 bg-slate-900/50 backdrop-blur-xs flex items-center justify-center p-4 overflow-y-auto">
          <div className="bg-white rounded-2xl shadow-2xl max-w-2xl w-full border border-slate-200 overflow-hidden my-auto animate-in zoom-in-95 duration-150">
            <div className="p-5 border-b border-slate-100 bg-slate-50 flex items-center justify-between">
              <div>
                <h3 className="font-bold text-slate-900 text-base">
                  {editingShiftId ? 'Edit Shift Configuration' : 'Create New Shift'}
                </h3>
                <p className="text-xs text-slate-500 mt-0.5">Define shift timings, punch cutoffs, and rules.</p>
              </div>
              <button 
                onClick={() => setIsModalOpen(false)}
                className="text-slate-400 hover:text-slate-600 p-1"
              >
                <X size={18} />
              </button>
            </div>

            <form onSubmit={handleSaveShift} className="p-6 space-y-5 text-xs max-h-[75vh] overflow-y-auto">
              {error && (
                <div className="p-3 bg-rose-50 border border-rose-200 rounded-lg text-rose-800 text-xs font-semibold flex items-center gap-2">
                  <AlertTriangle size={15} className="text-rose-600 shrink-0" />
                  {error}
                </div>
              )}

              {/* Basic Fields */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Shift Code *</label>
                  <input
                    type="text"
                    required
                    placeholder="e.g. S5"
                    value={shiftForm.code}
                    onChange={(e) => setShiftForm({ ...shiftForm, code: e.target.value.toUpperCase() })}
                    className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono font-bold"
                  />
                </div>

                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Shift Name *</label>
                  <input
                    type="text"
                    required
                    placeholder="e.g. Rotational Shift"
                    value={shiftForm.name}
                    onChange={(e) => setShiftForm({ ...shiftForm, name: e.target.value })}
                    className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium"
                  />
                </div>
              </div>

              {/* Start & End Times */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Start Time (HH:MM) *</label>
                  <input
                    type="text"
                    required
                    placeholder="09:00"
                    value={shiftForm.start_time}
                    onChange={(e) => setShiftForm({ ...shiftForm, start_time: e.target.value })}
                    className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono"
                  />
                </div>

                <div>
                  <label className="block font-semibold text-slate-700 mb-1">End Time (HH:MM) *</label>
                  <input
                    type="text"
                    required
                    placeholder="17:00"
                    value={shiftForm.end_time}
                    onChange={(e) => setShiftForm({ ...shiftForm, end_time: e.target.value })}
                    className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono"
                  />
                </div>
              </div>

              {/* Break Timings */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Break Start Time</label>
                  <input
                    type="text"
                    placeholder="13:00"
                    value={shiftForm.break_start_time}
                    onChange={(e) => setShiftForm({ ...shiftForm, break_start_time: e.target.value })}
                    className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono"
                  />
                </div>

                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Break End Time</label>
                  <input
                    type="text"
                    placeholder="13:30"
                    value={shiftForm.break_end_time}
                    onChange={(e) => setShiftForm({ ...shiftForm, break_end_time: e.target.value })}
                    className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono"
                  />
                </div>
              </div>

              {/* Toggles & Color */}
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 pt-1">
                <div>
                  <label className="block font-semibold text-slate-700 mb-1.5">Color Badge</label>
                  <select
                    value={shiftForm.color}
                    onChange={(e) => setShiftForm({ ...shiftForm, color: e.target.value })}
                    className="w-full p-2.5 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium"
                  >
                    <option value="emerald">Emerald (Green)</option>
                    <option value="blue">Blue (Standard)</option>
                    <option value="amber">Amber (Orange)</option>
                    <option value="purple">Purple (Night)</option>
                    <option value="rose">Rose (Red)</option>
                    <option value="indigo">Indigo</option>
                  </select>
                </div>

                <div className="flex items-center gap-2 pt-6">
                  <input
                    type="checkbox"
                    id="is_overnight"
                    checked={shiftForm.is_overnight}
                    onChange={(e) => setShiftForm({ ...shiftForm, is_overnight: e.target.checked })}
                    className="w-4 h-4 text-brand-600 rounded border-slate-300 focus:ring-brand-500"
                  />
                  <label htmlFor="is_overnight" className="font-semibold text-slate-800 cursor-pointer">
                    Overnight Shift (crosses midnight)
                  </label>
                </div>

                <div className="flex items-center gap-2 pt-6">
                  <input
                    type="checkbox"
                    id="is_active"
                    checked={shiftForm.is_active}
                    onChange={(e) => setShiftForm({ ...shiftForm, is_active: e.target.checked })}
                    className="w-4 h-4 text-brand-600 rounded border-slate-300 focus:ring-brand-500"
                  />
                  <label htmlFor="is_active" className="font-semibold text-slate-800 cursor-pointer">
                    Active / Enabled
                  </label>
                </div>
              </div>

              {/* Advanced Windows Accordion Header */}
              <div className="pt-2 border-t border-slate-200">
                <span className="font-bold text-slate-800 block mb-2">Punch Windows & Boundary Cutoffs:</span>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-[11px] font-semibold text-slate-600 mb-1">1st Half Check-In Cutoff</label>
                    <input
                      type="text"
                      value={shiftForm.first_half_start_cutoff}
                      onChange={(e) => setShiftForm({ ...shiftForm, first_half_start_cutoff: e.target.value })}
                      className="w-full p-2 bg-slate-50 border border-slate-300 rounded-lg font-mono text-xs"
                    />
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-slate-600 mb-1">1st Half End Range (Start - End)</label>
                    <div className="flex items-center gap-1">
                      <input
                        type="text"
                        value={shiftForm.first_half_end_start}
                        onChange={(e) => setShiftForm({ ...shiftForm, first_half_end_start: e.target.value })}
                        className="w-full p-2 bg-slate-50 border border-slate-300 rounded-lg font-mono text-xs"
                      />
                      <input
                        type="text"
                        value={shiftForm.first_half_end_end}
                        onChange={(e) => setShiftForm({ ...shiftForm, first_half_end_end: e.target.value })}
                        className="w-full p-2 bg-slate-50 border border-slate-300 rounded-lg font-mono text-xs"
                      />
                    </div>
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-slate-600 mb-1">2nd Half Start Range (Start - End)</label>
                    <div className="flex items-center gap-1">
                      <input
                        type="text"
                        value={shiftForm.second_half_start_start}
                        onChange={(e) => setShiftForm({ ...shiftForm, second_half_start_start: e.target.value })}
                        className="w-full p-2 bg-slate-50 border border-slate-300 rounded-lg font-mono text-xs"
                      />
                      <input
                        type="text"
                        value={shiftForm.second_half_start_end}
                        onChange={(e) => setShiftForm({ ...shiftForm, second_half_start_end: e.target.value })}
                        className="w-full p-2 bg-slate-50 border border-slate-300 rounded-lg font-mono text-xs"
                      />
                    </div>
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-slate-600 mb-1">2nd Half End Checkout Cutoff</label>
                    <input
                      type="text"
                      value={shiftForm.second_half_end_cutoff}
                      onChange={(e) => setShiftForm({ ...shiftForm, second_half_end_cutoff: e.target.value })}
                      className="w-full p-2 bg-slate-50 border border-slate-300 rounded-lg font-mono text-xs"
                    />
                  </div>
                </div>
              </div>

              {/* Footer */}
              <div className="pt-4 border-t border-slate-100 flex items-center justify-end gap-2.5">
                <button
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  className="px-4 py-2 border border-slate-200 rounded-lg text-slate-600 hover:bg-slate-50 font-semibold"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={savingShift}
                  className="px-5 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg font-semibold shadow-sm transition-colors"
                >
                  {savingShift ? 'Saving...' : (editingShiftId ? 'Save Changes' : 'Create Shift')}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

    </div>
  );
}
