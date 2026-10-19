import React, { useState, useEffect } from 'react';
import { Modal } from '../components/common/Modal';
import { api } from '../services/api';
import { StatusBadge } from '../components/common/Badge';
import { 
  User, 
  Calendar, 
  Clock, 
  MapPin, 
  ShieldAlert, 
  Smartphone, 
  History,
  CheckCircle2,
  FileCheck
} from 'lucide-react';

interface EmployeeProfileModalProps {
  isOpen: boolean;
  onClose: () => void;
  employeeId: string;
  targetDate?: string;
  onOpenCorrection?: (employeeId: string, date: string, vNo: number) => void;
}

export const EmployeeProfileModal: React.FC<EmployeeProfileModalProps> = ({
  isOpen,
  onClose,
  employeeId,
  targetDate,
  onOpenCorrection,
}) => {
  const [profile, setProfile] = useState<any | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [activeTab, setActiveTab] = useState<'today' | 'history' | 'attempts'>('today');

  useEffect(() => {
    if (isOpen && employeeId) {
      setLoading(true);
      api.getEmployeeDetail(employeeId, targetDate)
        .then((res) => {
          setProfile(res);
          setLoading(false);
        })
        .catch((err) => {
          console.error('[EmployeeDetail] Error:', err);
          setLoading(false);
        });
    }
  }, [isOpen, employeeId, targetDate]);

  if (!isOpen) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Employee Attendance Profile"
      subtitle={`Comprehensive telemetry and audit record for ${employeeId}`}
      maxWidth="max-w-4xl"
    >
      {loading ? (
        <div className="p-12 text-center text-xs text-slate-500">
          <div className="w-6 h-6 border-2 border-brand-500 border-t-transparent rounded-full animate-spin mx-auto mb-2" />
          Loading employee profile & history...
        </div>
      ) : !profile ? (
        <div className="p-8 text-center text-xs text-rose-400">
          Unable to load profile for employee '{employeeId}'.
        </div>
      ) : (
        <div className="space-y-4">
          {/* Header Profile Summary */}
          <div className="bg-slate-50 border border-slate-200 rounded-xl p-4 flex flex-col md:flex-row md:items-center justify-between gap-4 shadow-sm">
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 rounded-xl bg-gradient-to-tr from-brand-500 to-brand-700 border border-orange-200 flex items-center justify-center text-white font-bold font-mono text-base shadow-sm">
                {profile.full_name?.charAt(0) || 'E'}
              </div>
              <div>
                <h3 className="text-base font-bold text-slate-900 flex items-center gap-2">
                  <span>{profile.full_name}</span>
                  <span className="text-xs font-mono text-white bg-slate-900 px-2 py-0.5 rounded font-bold">
                    {profile.employee_id}
                  </span>
                </h3>
                <div className="text-xs text-slate-600 font-mono mt-0.5">
                  Role: <strong className="text-slate-900">{profile.role}</strong> | Status: <strong className="text-emerald-700 font-bold">{profile.is_active ? 'ACTIVE' : 'INACTIVE'}</strong>
                </div>
              </div>
            </div>

            {/* Shift Assignment Card */}
            <div className="bg-white border border-slate-200 px-4 py-2.5 rounded-lg text-xs font-mono shadow-sm">
              <span className="text-slate-500 block text-[10px] uppercase font-bold">Assigned Shift</span>
              <div className="font-bold text-slate-900 text-sm">{profile.assigned_shift?.shift_name || 'No Shift Assigned'}</div>
              <div className="text-[11px] text-slate-500 mt-0.5">
                Effective: {profile.assigned_shift?.effective_from || '--'} to {profile.assigned_shift?.effective_to || 'Ongoing'}
              </div>
            </div>
          </div>

          {/* Navigation Tabs */}
          <div className="flex items-center gap-2 border-b border-slate-200 text-xs">
            <button
              onClick={() => setActiveTab('today')}
              className={`pb-2.5 px-3.5 font-bold transition-colors border-b-2 ${
                activeTab === 'today'
                  ? 'border-brand-500 text-brand-600'
                  : 'border-transparent text-slate-500 hover:text-slate-800'
              }`}
            >
              Today's Verification Timeline ({profile.today_timeline?.length || 0})
            </button>
            <button
              onClick={() => setActiveTab('history')}
              className={`pb-2.5 px-3.5 font-bold transition-colors border-b-2 ${
                activeTab === 'history'
                  ? 'border-brand-500 text-brand-600'
                  : 'border-transparent text-slate-500 hover:text-slate-800'
              }`}
            >
              30-Day History ({profile.history?.length || 0})
            </button>
            <button
              onClick={() => setActiveTab('attempts')}
              className={`pb-2.5 px-3.5 font-bold transition-colors border-b-2 ${
                activeTab === 'attempts'
                  ? 'border-brand-500 text-brand-600'
                  : 'border-transparent text-slate-500 hover:text-slate-800'
              }`}
            >
              Telemetry Attempts ({profile.recent_attempts?.length || 0})
            </button>
          </div>

          {/* Tab 1: Today's Timeline */}
          {activeTab === 'today' && (
            <div className="space-y-3">
              {(!profile.today_timeline || profile.today_timeline.length === 0) ? (
                <div className="py-8 text-center text-xs text-slate-400 bg-white border border-slate-200 rounded-xl shadow-sm">
                  No attendance punches recorded for this employee today ({profile.selected_date}).
                </div>
              ) : (
                profile.today_timeline.map((item: any, idx: number) => (
                  <div
                    key={idx}
                    className="bg-white border border-slate-200 rounded-xl p-4 flex flex-col md:flex-row md:items-center justify-between gap-3 text-xs shadow-sm"
                  >
                    <div>
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-bold text-slate-900 font-mono">Punch #{item.verification_no}</span>
                        <span className="text-slate-500 font-mono">({item.verification_window})</span>
                        <StatusBadge status={item.status} />
                      </div>
                      <div className="text-slate-600 font-mono text-[11px] flex flex-wrap gap-x-4 gap-y-1">
                        <span>Time: <strong className="text-slate-900">{item.server_timestamp}</strong></span>
                        <span>Mode: <strong className="text-slate-900">{item.verification_mode}</strong></span>
                        <span>Source: <strong className="text-slate-900">{item.source}</strong></span>
                        <span>Device: <strong className="text-slate-900">{item.device_id}</strong></span>
                      </div>
                    </div>

                    <div className="flex items-center gap-2 font-mono text-[11px] shrink-0">
                      <span className="px-2.5 py-1 rounded-md bg-emerald-50 border border-emerald-200 text-emerald-700 font-bold">
                        Face: {item.face_result}
                      </span>
                      <span className="px-2.5 py-1 rounded-md bg-emerald-50 border border-emerald-200 text-emerald-700 font-bold">
                        Live: {item.liveness_result}
                      </span>
                      <span className="px-2.5 py-1 rounded-md bg-blue-50 border border-blue-200 text-blue-700 font-bold">
                        GPS: {item.distance_meters}m
                      </span>
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Tab 2: 30-Day History */}
          {activeTab === 'history' && (
            <div className="max-h-[50vh] overflow-y-auto border border-slate-200 rounded-xl bg-white shadow-sm">
              <table className="w-full text-left table-dense">
                <thead>
                  <tr>
                    <th>Date</th>
                    <th>Punch #</th>
                    <th>Window</th>
                    <th>Time</th>
                    <th>Status</th>
                    <th>Source</th>
                  </tr>
                </thead>
                <tbody>
                  {(!profile.history || profile.history.length === 0) ? (
                    <tr>
                      <td colSpan={6} className="text-center py-6 text-slate-400 text-xs">
                        No historical records found.
                      </td>
                    </tr>
                  ) : (
                    profile.history.map((h: any) => (
                      <tr key={h.id}>
                        <td className="font-mono text-slate-800 font-semibold">{h.date}</td>
                        <td className="font-mono text-slate-600 text-center">#{h.verification_no}</td>
                        <td className="font-mono text-slate-700">{h.window}</td>
                        <td className="font-mono text-slate-900 font-bold">{h.timestamp}</td>
                        <td>
                          <StatusBadge status={h.status} />
                        </td>
                        <td className="font-mono text-slate-700 text-[10px]">{h.source}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          )}

          {/* Tab 3: Attempts */}
          {activeTab === 'attempts' && (
            <div className="max-h-[50vh] overflow-y-auto border border-slate-200 rounded-xl bg-white shadow-sm">
              <table className="w-full text-left table-dense">
                <thead>
                  <tr>
                    <th>Timestamp</th>
                    <th>Status</th>
                    <th>Rejection Reason</th>
                    <th>GPS Distance</th>
                    <th>GPS Accuracy</th>
                    <th>Source</th>
                  </tr>
                </thead>
                <tbody>
                  {(!profile.recent_attempts || profile.recent_attempts.length === 0) ? (
                    <tr>
                      <td colSpan={6} className="text-center py-6 text-slate-400 text-xs">
                        No telemetry attempts recorded.
                      </td>
                    </tr>
                  ) : (
                    profile.recent_attempts.map((at: any) => (
                      <tr key={at.id}>
                        <td className="font-mono text-slate-800 font-semibold">{at.timestamp}</td>
                        <td>
                          <StatusBadge status={at.status} />
                        </td>
                        <td className="font-mono text-rose-600 text-xs font-bold">{at.reason}</td>
                        <td className="font-mono text-slate-700">{at.distance ? `${at.distance}m` : '--'}</td>
                        <td className="font-mono text-slate-600">{at.accuracy ? `±${at.accuracy}m` : '--'}</td>
                        <td className="font-mono text-slate-700 text-[10px]">{at.source}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          )}

          {/* Footer Actions */}
          <div className="flex items-center justify-between pt-3 border-t border-slate-200">
            {onOpenCorrection && (
              <button
                onClick={() => {
                  onClose();
                  onOpenCorrection(profile.employee_id, profile.selected_date, 1);
                }}
                className="px-3.5 py-2 rounded-lg bg-amber-50 hover:bg-amber-100 text-amber-800 border border-amber-300 text-xs font-bold transition-colors flex items-center gap-1.5 shadow-sm"
              >
                <FileCheck className="w-3.5 h-3.5" />
                Correct Today's Record
              </button>
            )}

            <button
              onClick={onClose}
              className="px-4 py-2 rounded-lg bg-slate-900 hover:bg-slate-800 text-xs text-white font-semibold transition-colors ml-auto shadow-sm"
            >
              Close
            </button>
          </div>
        </div>
      )}
    </Modal>
  );
};
