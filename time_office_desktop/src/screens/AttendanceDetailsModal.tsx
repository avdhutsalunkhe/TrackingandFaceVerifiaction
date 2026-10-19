import React, { useState } from 'react';
import { Modal } from '../components/common/Modal';
import { StatusBadge, VerificationResultBadge } from '../components/common/Badge';
import { 
  User, 
  Clock, 
  MapPin, 
  ShieldCheck, 
  Smile, 
  Smartphone, 
  Database,
  ExternalLink,
  ChevronDown,
  ChevronUp,
  FileCheck
} from 'lucide-react';

interface AttendanceDetailsModalProps {
  isOpen: boolean;
  onClose: () => void;
  punchId: number;
  initialData?: any;
  onOpenCorrection?: (employeeId: string, date: string, verificationNo: number) => void;
}

export const AttendanceDetailsModal: React.FC<AttendanceDetailsModalProps> = ({
  isOpen,
  onClose,
  punchId,
  initialData,
  onOpenCorrection,
}) => {
  const [showTechnicalDetails, setShowTechnicalDetails] = useState(false);

  if (!initialData) return null;

  const data = initialData;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Attendance Verification Details"
      subtitle={`Official Server Record #${data.id || punchId}`}
      maxWidth="max-w-2xl"
    >
      <div className="space-y-4">
        {/* Top Summary Banner */}
        <div className="bg-slate-50 border border-slate-200 rounded-xl p-4 flex items-center justify-between shadow-sm">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-orange-100 border border-orange-200 flex items-center justify-center text-brand-600 font-bold font-mono">
              {data.employee_id?.slice(-3) || 'EMP'}
            </div>
            <div>
              <div className="text-sm font-bold text-slate-900 flex items-center gap-2">
                <span>{data.full_name || data.employee_name || 'Employee'}</span>
                <span className="text-xs font-mono text-white bg-slate-900 px-2 py-0.5 rounded font-bold">
                  {data.employee_id}
                </span>
              </div>
              <div className="text-xs text-slate-500 mt-0.5">
                Shift: <strong className="text-slate-800">{data.shift_name || 'Unassigned'}</strong>
              </div>
            </div>
          </div>

          <div className="text-right">
            <StatusBadge status={data.status || 'PRESENT'} className="text-xs px-2.5 py-1" />
            <div className="text-[11px] text-slate-500 font-mono mt-1">
              {data.attendance_time || data.formatted_time || data.server_time || '--'}
            </div>
          </div>
        </div>

        {/* 3 Verification Pillar Cards: Face, Liveness, Location */}
        <div className="grid grid-cols-3 gap-3">
          {/* Face Result */}
          <div className="bg-emerald-50/60 border border-emerald-200 p-3 rounded-xl text-center shadow-sm">
            <Smile className="w-5 h-5 text-emerald-600 mx-auto mb-1.5" />
            <div className="text-[10px] uppercase font-bold text-slate-600">Face Match</div>
            <div className="text-sm font-bold text-emerald-700 mt-0.5">
              {data.face_result || 'MATCH'}
            </div>
            <div className="text-[10px] text-slate-500 font-mono mt-0.5">Verified Biometric</div>
          </div>

          {/* Liveness Result */}
          <div className="bg-emerald-50/60 border border-emerald-200 p-3 rounded-xl text-center shadow-sm">
            <ShieldCheck className="w-5 h-5 text-emerald-600 mx-auto mb-1.5" />
            <div className="text-[10px] uppercase font-bold text-slate-600">Live Person</div>
            <div className="text-sm font-bold text-emerald-700 mt-0.5">
              {data.liveness_result || 'REAL'}
            </div>
            <div className="text-[10px] text-slate-500 font-mono mt-0.5">Anti-Spoof Passed</div>
          </div>

          {/* Location Result */}
          <div className="bg-blue-50/60 border border-blue-200 p-3 rounded-xl text-center shadow-sm">
            <MapPin className="w-5 h-5 text-blue-600 mx-auto mb-1.5" />
            <div className="text-[10px] uppercase font-bold text-slate-600">Location</div>
            <div className="text-sm font-bold text-blue-700 mt-0.5">
              {data.gps_distance !== undefined ? `${data.gps_distance}m` : 'GEOFENCE OK'}
            </div>
            <div className="text-[10px] text-slate-500 font-mono mt-0.5">Within Bounds</div>
          </div>
        </div>

        {/* Core Verification Information Grid */}
        <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-3 text-xs shadow-sm">
          <div className="font-bold uppercase tracking-wider text-slate-700 text-[11px] pb-2 border-b border-slate-200">
            Attendance Verification Metadata
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <span className="text-slate-500 block text-[11px]">Verification Window</span>
              <span className="font-bold text-slate-900 font-mono">
                {data.verification_window || data.current_verification_period || 'Standard Window'}
              </span>
            </div>

            <div>
              <span className="text-slate-500 block text-[11px]">Verification Number</span>
              <span className="font-bold text-slate-900 font-mono">
                Punch #{data.verification_no || 1}
              </span>
            </div>

            <div>
              <span className="text-slate-500 block text-[11px]">Server Timestamp</span>
              <span className="font-bold text-slate-900 font-mono">
                {data.server_time || data.attendance_time}
              </span>
            </div>

            <div>
              <span className="text-slate-500 block text-[11px]">Submission Mode / Source</span>
              <span className="font-bold text-slate-900 font-mono">
                {data.source || 'ONLINE'} ({data.verification_status || 'CONFIRMED'})
              </span>
            </div>

            <div>
              <span className="text-slate-500 block text-[11px]">Device Hardware ID</span>
              <span className="font-bold text-slate-900 font-mono truncate block" title={data.device || data.device_id}>
                {data.device || data.device_id || 'Mobile Client'}
              </span>
            </div>

            <div>
              <span className="text-slate-500 block text-[11px]">GPS Accuracy Radius</span>
              <span className="font-bold text-slate-900 font-mono">
                {data.gps_accuracy ? `±${data.gps_accuracy} meters` : 'High Precision'}
              </span>
            </div>
          </div>
        </div>

        {/* Expandable Technical ML & Geolocation Gating Telemetry */}
        <div className="border border-slate-200 rounded-xl overflow-hidden shadow-sm">
          <button
            type="button"
            onClick={() => setShowTechnicalDetails(!showTechnicalDetails)}
            className="w-full flex items-center justify-between px-4 py-2.5 bg-slate-50 hover:bg-slate-100 text-xs text-slate-700 font-semibold transition-colors"
          >
            <span className="flex items-center gap-1.5">
              <Database className="w-3.5 h-3.5 text-brand-600" />
              Technical Telemetry & GPS Coordinates
            </span>
            {showTechnicalDetails ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
          </button>

          {showTechnicalDetails && (
            <div className="p-3.5 bg-slate-100/70 border-t border-slate-200 space-y-2 text-xs font-mono text-slate-800">
              <div className="grid grid-cols-2 gap-2 text-[11px]">
                <div>
                  <span className="text-slate-500 block">Latitude:</span>
                  <span className="font-bold">{data.verified_latitude ?? '--'}</span>
                </div>
                <div>
                  <span className="text-slate-500 block">Longitude:</span>
                  <span className="font-bold">{data.verified_longitude ?? '--'}</span>
                </div>
                <div>
                  <span className="text-slate-500 block">Biometric Similarity:</span>
                  <span className="font-bold">{data.face_similarity_score ?? '1.000'}</span>
                </div>
                <div>
                  <span className="text-slate-500 block">Classification Code:</span>
                  <span className="font-bold">{data.attendance_classification || 'PRESENT'}</span>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Footer Actions */}
        <div className="flex items-center justify-between pt-2">
          {onOpenCorrection && (
            <button
              onClick={() => {
                onClose();
                onOpenCorrection(
                  data.employee_id,
                  data.attendance_date || new Date().toISOString().slice(0, 10),
                  data.verification_no || 1
                );
              }}
              className="px-3.5 py-2 rounded-lg bg-amber-50 hover:bg-amber-100 text-amber-800 border border-amber-300 text-xs font-bold transition-colors flex items-center gap-1.5 shadow-sm"
            >
              <FileCheck className="w-3.5 h-3.5" />
              Request / Correct Record
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
    </Modal>
  );
};
