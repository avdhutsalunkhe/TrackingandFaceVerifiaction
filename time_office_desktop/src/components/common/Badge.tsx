import React from 'react';
import { CheckCircle2, Clock, AlertTriangle, XCircle, ShieldAlert, Sparkles } from 'lucide-react';

interface BadgeProps {
  status: string;
  className?: string;
}

export const StatusBadge: React.FC<BadgeProps> = ({ status, className = '' }) => {
  const norm = (status || '').toUpperCase();

  if (norm === 'PRESENT' || norm === 'CONFIRMED' || norm === 'SUCCESS' || norm === 'APPROVED') {
    return (
      <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-semibold uppercase tracking-wider bg-emerald-500/15 text-emerald-400 border border-emerald-500/30 ${className}`}>
        <CheckCircle2 className="w-3 h-3 text-emerald-400" />
        {norm}
      </span>
    );
  }

  if (norm === 'LATE' || norm === 'REVIEW_REQUIRED' || norm === 'UPCOMING') {
    return (
      <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-semibold uppercase tracking-wider bg-amber-500/15 text-amber-400 border border-amber-500/30 ${className}`}>
        <Clock className="w-3 h-3 text-amber-400" />
        {norm}
      </span>
    );
  }

  if (norm === 'NOT_MARKED' || norm === 'REJECTED' || norm === 'WINDOW_EXPIRED' || norm === 'SPOOF') {
    return (
      <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-semibold uppercase tracking-wider bg-rose-500/15 text-rose-400 border border-rose-500/30 ${className}`}>
        <XCircle className="w-3 h-3 text-rose-400" />
        {norm}
      </span>
    );
  }

  if (norm === 'PENDING' || norm === 'ACTIVE_NOW' || norm === 'WINDOW_OPEN') {
    return (
      <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-semibold uppercase tracking-wider bg-blue-500/15 text-blue-400 border border-blue-500/30 ${className}`}>
        <span className="w-1.5 h-1.5 rounded-full bg-blue-400 animate-pulse" />
        {norm}
      </span>
    );
  }

  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium bg-slate-800 text-slate-300 border border-slate-700 ${className}`}>
      {norm}
    </span>
  );
};

export const VerificationResultBadge: React.FC<{ label: string; passed: boolean }> = ({ label, passed }) => {
  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium border ${
        passed
          ? 'bg-emerald-950/40 text-emerald-300 border-emerald-800/60'
          : 'bg-rose-950/40 text-rose-300 border-rose-800/60'
      }`}
    >
      {passed ? <CheckCircle2 className="w-3 h-3 text-emerald-400" /> : <ShieldAlert className="w-3 h-3 text-rose-400" />}
      {label}
    </span>
  );
};
