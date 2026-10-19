import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { 
  X, ChevronLeft, ChevronRight, Calendar, Sparkles, 
  RotateCcw, Check, AlertCircle, Clock, CheckCircle2,
  Layers, Shuffle, ListFilter
} from 'lucide-react';
import { API_BASE } from '../api/client';

const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
];

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export default function MonthlyShiftModal({ employee, initialYear, initialMonth, onClose, onSaved }) {
  const [year, setYear] = useState(initialYear || new Date().getFullYear());
  const [month, setMonth] = useState(initialMonth || (new Date().getMonth() + 1));
  
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [activeShifts, setActiveShifts] = useState([]);
  const [assignments, setAssignments] = useState({}); // { [day]: { shift_id, shift_code, shift_name, is_off, color, notes } }
  const [selectedDayForPopover, setSelectedDayForPopover] = useState(null);
  
  // Paint tool selection: null = normal click popover, or shift_id / 'OFF' / 'CLEAR'
  const [paintMode, setPaintMode] = useState(null);
  const [selectedDays, setSelectedDays] = useState([]);
  
  // Pattern menu modal / popover
  const [isPatternOpen, setIsPatternOpen] = useState(false);
  const [patternType, setPatternType] = useState('weekly_standard');
  const [patternShiftId, setPatternShiftId] = useState('');
  const [customCycle, setCustomCycle] = useState([
    { shift_id: '', is_off: false, days_count: 2 },
    { shift_id: '', is_off: false, days_count: 2 },
    { shift_id: '', is_off: true, days_count: 1 }
  ]);
  
  const [statusMessage, setStatusMessage] = useState('');
  const [hasChanges, setHasChanges] = useState(false);

  const fetchSchedule = async () => {
    setLoading(true);
    setStatusMessage('');
    try {
      const res = await axios.get(`${API_BASE}/shifts/employee/${employee.id}/monthly`, {
        params: { year, month }
      });
      setAssignments(res.data.assignments || {});
      setActiveShifts(res.data.active_shifts || []);
      if (res.data.active_shifts?.length > 0 && !patternShiftId) {
        setPatternShiftId(res.data.active_shifts[0].id);
      }
      setHasChanges(false);
      setSelectedDays([]);
    } catch (err) {
      console.error('Failed to load employee monthly shifts:', err);
      setStatusMessage('Failed to load shift schedule.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (employee?.id) {
      fetchSchedule();
    }
  }, [employee?.id, year, month]);

  const handlePrevMonth = () => {
    if (month === 1) {
      setMonth(12);
      setYear(prev => prev - 1);
    } else {
      setMonth(prev => prev - 1);
    }
  };

  const handleNextMonth = () => {
    if (month === 12) {
      setMonth(1);
      setYear(prev => prev + 1);
    } else {
      setMonth(prev => prev + 1);
    }
  };

  const daysInMonth = new Date(year, month, 0).getDate();
  const firstDayWeekday = new Date(year, month - 1, 1).getDay(); // 0 = Sun, 1 = Mon ... 6 = Sat

  // Calendar cells generation (Sun=0 to Sat=6)
  const calendarCells = [];
  // Leading blank days
  for (let i = 0; i < firstDayWeekday; i++) {
    calendarCells.push({ type: 'empty', key: `empty-${i}` });
  }
  // Days of current month
  for (let d = 1; d <= daysInMonth; d++) {
    calendarCells.push({
      type: 'day',
      day: d,
      key: `day-${d}`,
      dateStr: `${year}-${String(month).padStart(2, '0')}-${String(d).padStart(2, '0')}`
    });
  }

  // Shift assignment helper
  const assignShiftToDay = (day, shiftId, isOff = false) => {
    const sObj = activeShifts.find(s => s.id === shiftId);
    setAssignments(prev => ({
      ...prev,
      [String(day)]: isOff ? {
        shift_id: null,
        shift_code: 'OFF',
        shift_name: 'Day Off',
        color: 'slate',
        is_off: true
      } : (sObj ? {
        shift_id: sObj.id,
        shift_code: sObj.code,
        shift_name: sObj.name,
        color: sObj.color || 'emerald',
        is_off: false
      } : null)
    }));
    setHasChanges(true);
  };

  const clearDay = (day) => {
    setAssignments(prev => {
      const copy = { ...prev };
      delete copy[String(day)];
      return copy;
    });
    setHasChanges(true);
  };

  const handleCellClick = (day) => {
    if (paintMode === 'OFF') {
      assignShiftToDay(day, null, true);
    } else if (paintMode === 'CLEAR') {
      clearDay(day);
    } else if (paintMode) {
      assignShiftToDay(day, Number(paintMode), false);
    } else {
      // Toggle popover
      setSelectedDayForPopover(prev => (prev === day ? null : day));
    }
  };

  const handleApplyPattern = async () => {
    try {
      const payload = {
        year,
        month,
        pattern_mode: patternType,
        primary_shift_id: patternShiftId ? Number(patternShiftId) : (activeShifts[0]?.id || 1),
        custom_sequence: patternType === 'custom_rotation' ? customCycle.map(c => ({
          shift_id: c.shift_id ? Number(c.shift_id) : (activeShifts[0]?.id || 1),
          is_off: Boolean(c.is_off),
          days_count: Number(c.days_count) || 1
        })) : undefined
      };

      const res = await axios.post(
        `${API_BASE}/shifts/employee/${employee.id}/monthly/pattern`,
        payload
      );

      if (res.data.draft_assignments) {
        setAssignments(res.data.draft_assignments);
        setHasChanges(true);
        setIsPatternOpen(false);
        setStatusMessage('Pattern applied to draft schedule. Review and click "Save Assignments" to commit.');
      }
    } catch (err) {
      console.error('Failed to generate pattern:', err);
      alert('Failed to generate pattern: ' + (err.response?.data?.detail || err.message));
    }
  };

  const handleSaveAssignments = async () => {
    setSaving(true);
    setStatusMessage('');
    try {
      const assignmentList = [];
      for (let d = 1; d <= daysInMonth; d++) {
        const item = assignments[String(d)];
        if (item) {
          assignmentList.push({
            date: `${year}-${String(month).padStart(2, '0')}-${String(d).padStart(2, '0')}`,
            shift_id: item.is_off ? null : item.shift_id,
            shift_code: item.shift_code,
            is_off: Boolean(item.is_off),
            notes: item.notes || null
          });
        }
      }

      await axios.post(
        `${API_BASE}/shifts/employee/${employee.id}/monthly`,
        {
          year,
          month,
          assignments: assignmentList
        }
      );

      setStatusMessage('Shift roster saved successfully! Daily attendance recalculated.');
      setHasChanges(false);
      if (onSaved) onSaved();
      setTimeout(() => {
        onClose();
      }, 900);
    } catch (err) {
      console.error('Failed to save assignments:', err);
      alert('Failed to save assignments: ' + (err.response?.data?.detail || err.message));
    } finally {
      setSaving(false);
    }
  };

  const handleClearDraft = () => {
    if (window.confirm(`Clear all draft shift assignments for ${MONTH_NAMES[month - 1]} ${year}?`)) {
      setAssignments({});
      setHasChanges(true);
      setSelectedDayForPopover(null);
    }
  };

  const getBadgeStyle = (item) => {
    if (!item) return null;
    if (item.is_off) {
      return "bg-slate-100 text-slate-600 border border-slate-200";
    }
    const color = item.color || 'emerald';
    if (color === 'emerald') return "bg-emerald-100 text-emerald-800 border border-emerald-200";
    if (color === 'blue') return "bg-blue-100 text-blue-800 border border-blue-200";
    if (color === 'amber') return "bg-amber-100 text-amber-800 border border-amber-200";
    if (color === 'purple') return "bg-purple-100 text-purple-800 border border-purple-200";
    if (color === 'rose') return "bg-rose-100 text-rose-800 border border-rose-200";
    if (color === 'indigo') return "bg-indigo-100 text-indigo-800 border border-indigo-200";
    return "bg-slate-100 text-slate-700 border border-slate-200";
  };

  const getPillDot = (color) => {
    if (color === 'emerald') return 'bg-emerald-500';
    if (color === 'blue') return 'bg-blue-500';
    if (color === 'amber') return 'bg-amber-500';
    if (color === 'purple') return 'bg-purple-500';
    if (color === 'rose') return 'bg-rose-500';
    if (color === 'indigo') return 'bg-indigo-500';
    return 'bg-slate-400';
  };

  return (
    <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-3 sm:p-5 overflow-y-auto">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-4xl border border-slate-200/90 overflow-hidden flex flex-col my-auto animate-in fade-in zoom-in-95 duration-150">
        
        {/* Header */}
        <div className="p-5 border-b border-slate-200 bg-slate-50/80 flex items-start justify-between gap-4">
          <div className="flex items-center gap-3.5">
            <div className="w-11 h-11 rounded-full bg-brand-100 text-brand-700 font-bold text-base flex items-center justify-center shadow-xs">
              {employee?.name ? employee.name.charAt(0) : 'E'}
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-bold text-slate-900 leading-tight">
                  {employee?.name || 'Employee Shift Schedule'}
                </h2>
                <span className="text-[11px] font-semibold text-brand-700 bg-brand-50 px-2 py-0.5 rounded-full border border-brand-200">
                  Monthly Roster
                </span>
              </div>
              <p className="text-xs text-slate-500 mt-0.5">
                ID: <span className="font-mono font-semibold text-slate-700">{employee?.id}</span> &nbsp;|&nbsp;
                Department: <span className="font-semibold text-slate-700">{employee?.department || 'Operations'}</span> &nbsp;|&nbsp;
                Designation: <span className="font-semibold text-slate-700">{employee?.designation || 'Staff'}</span>
              </p>
            </div>
          </div>

          <button 
            onClick={onClose}
            className="p-1.5 text-slate-400 hover:text-slate-700 hover:bg-slate-200/60 rounded-lg transition-colors"
          >
            <X size={20} />
          </button>
        </div>

        {/* Month Navigation & Shift Legend */}
        <div className="p-4 sm:p-5 border-b border-slate-100 space-y-4">
          {/* Controls row */}
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-2">
              <button
                onClick={handlePrevMonth}
                className="p-1.5 text-slate-600 hover:text-slate-900 bg-slate-100 hover:bg-slate-200 rounded-lg transition-colors"
                title="Previous month"
              >
                <ChevronLeft size={18} />
              </button>

              <h3 className="text-base font-bold text-slate-800 min-w-[150px] text-center">
                {MONTH_NAMES[month - 1]} {year}
              </h3>

              <button
                onClick={handleNextMonth}
                className="p-1.5 text-slate-600 hover:text-slate-900 bg-slate-100 hover:bg-slate-200 rounded-lg transition-colors"
                title="Next month"
              >
                <ChevronRight size={18} />
              </button>
            </div>

            {/* Quick Paint Tool Info */}
            <div className="text-xs text-slate-500 flex items-center gap-1.5">
              <span>Quick Paint Tool:</span>
              <button
                onClick={() => setPaintMode(null)}
                className={`px-2 py-0.5 rounded text-[11px] font-semibold transition-all ${
                  paintMode === null ? 'bg-slate-900 text-white shadow-xs' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                }`}
              >
                Click Popover
              </button>
            </div>
          </div>

          {/* Shift Legend Pills */}
          <div className="flex flex-wrap items-center gap-2 pt-1 text-xs">
            <span className="text-[11px] font-bold text-slate-400 uppercase tracking-wider mr-1">Shifts:</span>
            {activeShifts.map(s => {
              const isSelected = paintMode === String(s.id);
              return (
                <button
                  key={s.id}
                  type="button"
                  onClick={() => setPaintMode(isSelected ? null : String(s.id))}
                  className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold transition-all border ${
                    isSelected 
                      ? 'ring-2 ring-brand-500 shadow-xs border-transparent' 
                      : 'bg-white hover:bg-slate-50 border-slate-200 text-slate-700'
                  }`}
                >
                  <span className={`w-2.5 h-2.5 rounded-full ${getPillDot(s.color)}`} />
                  <span>{s.code} - {s.name}</span>
                </button>
              );
            })}

            {/* Off Day Pill */}
            <button
              type="button"
              onClick={() => setPaintMode(paintMode === 'OFF' ? null : 'OFF')}
              className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold transition-all border ${
                paintMode === 'OFF'
                  ? 'ring-2 ring-slate-700 shadow-xs border-transparent bg-slate-800 text-white'
                  : 'bg-white hover:bg-slate-50 border-slate-200 text-slate-700'
              }`}
            >
              <span className="w-2.5 h-2.5 rounded-full bg-slate-400" />
              <span>Off</span>
            </button>

            {/* Clear Tool */}
            <button
              type="button"
              onClick={() => setPaintMode(paintMode === 'CLEAR' ? null : 'CLEAR')}
              className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold transition-all border ${
                paintMode === 'CLEAR'
                  ? 'ring-2 ring-rose-500 shadow-xs border-transparent bg-rose-50 text-rose-700 border-rose-300'
                  : 'bg-white hover:bg-slate-50 border-slate-200 text-slate-600'
              }`}
            >
              <RotateCcw size={12} />
              <span>Clear Eraser</span>
            </button>
          </div>
        </div>

        {/* Calendar Grid Container */}
        <div className="p-4 sm:p-6 overflow-y-auto flex-1 max-h-[60vh]">
          {loading ? (
            <div className="p-12 text-center text-slate-400 text-sm">
              Loading monthly shift assignments...
            </div>
          ) : (
            <div className="space-y-2">
              {/* Day Headers (Sun-Sat) */}
              <div className="grid grid-cols-7 gap-2 text-center text-xs font-bold text-slate-500 uppercase tracking-wider py-1">
                {WEEKDAYS.map((w, idx) => (
                  <div key={w} className={idx === 0 || idx === 6 ? 'text-amber-600/90' : ''}>
                    {w}
                  </div>
                ))}
              </div>

              {/* 7-Column Grid Cells */}
              <div className="grid grid-cols-7 gap-2">
                {calendarCells.map((cell) => {
                  if (cell.type === 'empty') {
                    return (
                      <div 
                        key={cell.key} 
                        className="min-h-[72px] sm:min-h-[82px] rounded-xl bg-slate-50/50 border border-dashed border-slate-200/60"
                      />
                    );
                  }

                  const dayNum = cell.day;
                  const item = assignments[String(dayNum)];
                  const badgeClass = getBadgeStyle(item);
                  const isPopoverOpen = selectedDayForPopover === dayNum;

                  return (
                    <div
                      key={cell.key}
                      onClick={() => handleCellClick(dayNum)}
                      className={`relative min-h-[72px] sm:min-h-[82px] p-2 rounded-xl border transition-all cursor-pointer flex flex-col justify-between select-none ${
                        isPopoverOpen
                          ? 'border-brand-500 ring-2 ring-brand-400/30 bg-brand-50/20 shadow-sm'
                          : item 
                            ? 'bg-white hover:border-slate-300 border-slate-200 shadow-xs hover:shadow-sm'
                            : 'bg-slate-50/40 hover:bg-white border-slate-200/80 hover:border-brand-300'
                      }`}
                    >
                      {/* Day Number */}
                      <div className="flex items-center justify-between">
                        <span className={`text-xs font-bold ${item ? 'text-slate-800' : 'text-slate-400'}`}>
                          {dayNum}
                        </span>
                        {item?.is_off && (
                          <span className="w-1.5 h-1.5 rounded-full bg-slate-400" />
                        )}
                      </div>

                      {/* Assigned Shift Badge */}
                      <div className="my-auto pt-1">
                        {item ? (
                          <div 
                            className={`w-full text-center py-1 px-1 rounded-md text-[11px] font-bold truncate transition-transform hover:scale-105 ${badgeClass}`}
                            title={`${item.shift_code} - ${item.shift_name}`}
                          >
                            {item.shift_code}
                          </div>
                        ) : (
                          <div className="text-[10px] text-slate-300 text-center font-medium italic">
                            Unassigned
                          </div>
                        )}
                      </div>

                      {/* Dropdown Popover on Click if not in paintMode */}
                      {isPopoverOpen && !paintMode && (
                        <div 
                          className="absolute left-0 top-full mt-1.5 z-40 bg-white rounded-xl shadow-xl border border-slate-200 p-2 w-48 text-xs space-y-1 animate-in fade-in-50 zoom-in-95"
                          onClick={(e) => e.stopPropagation()}
                        >
                          <div className="px-2 py-1 text-[11px] font-bold text-slate-400 uppercase tracking-wider border-b border-slate-100 flex justify-between items-center">
                            <span>Assign Day {dayNum}</span>
                            <button onClick={() => setSelectedDayForPopover(null)} className="text-slate-400 hover:text-slate-600">
                              <X size={12} />
                            </button>
                          </div>
                          
                          {/* Active Shifts */}
                          <div className="max-h-40 overflow-y-auto space-y-0.5">
                            {activeShifts.map(s => (
                              <button
                                key={s.id}
                                type="button"
                                onClick={() => {
                                  assignShiftToDay(dayNum, s.id, false);
                                  setSelectedDayForPopover(null);
                                }}
                                className="w-full text-left px-2 py-1.5 rounded-lg hover:bg-slate-100 font-semibold text-slate-700 flex items-center justify-between transition-colors"
                              >
                                <span className="flex items-center gap-1.5">
                                  <span className={`w-2 h-2 rounded-full ${getPillDot(s.color)}`} />
                                  <span>{s.code} - {s.name}</span>
                                </span>
                                {item?.shift_id === s.id && <Check size={14} className="text-brand-600" />}
                              </button>
                            ))}
                          </div>

                          <div className="pt-1 border-t border-slate-100 space-y-0.5">
                            <button
                              type="button"
                              onClick={() => {
                                assignShiftToDay(dayNum, null, true);
                                setSelectedDayForPopover(null);
                              }}
                              className="w-full text-left px-2 py-1.5 rounded-lg hover:bg-slate-100 font-semibold text-slate-600 flex items-center justify-between"
                            >
                              <span>Off (Day Off)</span>
                              {item?.is_off && <Check size={14} className="text-slate-600" />}
                            </button>

                            <button
                              type="button"
                              onClick={() => {
                                clearDay(dayNum);
                                setSelectedDayForPopover(null);
                              }}
                              className="w-full text-left px-2 py-1.5 rounded-lg hover:bg-rose-50 font-semibold text-rose-600 flex items-center justify-between"
                            >
                              <span>Unassign (Clear)</span>
                            </button>
                          </div>
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </div>

        {/* Auto-fill Pattern Drawer/Modal */}
        {isPatternOpen && (
          <div className="p-5 border-t border-slate-200 bg-amber-50/40 space-y-4 text-xs animate-in slide-in-from-bottom-2">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Sparkles size={16} className="text-brand-600" />
                <h4 className="font-bold text-slate-900 text-sm">Deterministic Auto-fill Shift Pattern</h4>
              </div>
              <button 
                onClick={() => setIsPatternOpen(false)}
                className="text-slate-400 hover:text-slate-600"
              >
                <X size={16} />
              </button>
            </div>

            <p className="text-slate-500 text-xs">
              Apply a reproducible rotation without random shift assignments. You can review and adjust any day before saving.
            </p>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <div>
                <label className="block font-semibold text-slate-700 mb-1">Rotation Strategy</label>
                <select
                  value={patternType}
                  onChange={(e) => setPatternType(e.target.value)}
                  className="w-full p-2 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium"
                >
                  <option value="weekly_standard">Mon–Fri Work, Sat–Sun Off</option>
                  <option value="work6_off1">6 Days Work, 1 Day Off (Sunday)</option>
                  <option value="custom_rotation">Custom Sequential Rotation</option>
                </select>
              </div>

              {patternType !== 'custom_rotation' && (
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Primary Work Shift</label>
                  <select
                    value={patternShiftId}
                    onChange={(e) => setPatternShiftId(e.target.value)}
                    className="w-full p-2 bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium"
                  >
                    {activeShifts.map(s => (
                      <option key={s.id} value={s.id}>{s.code} — {s.name} ({s.start_time}-{s.end_time})</option>
                    ))}
                  </select>
                </div>
              )}

              {patternType === 'custom_rotation' && (
                <div className="sm:col-span-2">
                  <label className="block font-semibold text-slate-700 mb-1">Repeating Sequence</label>
                  <div className="space-y-1.5">
                    {customCycle.map((step, idx) => (
                      <div key={idx} className="flex items-center gap-2">
                        <select
                          value={step.is_off ? 'OFF' : step.shift_id}
                          onChange={(e) => {
                            const val = e.target.value;
                            const copy = [...customCycle];
                            if (val === 'OFF') {
                              copy[idx] = { ...copy[idx], is_off: true, shift_id: '' };
                            } else {
                              copy[idx] = { ...copy[idx], is_off: false, shift_id: Number(val) };
                            }
                            setCustomCycle(copy);
                          }}
                          className="flex-1 p-1.5 bg-white border border-slate-300 rounded-lg text-xs"
                        >
                          <option value="OFF">Day Off (OFF)</option>
                          {activeShifts.map(s => (
                            <option key={s.id} value={s.id}>{s.code} - {s.name}</option>
                          ))}
                        </select>
                        <span className="text-slate-400">for</span>
                        <input
                          type="number"
                          min="1"
                          max="14"
                          value={step.days_count}
                          onChange={(e) => {
                            const copy = [...customCycle];
                            copy[idx].days_count = Number(e.target.value);
                            setCustomCycle(copy);
                          }}
                          className="w-14 p-1.5 bg-white border border-slate-300 rounded-lg text-center text-xs font-semibold"
                        />
                        <span className="text-slate-500">days</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>

            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setIsPatternOpen(false)}
                className="px-3.5 py-1.5 border border-slate-300 rounded-lg text-slate-700 hover:bg-slate-100 font-semibold"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleApplyPattern}
                className="px-4 py-1.5 bg-brand-600 hover:bg-brand-700 text-white rounded-lg font-semibold shadow-xs"
              >
                Apply Pattern to Draft
              </button>
            </div>
          </div>
        )}

        {/* Status Alert Banner */}
        {statusMessage && (
          <div className="mx-5 mb-2 p-3 bg-emerald-50 border border-emerald-200 rounded-xl flex items-center gap-2 text-xs font-medium text-emerald-800">
            <CheckCircle2 size={16} className="text-emerald-600 shrink-0" />
            <span>{statusMessage}</span>
          </div>
        )}

        {/* Footer Actions */}
        <div className="p-4 sm:p-5 border-t border-slate-200 bg-slate-50 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => setIsPatternOpen(prev => !prev)}
              className="flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-slate-700 bg-white hover:bg-slate-100 border border-slate-300 rounded-lg shadow-2xs transition-colors"
            >
              <Sparkles size={14} className="text-brand-600" />
              Auto-fill pattern ▾
            </button>

            <button
              type="button"
              onClick={handleClearDraft}
              className="flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-rose-700 bg-white hover:bg-rose-50 border border-rose-200 rounded-lg transition-colors"
            >
              <RotateCcw size={14} />
              Clear draft
            </button>
          </div>

          <div className="flex items-center gap-2.5">
            <button
              type="button"
              onClick={onClose}
              disabled={saving}
              className="px-4 py-2 text-xs font-semibold text-slate-600 hover:text-slate-900 bg-white border border-slate-200 hover:bg-slate-100 rounded-lg transition-colors"
            >
              Cancel
            </button>

            <button
              type="button"
              onClick={handleSaveAssignments}
              disabled={saving}
              className="flex items-center gap-1.5 px-5 py-2 text-xs font-semibold text-white bg-brand-600 hover:bg-brand-700 disabled:opacity-50 rounded-lg shadow-sm transition-colors"
            >
              {saving ? 'Saving...' : 'Save Assignments'}
            </button>
          </div>
        </div>

        {/* Informational Disclaimer note */}
        <div className="px-5 py-2.5 bg-slate-100/70 border-t border-slate-200 text-[11px] text-slate-500 flex items-center gap-1.5">
          <AlertCircle size={13} className="text-brand-600 shrink-0" />
          <span>Saved assignments are used by attendance processing; unassigned days are flagged for review.</span>
        </div>

      </div>
    </div>
  );
}
