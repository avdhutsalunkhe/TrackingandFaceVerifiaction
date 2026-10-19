import React, { useState } from 'react';
import { Modal } from '../components/common/Modal';
import { api } from '../services/api';
import { useTimeOffice } from '../context/TimeOfficeContext';
import { Edit3, AlertTriangle, CheckCircle2 } from 'lucide-react';

interface CorrectionModalProps {
  isOpen: boolean;
  onClose: () => void;
  initialEmployeeId?: string;
  initialDate?: string;
  initialVerificationNo?: number;
}

export const CorrectionModal: React.FC<CorrectionModalProps> = ({
  isOpen,
  onClose,
  initialEmployeeId = '',
  initialDate = '',
  initialVerificationNo = 1,
}) => {
  const { triggerRefresh, selectedDate } = useTimeOffice();
  const [employeeId, setEmployeeId] = useState(initialEmployeeId);
  const [dateVal, setDateVal] = useState(initialDate || selectedDate);
  const [vNo, setVNo] = useState<number>(initialVerificationNo);
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
      triggerRefresh();
      setTimeout(() => {
        onClose();
      }, 1500);
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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Controlled Attendance Correction"
      subtitle="Authorized Time Office operation — audited and recorded"
      maxWidth="max-w-lg"
    >
      <form onSubmit={handleSubmit} className="space-y-3.5 text-xs">
        {feedback && (
          <div
            className={`p-3 rounded-lg border flex items-start gap-2 ${
              feedback.type === 'success'
                ? 'bg-emerald-50 border-emerald-200 text-emerald-800'
                : 'bg-rose-50 border-rose-200 text-rose-800'
            }`}
          >
            {feedback.type === 'success' ? (
              <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0 mt-0.5" />
            ) : (
              <AlertTriangle className="w-4 h-4 text-rose-600 shrink-0 mt-0.5" />
            )}
            <span className="font-semibold">{feedback.message}</span>
          </div>
        )}

        <div className="bg-amber-50 border border-amber-200 p-3 rounded-lg text-amber-900 text-[11px] leading-relaxed">
          <strong>Notice:</strong> This action updates the authoritative attendance state and writes an immutable record to the system audit trail including your operator ID and IP address.
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-slate-700 font-bold mb-1 uppercase tracking-wider text-[10px]">
              Employee ID
            </label>
            <input
              type="text"
              required
              value={employeeId}
              onChange={(e) => setEmployeeId(e.target.value)}
              placeholder="e.g. EMP1001"
              className="w-full bg-white border border-slate-300 rounded-lg px-3 py-2 text-slate-900 font-mono text-xs focus:outline-none focus:border-brand-500 shadow-sm"
            />
          </div>

          <div>
            <label className="block text-slate-700 font-bold mb-1 uppercase tracking-wider text-[10px]">
              Attendance Date
            </label>
            <input
              type="date"
              required
              value={dateVal}
              onChange={(e) => setDateVal(e.target.value)}
              className="w-full bg-white border border-slate-300 rounded-lg px-3 py-2 text-slate-900 font-mono text-xs focus:outline-none focus:border-brand-500 shadow-sm"
            />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-slate-700 font-bold mb-1 uppercase tracking-wider text-[10px]">
              Punch Verification #
            </label>
            <input
              type="number"
              min={1}
              max={10}
              required
              value={vNo}
              onChange={(e) => setVNo(Number(e.target.value))}
              className="w-full bg-white border border-slate-300 rounded-lg px-3 py-2 text-slate-900 font-mono text-xs focus:outline-none focus:border-brand-500 shadow-sm"
            />
          </div>

          <div>
            <label className="block text-slate-700 font-bold mb-1 uppercase tracking-wider text-[10px]">
              New Official Status
            </label>
            <select
              value={newStatus}
              onChange={(e) => setNewStatus(e.target.value)}
              className="w-full bg-white border border-slate-300 rounded-lg px-3 py-2 text-slate-900 font-mono text-xs focus:outline-none focus:border-brand-500 shadow-sm"
            >
              <option value="PRESENT">PRESENT</option>
              <option value="LATE">LATE</option>
            </select>
          </div>
        </div>

        <div>
          <label className="block text-slate-700 font-bold mb-1 uppercase tracking-wider text-[10px]">
            Mandatory Correction Reason
          </label>
          <textarea
            rows={3}
            required
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Document reasons e.g. 'Network issue at site, verified manual sign-in sheet', 'Biometric glitch verified by manager'..."
            className="w-full bg-white border border-slate-300 rounded-lg p-2.5 text-slate-900 text-xs focus:outline-none focus:border-brand-500 shadow-sm"
          />
        </div>

        <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-200">
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            className="px-4 py-2 rounded-lg bg-slate-100 hover:bg-slate-200 text-slate-700 text-xs font-semibold"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={isSubmitting}
            className="px-4 py-2 rounded-lg bg-brand-600 hover:bg-brand-500 active:bg-brand-700 text-white text-xs font-bold shadow-sm transition-colors flex items-center gap-1.5 disabled:opacity-50"
          >
            <Edit3 className="w-3.5 h-3.5" />
            <span>{isSubmitting ? 'Saving Correction...' : 'Commit Correction'}</span>
          </button>
        </div>
      </form>
    </Modal>
  );
};
