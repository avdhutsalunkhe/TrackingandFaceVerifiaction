import React, { useState } from 'react';
import { useTimeOffice } from '../context/TimeOfficeContext';
import { api } from '../services/api';
import { Edit3, CheckCircle2, AlertTriangle, ShieldCheck } from 'lucide-react';

export const CorrectionScreen: React.FC = () => {
  const { selectedDate, triggerRefresh } = useTimeOffice();
  const [employeeId, setEmployeeId] = useState('');
  const [dateVal, setDateVal] = useState(selectedDate || new Date().toISOString().slice(0, 10));
  const [vNo, setVNo] = useState<number>(1);
  const [newStatus, setNewStatus] = useState<string>('PRESENT');
  const [reason, setReason] = useState<string>('');
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!employeeId.trim()) {
      setFeedback({ type: 'error', message: 'Employee ID is required.' });
      return;
    }
    if (!reason.trim()) {
      setFeedback({ type: 'error', message: 'A mandatory operational reason is required for the audit trail.' });
      return;
    }

    setIsSubmitting(true);
    setFeedback(null);
    try {
      const res = await api.correctAttendance({
        employee_id: employeeId.trim(),
        attendance_date: dateVal,
        verification_no: Number(vNo),
        new_status: newStatus,
        reason: reason.trim(),
      });

      setFeedback({ type: 'success', message: res.message || 'Attendance record successfully corrected and audited.' });
      setReason('');
      triggerRefresh();
    } catch (err: any) {
      setFeedback({
        type: 'error',
        message: err.response?.data?.detail || err.message || 'Failed to apply attendance correction.',
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="p-6 max-w-3xl mx-auto space-y-6 bg-[#090d16] min-h-screen text-slate-200">
      {/* Header */}
      <div className="bg-[#111622] border border-[#1e2638] p-5 rounded-2xl shadow-lg">
        <h2 className="text-xl font-bold text-white flex items-center gap-2.5">
          <Edit3 className="w-6 h-6 text-[#f95700]" />
          <span>Controlled Attendance Status Correction</span>
        </h2>
        <p className="text-xs text-slate-400 mt-1">
          Perform authorized attendance corrections with mandatory audit reasoning. All changes are permanently recorded.
        </p>
      </div>

      {/* Main Form */}
      <div className="bg-[#111622] border border-[#1e2638] rounded-2xl p-6 shadow-xl">
        <form onSubmit={handleSubmit} className="space-y-4 text-xs">
          {feedback && (
            <div
              className={`p-3.5 rounded-xl border flex items-start gap-2.5 ${
                feedback.type === 'success'
                  ? 'bg-emerald-500/15 border-emerald-500/30 text-emerald-300'
                  : 'bg-rose-500/15 border-rose-500/30 text-rose-300'
              }`}
            >
              {feedback.type === 'success' ? (
                <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
              ) : (
                <AlertTriangle className="w-4 h-4 text-rose-400 shrink-0 mt-0.5" />
              )}
              <span className="text-xs font-semibold">{feedback.message}</span>
            </div>
          )}

          <div className="bg-[#0c1018] border border-[#242f48] p-3.5 rounded-xl text-slate-300 flex items-start gap-3">
            <ShieldCheck className="w-4 h-4 text-[#f95700] shrink-0 mt-0.5" />
            <div className="text-[11px] leading-relaxed">
              <strong className="text-white">Audit Enforcement:</strong> Modifying attendance will record the timestamp, your logged-in Time Office username, IP address, previous value, new value, and reason into the central audit trail.
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-slate-300 font-bold mb-1.5 uppercase tracking-wider">
                Target Employee ID *
              </label>
              <input
                type="text"
                required
                value={employeeId}
                onChange={(e) => setEmployeeId(e.target.value)}
                placeholder="e.g. EMP1001"
                className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-white font-mono text-xs focus:outline-none focus:border-[#f95700]"
              />
            </div>

            <div>
              <label className="block text-slate-300 font-bold mb-1.5 uppercase tracking-wider">
                Attendance Date *
              </label>
              <input
                type="date"
                required
                value={dateVal}
                onChange={(e) => setDateVal(e.target.value)}
                className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-white font-mono text-xs focus:outline-none focus:border-[#f95700]"
              />
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-slate-300 font-bold mb-1.5 uppercase tracking-wider">
                Punch Verification Number *
              </label>
              <input
                type="number"
                min={1}
                max={10}
                required
                value={vNo}
                onChange={(e) => setVNo(Number(e.target.value))}
                className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-white font-mono text-xs focus:outline-none focus:border-[#f95700]"
              />
              <span className="text-[10px] text-slate-400 mt-1 block">Usually 1 for IN, 2 for OUT or split session punch number</span>
            </div>

            <div>
              <label className="block text-slate-300 font-bold mb-1.5 uppercase tracking-wider">
                New Official Status *
              </label>
              <select
                value={newStatus}
                onChange={(e) => setNewStatus(e.target.value)}
                className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-white font-mono text-xs focus:outline-none focus:border-[#f95700]"
              >
                <option value="PRESENT">PRESENT</option>
                <option value="LATE">LATE</option>
              </select>
            </div>
          </div>

          <div>
            <label className="block text-slate-300 font-bold mb-1.5 uppercase tracking-wider">
              Mandatory Operational Justification *
            </label>
            <textarea
              rows={4}
              required
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Explain why this correction is being authorized (e.g. 'Employee biometric failed due to facial bandage, verified presence at station with supervisor')..."
              className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl p-3 text-white text-xs focus:outline-none focus:border-[#f95700]"
            />
          </div>

          <div className="flex justify-end pt-2">
            <button
              type="submit"
              disabled={isSubmitting}
              className="px-5 py-2.5 rounded-xl bg-[#f95700] hover:bg-[#ea4e00] text-white font-bold text-xs shadow-lg shadow-orange-500/20 transition-all flex items-center gap-2 disabled:opacity-50"
            >
              <Edit3 className="w-4 h-4" />
              <span>{isSubmitting ? 'Recording Correction...' : 'Authorize & Commit Correction'}</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default CorrectionScreen;
