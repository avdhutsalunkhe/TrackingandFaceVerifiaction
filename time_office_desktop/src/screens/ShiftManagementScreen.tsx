import React, { useState, useEffect } from 'react';
import { api } from '../services/api';
import {
  Clock,
  Plus,
  Search,
  Edit2,
  Copy,
  Trash2,
  UserPlus,
  RefreshCw,
  ChevronDown,
  ChevronUp,
  Shield,
  Layers,
  X,
  AlertTriangle,
} from 'lucide-react';

interface ShiftRule {
  id?: number;
  rule_code?: string;
  rule_name?: string;
  period_name?: string;
  punch_no?: number;
  verification_no?: number;
  start_time: string;
  end_time: string;
  result_code?: string;
  result_classification?: string;
  priority?: number;
  require_face_verification?: boolean;
  show_in_user_schedule?: boolean;
  is_active?: boolean;
}

interface ShiftItem {
  id: number;
  shift_code: string;
  shift_name: string;
  description?: string;
  is_active: boolean;
  punch_periods?: ShiftRule[];
  rules?: ShiftRule[];
  created_at?: string;
  updated_at?: string;
}

interface EmployeeItem {
  id: number;
  employee_id: string;
  full_name: string;
  department?: string;
}

export const ShiftManagementScreen: React.FC = () => {
  const [shifts, setShifts] = useState<ShiftItem[]>([]);
  const [employees, setEmployees] = useState<EmployeeItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [expandedShiftId, setExpandedShiftId] = useState<number | null>(null);

  // Modals state
  const [isShiftModalOpen, setIsShiftModalOpen] = useState(false);
  const [editingShift, setEditingShift] = useState<ShiftItem | null>(null);

  const [isDuplicateModalOpen, setIsDuplicateModalOpen] = useState(false);
  const [duplicateTarget, setDuplicateTarget] = useState<ShiftItem | null>(null);
  const [dupCode, setDupCode] = useState('');
  const [dupName, setDupName] = useState('');

  const [isAssignModalOpen, setIsAssignModalOpen] = useState(false);
  const [assignUser, setAssignUser] = useState<string>('');
  const [assignShiftId, setAssignShiftId] = useState<number | null>(null);
  const [effectiveFrom, setEffectiveFrom] = useState(new Date().toISOString().split('T')[0]);
  const [effectiveTo, setEffectiveTo] = useState('');
  const [assignHistory, setAssignHistory] = useState<any[]>([]);

  // Shift Form state
  const [formCode, setFormCode] = useState('');
  const [formName, setFormName] = useState('');
  const [formDescription, setFormDescription] = useState('');
  const [formIsActive, setFormIsActive] = useState(true);
  const [formRules, setFormRules] = useState<ShiftRule[]>([
    {
      period_name: 'Shift Window 1',
      punch_no: 1,
      start_time: '09:00:00',
      end_time: '18:00:00',
      result_code: 'ON_TIME',
      priority: 1,
      require_face_verification: true,
      show_in_user_schedule: true,
      is_active: true,
    },
  ]);
  const [formError, setFormError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    loadShifts();
    loadEmployees();
  }, []);

  const loadShifts = async () => {
    setLoading(true);
    try {
      const data = await api.getAdminShifts();
      setShifts(data);
      if (data.length > 0 && expandedShiftId === null) {
        setExpandedShiftId(data[0].id);
      }
    } catch (err) {
      console.error('Failed to load shifts', err);
    } finally {
      setLoading(false);
    }
  };

  const loadEmployees = async () => {
    try {
      const res = await api.getEmployees({ page_size: 200 });
      setEmployees(res.records || []);
    } catch (err) {
      console.error('Failed to load employees', err);
    }
  };

  const openCreateModal = () => {
    setEditingShift(null);
    setFormCode(`S${String(shifts.length + 1).padStart(3, '0')}`);
    setFormName('Regular Shift');
    setFormDescription('Standard office shift hours');
    setFormIsActive(true);
    setFormRules([
      {
        period_name: 'Regular In-Punch Window',
        punch_no: 1,
        start_time: '08:30:00',
        end_time: '09:15:00',
        result_code: 'ON_TIME',
        priority: 1,
        require_face_verification: true,
        show_in_user_schedule: true,
        is_active: true,
      },
      {
        period_name: 'Late In-Punch Window',
        punch_no: 1,
        start_time: '09:15:01',
        end_time: '10:00:00',
        result_code: 'LATE',
        priority: 2,
        require_face_verification: true,
        show_in_user_schedule: true,
        is_active: true,
      },
      {
        period_name: 'Out-Punch Window',
        punch_no: 2,
        start_time: '18:00:00',
        end_time: '20:00:00',
        result_code: 'OUT_PUNCH',
        priority: 3,
        require_face_verification: true,
        show_in_user_schedule: true,
        is_active: true,
      },
    ]);
    setFormError(null);
    setIsShiftModalOpen(true);
  };

  const openEditModal = (shift: ShiftItem) => {
    setEditingShift(shift);
    setFormCode(shift.shift_code);
    setFormName(shift.shift_name);
    setFormDescription(shift.description || '');
    setFormIsActive(shift.is_active);

    const rules = shift.punch_periods || shift.rules || [];
    setFormRules(
      rules.map((r) => ({
        id: r.id,
        period_name: r.period_name || r.rule_name || `Punch #${r.punch_no || 1}`,
        punch_no: r.punch_no || r.verification_no || 1,
        start_time: r.start_time,
        end_time: r.end_time,
        result_code: r.result_code || 'ON_TIME',
        priority: r.priority || 1,
        require_face_verification: r.require_face_verification ?? true,
        show_in_user_schedule: r.show_in_user_schedule ?? true,
        is_active: r.is_active ?? true,
      }))
    );
    setFormError(null);
    setIsShiftModalOpen(true);
  };

  const handleAddRuleRow = () => {
    setFormRules((prev) => [
      ...prev,
      {
        period_name: `Window ${prev.length + 1}`,
        punch_no: 1,
        start_time: '10:00:01',
        end_time: '12:00:00',
        result_code: 'HALF_DAY',
        priority: prev.length + 1,
        require_face_verification: true,
        show_in_user_schedule: true,
        is_active: true,
      },
    ]);
  };

  const handleRemoveRuleRow = (index: number) => {
    setFormRules((prev) => prev.filter((_, i) => i !== index));
  };

  const handleRuleChange = (index: number, field: keyof ShiftRule, val: any) => {
    setFormRules((prev) => {
      const updated = [...prev];
      updated[index] = { ...updated[index], [field]: val };
      return updated;
    });
  };

  const handleSaveShift = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formCode.trim() || !formName.trim()) {
      setFormError('Shift Code and Shift Name are required.');
      return;
    }
    if (formRules.length === 0) {
      setFormError('At least one punch rule/window is required.');
      return;
    }

    setSubmitting(true);
    setFormError(null);
    try {
      const payload = {
        shift_code: formCode.trim().toUpperCase(),
        shift_name: formName.trim(),
        description: formDescription.trim(),
        is_active: formIsActive,
        rules: formRules,
      };

      if (editingShift) {
        await api.updateShift(editingShift.id, payload);
      } else {
        await api.createShift(payload);
      }
      setIsShiftModalOpen(false);
      loadShifts();
    } catch (err: any) {
      setFormError(err?.response?.data?.detail || err.message || 'Failed to save shift.');
    } finally {
      setSubmitting(false);
    }
  };

  const openDuplicateModal = (shift: ShiftItem) => {
    setDuplicateTarget(shift);
    setDupCode(`${shift.shift_code}_COPY`);
    setDupName(`${shift.shift_name} (Copy)`);
    setIsDuplicateModalOpen(true);
  };

  const handleDuplicate = async () => {
    if (!duplicateTarget || !dupCode.trim() || !dupName.trim()) return;
    setSubmitting(true);
    try {
      await api.duplicateShift(duplicateTarget.id, dupCode.trim().toUpperCase(), dupName.trim());
      setIsDuplicateModalOpen(false);
      loadShifts();
    } catch (err: any) {
      alert(err?.response?.data?.detail || 'Failed to duplicate shift.');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteShift = async (shift: ShiftItem) => {
    if (!confirm(`Are you sure you want to delete/deactivate shift "${shift.shift_name}" (${shift.shift_code})?`)) {
      return;
    }
    try {
      await api.deleteShift(shift.id);
      loadShifts();
    } catch (err: any) {
      alert(err?.response?.data?.detail || 'Failed to delete shift.');
    }
  };

  const openAssignModal = (shift?: ShiftItem) => {
    if (shift) setAssignShiftId(shift.id);
    else if (shifts.length > 0) setAssignShiftId(shifts[0].id);
    if (employees.length > 0) {
      const emp = employees[0];
      setAssignUser(String(emp.id));
      fetchUserHistory(emp.id);
    }
    setIsAssignModalOpen(true);
  };

  const fetchUserHistory = async (userId: number) => {
    const history = await api.getUserShiftHistory(userId);
    setAssignHistory(history);
  };

  const handleAssignShiftSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!assignUser || !assignShiftId) return;

    setSubmitting(true);
    try {
      await api.assignShift({
        user_id: Number(assignUser),
        shift_id: assignShiftId,
        effective_from: effectiveFrom,
        effective_to: effectiveTo ? effectiveTo : null,
      });
      alert('Shift assigned successfully!');
      fetchUserHistory(Number(assignUser));
    } catch (err: any) {
      alert(err?.response?.data?.detail || 'Failed to assign shift.');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteAssignment = async (assignmentId: number) => {
    if (!confirm('Remove this shift assignment record?')) return;
    try {
      await api.deleteShiftAssignment(assignmentId);
      if (assignUser) fetchUserHistory(Number(assignUser));
    } catch (err: any) {
      alert(err?.response?.data?.detail || 'Failed to remove assignment.');
    }
  };

  const filteredShifts = shifts.filter(
    (s) =>
      s.shift_code.toLowerCase().includes(search.toLowerCase()) ||
      s.shift_name.toLowerCase().includes(search.toLowerCase())
  );

  const getResultBadgeColor = (code?: string) => {
    switch (code) {
      case 'ON_TIME':
        return 'bg-emerald-50 text-emerald-700 border-emerald-200';
      case 'LATE':
        return 'bg-[#fff2e8] text-[#ea4e00] border-[#ffd8bf]';
      case 'HALF_DAY':
        return 'bg-amber-50 text-amber-800 border-amber-200';
      case 'AFTERNOON_PUNCH':
      case 'SECOND_HALF':
        return 'bg-purple-50 text-purple-700 border-purple-200';
      case 'OUT_PUNCH':
        return 'bg-blue-50 text-blue-700 border-blue-200';
      default:
        return 'bg-slate-100 text-slate-700 border-slate-200';
    }
  };

  return (
    <div className="space-y-5 font-sans text-slate-800">
      {/* Top Title Banner */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-white p-5 rounded-2xl border border-slate-200/90 shadow-sm">
        <div className="flex items-center gap-3.5">
          <div className="w-11 h-11 rounded-xl bg-[#f95700] text-white flex items-center justify-center shadow-md shadow-orange-500/20 shrink-0">
            <Layers className="w-6 h-6 stroke-[2.2]" />
          </div>
          <div>
            <h1 className="text-xl font-extrabold text-slate-900 tracking-tight">Shift Rules & Management</h1>
            <p className="text-xs text-slate-500 mt-0.5 font-medium">
              Configure shift schedules, non-overlapping attendance windows & assign rules
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2.5">
          <button
            onClick={openCreateModal}
            className="flex items-center gap-2 px-4 py-2.5 bg-[#f95700] hover:bg-[#ea4e00] text-white text-xs font-bold rounded-xl transition-all shadow-md shadow-orange-500/20"
          >
            <Plus className="w-4 h-4 stroke-[2.5]" />
            <span>Create New Shift</span>
          </button>
          <button
            onClick={() => openAssignModal()}
            className="flex items-center gap-2 px-4 py-2.5 bg-white hover:bg-slate-50 text-slate-700 border border-slate-300 text-xs font-semibold rounded-xl transition-all shadow-sm"
          >
            <UserPlus className="w-4 h-4 text-[#f95700]" />
            <span>Assign Shift</span>
          </button>
          <button
            onClick={loadShifts}
            className="p-2.5 bg-white hover:bg-slate-50 text-slate-600 rounded-xl border border-slate-300 transition-colors shadow-sm"
            title="Refresh list"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      {/* Search and Counter Bar */}
      <div className="flex items-center justify-between gap-4 bg-white px-5 py-3.5 rounded-2xl border border-slate-200/90 shadow-sm">
        <div className="relative flex-1 max-w-md">
          <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            type="text"
            placeholder="Search shift code or name..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full bg-slate-50 border border-slate-200 rounded-xl pl-9 pr-4 py-2 text-xs text-slate-900 placeholder:text-slate-400 focus:outline-none focus:bg-white focus:border-[#f95700] transition-colors"
          />
        </div>
        <div className="text-xs text-slate-500 font-medium">
          Configured Shifts: <strong className="text-slate-900 font-mono text-sm">{shifts.length}</strong>
        </div>
      </div>

      {/* Shifts Accordion List */}
      {loading ? (
        <div className="flex flex-col items-center justify-center p-16 gap-3 bg-white rounded-2xl border border-slate-200/90 shadow-sm">
          <div className="w-8 h-8 border-2 border-[#f95700] border-t-transparent rounded-full animate-spin" />
          <span className="text-xs font-mono text-slate-500 uppercase tracking-wider">Loading Shifts...</span>
        </div>
      ) : filteredShifts.length === 0 ? (
        <div className="text-center p-12 bg-white rounded-2xl border border-slate-200/90 space-y-4 shadow-sm">
          <Clock className="w-12 h-12 text-slate-400 mx-auto stroke-[1.5]" />
          <div className="text-slate-800 font-bold text-sm">No Shifts Found</div>
          <p className="text-xs text-slate-500 max-w-sm mx-auto">
            No matching shift definitions found. Click below to create a new shift.
          </p>
          <button
            onClick={openCreateModal}
            className="px-4 py-2 bg-[#f95700] text-white text-xs font-bold rounded-xl shadow-md hover:bg-[#ea4e00] transition-colors"
          >
            Create Shift (e.g. S001)
          </button>
        </div>
      ) : (
        <div className="space-y-3.5">
          {filteredShifts.map((shift) => {
            const isExpanded = expandedShiftId === shift.id;
            const rules = shift.punch_periods || shift.rules || [];

            return (
              <div
                key={shift.id}
                className="bg-white border border-slate-200/90 rounded-2xl overflow-hidden transition-all shadow-sm hover:shadow-md"
              >
                {/* Header Row */}
                <div className="p-4 flex items-center justify-between gap-4 select-none">
                  <div
                    onClick={() => setExpandedShiftId(isExpanded ? null : shift.id)}
                    className="flex items-center gap-4 flex-1 cursor-pointer"
                  >
                    {/* Small Dark Code Badge */}
                    <div className="px-3 py-1.5 bg-[#111622] text-[#f95700] rounded-xl text-xs font-extrabold font-mono tracking-wider border border-slate-800 shadow-sm">
                      {shift.shift_code}
                    </div>
                    <div>
                      <div className="text-sm font-bold text-slate-900 flex items-center gap-2.5">
                        <span>{shift.shift_name}</span>
                        <span
                          className={`text-[10px] px-2.5 py-0.5 rounded-full font-bold uppercase ${
                            shift.is_active
                              ? 'bg-emerald-50 text-emerald-700 border border-emerald-200'
                              : 'bg-rose-50 text-rose-700 border border-rose-200'
                          }`}
                        >
                          {shift.is_active ? 'Active' : 'Inactive'}
                        </span>
                      </div>
                      <div className="text-xs text-slate-500 font-medium mt-0.5">
                        {rules.length} Dynamic Rules & Punch Windows
                        {shift.description ? ` • ${shift.description}` : ''}
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center gap-1.5">
                    <button
                      onClick={() => openAssignModal(shift)}
                      className="p-2 text-slate-500 hover:text-[#f95700] hover:bg-orange-50 rounded-xl transition-colors"
                      title="Assign Shift to Employee"
                    >
                      <UserPlus className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => openEditModal(shift)}
                      className="p-2 text-slate-500 hover:text-slate-900 hover:bg-slate-100 rounded-xl transition-colors"
                      title="Edit Shift & Rules"
                    >
                      <Edit2 className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => openDuplicateModal(shift)}
                      className="p-2 text-slate-500 hover:text-blue-600 hover:bg-blue-50 rounded-xl transition-colors"
                      title="Duplicate Shift"
                    >
                      <Copy className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => handleDeleteShift(shift)}
                      className="p-2 text-slate-500 hover:text-rose-600 hover:bg-rose-50 rounded-xl transition-colors"
                      title="Delete Shift"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => setExpandedShiftId(isExpanded ? null : shift.id)}
                      className="p-2 text-slate-500 hover:text-slate-900 hover:bg-slate-100 rounded-xl transition-colors"
                    >
                      {isExpanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                    </button>
                  </div>
                </div>

                {/* Expanded Rules Section */}
                {isExpanded && (
                  <div className="px-5 pb-5 pt-3 border-t border-slate-100 bg-[#faf8f5]">
                    <div className="text-xs font-bold text-slate-600 mb-3 uppercase tracking-wider font-mono">
                      Configured Non-Overlapping Time Windows ({rules.length}):
                    </div>
                    {rules.length === 0 ? (
                      <div className="text-xs text-slate-500 italic p-4 bg-white rounded-xl border border-slate-200">
                        No punch period rules configured for this shift yet.
                      </div>
                    ) : (
                      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                        {rules.map((rule, idx) => (
                          <div
                            key={rule.id || idx}
                            className="bg-white p-4 rounded-xl border border-slate-200/90 shadow-sm flex flex-col justify-between gap-3"
                          >
                            <div className="flex items-start justify-between gap-2">
                              <div>
                                <div className="text-xs font-bold text-slate-900">
                                  {rule.period_name || rule.rule_name || `Punch #${rule.punch_no || 1}`}
                                </div>
                                <div className="text-xs font-mono text-slate-600 mt-1 flex items-center gap-1.5">
                                  <Clock className="w-3.5 h-3.5 text-[#f95700]" />
                                  <span>
                                    {rule.start_time} - {rule.end_time}
                                  </span>
                                </div>
                              </div>
                              <span
                                className={`text-[10px] font-bold px-2.5 py-0.5 rounded-full border ${getResultBadgeColor(
                                  rule.result_code
                                )}`}
                              >
                                {rule.result_code || 'PRESENT'}
                              </span>
                            </div>

                            <div className="flex items-center justify-between text-[11px] text-slate-500 pt-2 border-t border-slate-100 font-mono">
                              <span>Priority #{rule.priority || idx + 1}</span>
                              <div className="flex items-center gap-2">
                                {rule.require_face_verification && (
                                  <span className="flex items-center gap-1 text-emerald-700 font-semibold">
                                    <Shield className="w-3 h-3 text-emerald-600" /> Face AI
                                  </span>
                                )}
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* CREATE / EDIT SHIFT MODAL */}
      {isShiftModalOpen && (
        <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white border border-slate-200 rounded-2xl w-full max-w-3xl max-h-[90vh] flex flex-col overflow-hidden shadow-2xl">
            <div className="px-6 py-4 border-b border-slate-200 flex items-center justify-between bg-slate-50">
              <h2 className="text-base font-bold text-slate-900">
                {editingShift ? `Edit Shift: ${editingShift.shift_code}` : 'Create New Shift Rules'}
              </h2>
              <button
                onClick={() => setIsShiftModalOpen(false)}
                className="p-1 text-slate-400 hover:text-slate-700 rounded-lg hover:bg-slate-200 transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <form onSubmit={handleSaveShift} className="flex-1 overflow-y-auto p-6 space-y-5">
              {formError && (
                <div className="p-3.5 bg-rose-50 border border-rose-200 rounded-xl text-xs text-rose-700 flex items-center gap-2 font-medium">
                  <AlertTriangle className="w-4 h-4 shrink-0 text-rose-600" />
                  <span>{formError}</span>
                </div>
              )}

              {/* Shift Metadata */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1">
                    Shift Code *
                  </label>
                  <input
                    type="text"
                    required
                    placeholder="e.g. S001"
                    value={formCode}
                    onChange={(e) => setFormCode(e.target.value.toUpperCase())}
                    className="w-full bg-slate-50 border border-slate-300 rounded-xl px-3 py-2 text-xs text-slate-900 uppercase font-mono focus:bg-white focus:border-[#f95700]"
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1">
                    Shift Name *
                  </label>
                  <input
                    type="text"
                    required
                    placeholder="e.g. Morning General Shift"
                    value={formName}
                    onChange={(e) => setFormName(e.target.value)}
                    className="w-full bg-slate-50 border border-slate-300 rounded-xl px-3 py-2 text-xs text-slate-900 focus:bg-white focus:border-[#f95700]"
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1">
                    Status
                  </label>
                  <select
                    value={formIsActive ? 'active' : 'inactive'}
                    onChange={(e) => setFormIsActive(e.target.value === 'active')}
                    className="w-full bg-slate-50 border border-slate-300 rounded-xl px-3 py-2 text-xs text-slate-900 focus:bg-white focus:border-[#f95700]"
                  >
                    <option value="active">Active</option>
                    <option value="inactive">Inactive</option>
                  </select>
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">
                  Description
                </label>
                <input
                  type="text"
                  placeholder="e.g. General office shift with 15 min grace period"
                  value={formDescription}
                  onChange={(e) => setFormDescription(e.target.value)}
                  className="w-full bg-slate-50 border border-slate-300 rounded-xl px-3 py-2 text-xs text-slate-900 focus:bg-white focus:border-[#f95700]"
                />
              </div>

              {/* Dynamic Rules Builder */}
              <div className="space-y-3 pt-2">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-extrabold text-slate-800 uppercase tracking-wider font-mono">
                    Punch Windows & Classification Rules
                  </span>
                  <button
                    type="button"
                    onClick={handleAddRuleRow}
                    className="flex items-center gap-1.5 px-3 py-1.5 bg-[#fff2e8] hover:bg-[#ffe2ce] text-[#ea4e00] border border-[#ffd8bf] text-xs font-bold rounded-xl transition-colors"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    <span>Add Window Rule</span>
                  </button>
                </div>

                <div className="space-y-3">
                  {formRules.map((rule, idx) => (
                    <div
                      key={idx}
                      className="p-4 bg-slate-50 border border-slate-200 rounded-2xl space-y-3 relative group"
                    >
                      <div className="flex items-center justify-between gap-2 border-b border-slate-200 pb-2">
                        <span className="text-xs font-bold text-[#f95700] font-mono">
                          Window #{idx + 1}
                        </span>
                        {formRules.length > 1 && (
                          <button
                            type="button"
                            onClick={() => handleRemoveRuleRow(idx)}
                            className="text-slate-400 hover:text-rose-600 text-xs transition-colors"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        )}
                      </div>

                      <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
                        <div className="md:col-span-2">
                          <label className="block text-[11px] font-semibold text-slate-600 mb-1">
                            Window Name
                          </label>
                          <input
                            type="text"
                            value={rule.period_name || ''}
                            onChange={(e) => handleRuleChange(idx, 'period_name', e.target.value)}
                            placeholder="e.g. On-Time In-Punch"
                            className="w-full bg-white border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs text-slate-900 focus:outline-none"
                          />
                        </div>

                        <div>
                          <label className="block text-[11px] font-semibold text-slate-600 mb-1">
                            Start Time (HH:MM:SS)
                          </label>
                          <input
                            type="text"
                            value={rule.start_time}
                            onChange={(e) => handleRuleChange(idx, 'start_time', e.target.value)}
                            className="w-full bg-white border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs font-mono text-slate-900 focus:outline-none"
                          />
                        </div>

                        <div>
                          <label className="block text-[11px] font-semibold text-slate-600 mb-1">
                            End Time (HH:MM:SS)
                          </label>
                          <input
                            type="text"
                            value={rule.end_time}
                            onChange={(e) => handleRuleChange(idx, 'end_time', e.target.value)}
                            className="w-full bg-white border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs font-mono text-slate-900 focus:outline-none"
                          />
                        </div>

                        <div>
                          <label className="block text-[11px] font-semibold text-slate-600 mb-1">
                            Classification Result
                          </label>
                          <select
                            value={rule.result_code || 'ON_TIME'}
                            onChange={(e) => handleRuleChange(idx, 'result_code', e.target.value)}
                            className="w-full bg-white border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs text-slate-900 focus:outline-none"
                          >
                            <option value="ON_TIME">ON_TIME (Present)</option>
                            <option value="LATE">LATE (Late Arrival)</option>
                            <option value="HALF_DAY">HALF_DAY</option>
                            <option value="AFTERNOON_PUNCH">AFTERNOON_PUNCH</option>
                            <option value="SECOND_HALF">SECOND_HALF</option>
                            <option value="OUT_PUNCH">OUT_PUNCH</option>
                          </select>
                        </div>

                        <div>
                          <label className="block text-[11px] font-semibold text-slate-600 mb-1">
                            Punch No
                          </label>
                          <input
                            type="number"
                            value={rule.punch_no || 1}
                            onChange={(e) => handleRuleChange(idx, 'punch_no', Number(e.target.value))}
                            className="w-full bg-white border border-slate-300 rounded-lg px-2.5 py-1.5 text-xs font-mono text-slate-900 focus:outline-none"
                          />
                        </div>

                        <div className="md:col-span-2 flex items-center gap-4 pt-4">
                          <label className="flex items-center gap-2 cursor-pointer text-xs font-medium text-slate-700">
                            <input
                              type="checkbox"
                              checked={rule.require_face_verification ?? true}
                              onChange={(e) => handleRuleChange(idx, 'require_face_verification', e.target.checked)}
                              className="rounded border-slate-300 text-[#f95700] focus:ring-0"
                            />
                            <span>Require Face AI</span>
                          </label>
                          <label className="flex items-center gap-2 cursor-pointer text-xs font-medium text-slate-700">
                            <input
                              type="checkbox"
                              checked={rule.show_in_user_schedule ?? true}
                              onChange={(e) => handleRuleChange(idx, 'show_in_user_schedule', e.target.checked)}
                              className="rounded border-slate-300 text-[#f95700] focus:ring-0"
                            />
                            <span>Show in Schedule</span>
                          </label>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              <div className="pt-4 border-t border-slate-200 flex items-center justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setIsShiftModalOpen(false)}
                  className="px-4 py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 text-xs font-semibold rounded-xl transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting}
                  className="px-5 py-2 bg-[#f95700] hover:bg-[#ea4e00] text-white text-xs font-bold rounded-xl transition-all shadow-md shadow-orange-500/20 disabled:opacity-50"
                >
                  {submitting ? 'Saving...' : editingShift ? 'Update Shift' : 'Create Shift'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* DUPLICATE SHIFT MODAL */}
      {isDuplicateModalOpen && duplicateTarget && (
        <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white border border-slate-200 rounded-2xl w-full max-w-md p-6 space-y-4 shadow-2xl">
            <div className="flex items-center justify-between">
              <h3 className="text-base font-bold text-slate-900">Duplicate Shift</h3>
              <button
                onClick={() => setIsDuplicateModalOpen(false)}
                className="p-1 text-slate-400 hover:text-slate-700 rounded-lg hover:bg-slate-100"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            <p className="text-xs text-slate-600">
              Cloning shift <strong className="text-slate-900">{duplicateTarget.shift_name}</strong> ({duplicateTarget.shift_code}) along with its rules.
            </p>

            <div className="space-y-3">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">New Shift Code</label>
                <input
                  type="text"
                  value={dupCode}
                  onChange={(e) => setDupCode(e.target.value.toUpperCase())}
                  className="w-full bg-slate-50 border border-slate-300 rounded-xl px-3 py-2 text-xs text-slate-900 uppercase font-mono"
                />
              </div>
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">New Shift Name</label>
                <input
                  type="text"
                  value={dupName}
                  onChange={(e) => setDupName(e.target.value)}
                  className="w-full bg-slate-50 border border-slate-300 rounded-xl px-3 py-2 text-xs text-slate-900"
                />
              </div>
            </div>

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                onClick={() => setIsDuplicateModalOpen(false)}
                className="px-4 py-2 bg-slate-100 text-slate-700 text-xs font-semibold rounded-xl"
              >
                Cancel
              </button>
              <button
                onClick={handleDuplicate}
                disabled={submitting}
                className="px-4 py-2 bg-[#f95700] hover:bg-[#ea4e00] text-white text-xs font-bold rounded-xl shadow-md"
              >
                {submitting ? 'Duplicating...' : 'Duplicate Shift'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ASSIGN SHIFT MODAL */}
      {isAssignModalOpen && (
        <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white border border-slate-200 rounded-2xl w-full max-w-xl max-h-[90vh] flex flex-col overflow-hidden shadow-2xl">
            <div className="px-6 py-4 border-b border-slate-200 bg-slate-50 flex items-center justify-between">
              <h2 className="text-base font-bold text-slate-900 flex items-center gap-2">
                <UserPlus className="w-5 h-5 text-[#f95700]" />
                <span>Assign Shift to Employee</span>
              </h2>
              <button
                onClick={() => setIsAssignModalOpen(false)}
                className="p-1 text-slate-400 hover:text-slate-700 rounded-lg hover:bg-slate-200"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <form onSubmit={handleAssignShiftSubmit} className="p-6 space-y-4 overflow-y-auto flex-1">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">Select Employee *</label>
                <select
                  value={assignUser}
                  onChange={(e) => {
                    setAssignUser(e.target.value);
                    fetchUserHistory(Number(e.target.value));
                  }}
                  className="w-full bg-slate-50 border border-slate-300 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none"
                >
                  {employees.map((emp) => (
                    <option key={emp.id} value={emp.id}>
                      {emp.full_name} ({emp.employee_id}) {emp.department ? `- ${emp.department}` : ''}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">Select Shift *</label>
                <select
                  value={assignShiftId || ''}
                  onChange={(e) => setAssignShiftId(Number(e.target.value))}
                  className="w-full bg-slate-50 border border-slate-300 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none"
                >
                  {shifts.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.shift_code} - {s.shift_name}
                    </option>
                  ))}
                </select>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1">Effective From *</label>
                  <input
                    type="date"
                    required
                    value={effectiveFrom}
                    onChange={(e) => setEffectiveFrom(e.target.value)}
                    className="w-full bg-slate-50 border border-slate-300 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none"
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1">Effective To (Optional)</label>
                  <input
                    type="date"
                    value={effectiveTo}
                    onChange={(e) => setEffectiveTo(e.target.value)}
                    className="w-full bg-slate-50 border border-slate-300 rounded-xl px-3 py-2 text-xs text-slate-900 focus:outline-none"
                  />
                </div>
              </div>

              <button
                type="submit"
                disabled={submitting}
                className="w-full py-2.5 bg-[#f95700] hover:bg-[#ea4e00] text-white text-xs font-bold rounded-xl transition-all shadow-md shadow-orange-500/20"
              >
                {submitting ? 'Saving Assignment...' : 'Save Shift Assignment'}
              </button>

              {/* Assignment History Section */}
              <div className="pt-4 border-t border-slate-200 space-y-2">
                <div className="text-xs font-bold text-slate-800 uppercase tracking-wider font-mono">
                  Existing Shift Assignments ({assignHistory.length})
                </div>
                {assignHistory.length === 0 ? (
                  <div className="text-xs text-slate-500 italic p-3 bg-slate-50 rounded-xl border border-slate-200">
                    No active or past shift assignments for this employee.
                  </div>
                ) : (
                  <div className="space-y-2">
                    {assignHistory.map((h) => (
                      <div
                        key={h.id}
                        className="p-3 bg-slate-50 border border-slate-200 rounded-xl flex items-center justify-between text-xs"
                      >
                        <div>
                          <div className="font-bold text-slate-900">
                            {h.shift_code || 'Shift'} - {h.shift_name || ''}
                          </div>
                          <div className="text-[11px] font-mono text-slate-500 mt-0.5">
                            From: {h.effective_from} {h.effective_to ? `To: ${h.effective_to}` : '(Ongoing)'}
                          </div>
                        </div>
                        <button
                          type="button"
                          onClick={() => handleDeleteAssignment(h.id)}
                          className="p-1 text-slate-400 hover:text-rose-600 rounded transition-colors"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};

export default ShiftManagementScreen;
