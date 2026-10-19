import React, { useState, useEffect } from 'react';
import { useTimeOffice } from '../context/TimeOfficeContext';
import { api, BACKEND_URLS, isElectronApp } from '../services/api';
import { 
  Settings as SettingsIcon, 
  Server, 
  Clock, 
  ShieldCheck, 
  CheckCircle2, 
  XCircle, 
  Activity,
  Cpu
} from 'lucide-react';

export const SettingsScreen: React.FC = () => {
  const { activeBaseUrl, serverTime, connectionStatus, triggerRefresh } = useTimeOffice();
  const [candidateStatuses, setCandidateStatuses] = useState<Record<string, { status: string; latency?: number }>>({});
  const [testing, setTesting] = useState<boolean>(false);

  const testAllCandidates = async () => {
    setTesting(true);
    const results: Record<string, { status: string; latency?: number }> = {};
    for (const url of BACKEND_URLS) {
      const start = Date.now();
      try {
        const res = await fetch(`${url}/api/user/server-time`, { signal: AbortSignal.timeout(3000) });
        if (res.ok) {
          const lat = Date.now() - start;
          results[url] = { status: 'ONLINE', latency: lat };
        } else {
          results[url] = { status: `HTTP ${res.status}` };
        }
      } catch {
        results[url] = { status: 'UNREACHABLE' };
      }
    }
    setCandidateStatuses(results);
    setTesting(false);
  };

  useEffect(() => {
    testAllCandidates();
  }, []);

  const handleSelectEndpoint = (url: string) => {
    api.setBaseUrl(url);
    triggerRefresh();
  };

  return (
    <div className="max-w-3xl mx-auto space-y-5 animate-in fade-in duration-150">
      {/* Header */}
      <div className="bg-white border border-slate-200 p-5 rounded-xl shadow-sm">
        <h2 className="text-base font-bold text-slate-900 flex items-center gap-2">
          <SettingsIcon className="w-5 h-5 text-brand-600" />
          <span>Time Office Desktop Console Settings & Network Telemetry</span>
        </h2>
        <p className="text-xs text-slate-500 mt-1">
          Endpoint failover routing, server time synchronization and architectural security configurations
        </p>
      </div>

      {/* Backend Failover Network Status */}
      <div className="bg-white border border-slate-200 rounded-xl p-5 space-y-4 shadow-sm">
        <div className="flex items-center justify-between pb-3 border-b border-slate-200">
          <div className="flex items-center gap-2">
            <Server className="w-4 h-4 text-brand-600" />
            <h3 className="text-xs font-bold uppercase tracking-wider text-slate-800">
              Backend API Failover Candidates
            </h3>
          </div>
          <button
            onClick={testAllCandidates}
            disabled={testing}
            className="px-3 py-1.5 text-xs rounded-lg bg-slate-100 hover:bg-slate-200 text-brand-700 font-semibold border border-slate-300 disabled:opacity-50 transition-colors"
          >
            {testing ? 'Testing Pings...' : 'Re-test Latency'}
          </button>
        </div>

        <div className="space-y-2.5">
          {BACKEND_URLS.map((url) => {
            const isActive = activeBaseUrl === url;
            const res = candidateStatuses[url];

            return (
              <div
                key={url}
                className={`p-3.5 rounded-lg border flex items-center justify-between transition-colors ${
                  isActive
                    ? 'bg-orange-50/70 border-brand-400 ring-1 ring-brand-400/50'
                    : 'bg-slate-50/70 border-slate-200 hover:border-slate-300'
                }`}
              >
                <div className="flex items-center gap-3">
                  <div className={`w-3 h-3 rounded-full ${res?.status === 'ONLINE' ? 'bg-emerald-500 animate-pulse' : 'bg-slate-400'}`} />
                  <div>
                    <span className="font-mono text-xs font-bold text-slate-900">{url}</span>
                    <span className="text-[10px] text-slate-500 ml-2 font-mono">
                      {url.includes('115.244') ? '(Public Primary)' : url.includes('182.66') ? '(Public Secondary)' : url.includes('192.168') ? '(Office LAN)' : '(Local Dev)'}
                    </span>
                  </div>
                </div>

                <div className="flex items-center gap-4">
                  {res ? (
                    <span className={`text-xs font-mono font-bold ${res.status === 'ONLINE' ? 'text-emerald-700' : 'text-rose-600'}`}>
                      {res.status === 'ONLINE' ? `${res.latency}ms ping` : res.status}
                    </span>
                  ) : (
                    <span className="text-xs text-slate-400 font-mono">Pinging...</span>
                  )}

                  {!isActive && res?.status === 'ONLINE' && (
                    <button
                      onClick={() => handleSelectEndpoint(url)}
                      className="px-2.5 py-1 text-[11px] rounded-md bg-slate-900 hover:bg-brand-600 text-white font-semibold transition-colors shadow-sm"
                    >
                      Switch to This
                    </button>
                  )}

                  {isActive && (
                    <span className="px-2.5 py-0.5 rounded bg-brand-500 text-white text-[10px] font-bold font-mono shadow-sm">
                      ACTIVE
                    </span>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Architecture & Security Summary */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Time Authoritativeness */}
        <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-2 text-xs shadow-sm">
          <div className="flex items-center gap-2 text-brand-600 font-bold uppercase text-[11px]">
            <Clock className="w-4 h-4" />
            <span>Server Time Authority</span>
          </div>
          <p className="text-slate-600 leading-relaxed">
            Attendance status and verification windows are strictly governed by the backend server clock configured for <strong className="text-slate-900">{serverTime?.timezone || 'Asia/Kolkata'}</strong>. Local desktop PC time is never used for attendance decisions.
          </p>
          <div className="pt-2 border-t border-slate-200 font-mono text-[11px] text-slate-700">
            Current Server Date: <strong className="text-brand-600 font-bold">{serverTime?.server_date || '--'}</strong>
          </div>
        </div>

        {/* Database & RBAC Isolation */}
        <div className="bg-white border border-slate-200 rounded-xl p-4 space-y-2 text-xs shadow-sm">
          <div className="flex items-center gap-2 text-emerald-600 font-bold uppercase text-[11px]">
            <ShieldCheck className="w-4 h-4" />
            <span>Security & Zero-Direct DB Access</span>
          </div>
          <p className="text-slate-600 leading-relaxed">
            This application connects exclusively through authenticated REST APIs with cryptographic JWT Bearer tokens and role-based access control (<strong className="text-slate-900">TIME_OFFICE</strong>). Database credentials are never stored in this application.
          </p>
          <div className="pt-2 border-t border-slate-200 font-mono text-[11px] text-slate-700">
            Runtime Platform: <strong className="text-emerald-700 font-bold">{isElectronApp() ? 'Windows Native Desktop (Electron)' : 'Enterprise Web Browser Console'}</strong>
          </div>
        </div>
      </div>
    </div>
  );
};
