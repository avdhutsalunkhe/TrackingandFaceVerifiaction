import React, { useState, useEffect } from 'react';
import { api } from '../services/api';
import { AuditLogItem } from '../types';
import { ExportButtons } from '../components/common/ExportButtons';
import { 
  History, 
  ChevronLeft, 
  ChevronRight
} from 'lucide-react';

export const AuditLogScreen: React.FC = () => {
  const [logs, setLogs] = useState<AuditLogItem[]>([]);
  const [total, setTotal] = useState<number>(0);
  const [loading, setLoading] = useState<boolean>(true);
  const [actionFilter, setActionFilter] = useState<string>('');
  const [page, setPage] = useState<number>(1);
  const pageSize = 50;

  useEffect(() => {
    let isMounted = true;
    setLoading(true);

    api.getAuditLogs({
      action: actionFilter || undefined,
      page,
      page_size: pageSize,
    })
      .then((res) => {
        if (isMounted) {
          setLogs(res.records || []);
          setTotal(res.total || 0);
          setLoading(false);
        }
      })
      .catch((err) => {
        console.error('[AuditLog] Error:', err);
        if (isMounted) setLoading(false);
      });

    return () => {
      isMounted = false;
    };
  }, [actionFilter, page]);

  const totalPages = Math.ceil(total / pageSize) || 1;

  return (
    <div className="p-6 space-y-5 bg-[#090d16] min-h-screen text-slate-200">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-[#111622] p-5 rounded-2xl border border-[#1e2638] shadow-lg">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2.5 tracking-tight">
            <History className="w-6 h-6 text-[#f95700]" />
            <span>Time Office Operational & Security Audit Trail</span>
          </h2>
          <p className="text-xs text-slate-400 mt-1">
            Immutable log of all user logins, attendance corrections, request approvals and system telemetry
          </p>
        </div>

        <ExportButtons
          data={logs.map((l) => ({
            'Log ID': l.id,
            'Timestamp': l.timestamp,
            'Action': l.action,
            'Operator': l.actor,
            'Operator ID': l.actor_employee_id || '--',
            'Target': l.target,
            'Target ID': l.target_employee_id || '--',
            'IP Address': l.ip_address,
            'Details': JSON.stringify(l.details || {})
          }))}
          fileName="TimeOffice_Audit_Trail"
        />
      </div>

      {/* Filter Bar */}
      <div className="flex flex-wrap items-center justify-between gap-3 bg-[#111622] p-4 rounded-xl border border-[#1e2638] text-xs shadow-md">
        <div className="flex items-center gap-3">
          <select
            value={actionFilter}
            onChange={(e) => {
              setActionFilter(e.target.value);
              setPage(1);
            }}
            className="bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-xs font-mono text-white focus:outline-none focus:border-[#f95700]"
          >
            <option value="">All Audit Actions</option>
            <option value="TIME_OFFICE_CORRECT_ATTENDANCE">TIME_OFFICE_CORRECT_ATTENDANCE</option>
            <option value="TIME_OFFICE_APPROVE_REQUEST">TIME_OFFICE_APPROVE_REQUEST</option>
            <option value="TIME_OFFICE_REJECT_REQUEST">TIME_OFFICE_REJECT_REQUEST</option>
            <option value="USER_LOGIN_SUCCESS">USER_LOGIN_SUCCESS</option>
            <option value="PASSWORD_CHANGED">PASSWORD_CHANGED</option>
            <option value="ATTENDANCE_ATTEMPT_REJECTED">ATTENDANCE_ATTEMPT_REJECTED</option>
          </select>
        </div>

        {/* Counter & Pagination controls */}
        <div className="flex items-center gap-3">
          <span className="text-slate-400 font-mono text-xs">
            Logs: <strong className="text-white">{total}</strong>
          </span>

          <div className="flex items-center gap-1 border border-[#242f48] rounded-xl bg-[#0c1018] px-1 py-0.5">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page <= 1}
              className="p-1 text-slate-400 hover:text-white disabled:opacity-30 rounded"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            <span className="text-[11px] font-mono px-2 text-slate-300">
              {page} / {totalPages}
            </span>
            <button
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={page >= totalPages}
              className="p-1 text-slate-400 hover:text-white disabled:opacity-30 rounded"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      {/* Main Table */}
      <div className="bg-[#111622] border border-[#1e2638] rounded-2xl overflow-hidden shadow-lg">
        <div className="overflow-x-auto max-h-[64vh]">
          <table className="w-full text-left table-dense">
            <thead>
              <tr>
                <th>Log ID</th>
                <th>Timestamp</th>
                <th>Action</th>
                <th>Actor (Operator)</th>
                <th>Target Employee</th>
                <th>Audit Details</th>
                <th>IP Address</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={7} className="text-center py-16 text-slate-400 text-xs font-mono">
                    <div className="w-7 h-7 border-2 border-[#f95700] border-t-transparent rounded-full animate-spin mx-auto mb-3" />
                    Querying audit logs...
                  </td>
                </tr>
              ) : logs.length === 0 ? (
                <tr>
                  <td colSpan={7} className="text-center py-16 text-slate-400 text-xs">
                    No audit records found matching criteria.
                  </td>
                </tr>
              ) : (
                logs.map((l) => (
                  <tr key={l.id}>
                    <td className="font-mono text-slate-400 font-bold">#{l.id}</td>
                    <td className="font-mono text-slate-300">{l.timestamp}</td>
                    <td>
                      <span className="font-mono text-[11px] font-bold px-2.5 py-0.5 rounded-full bg-[#f95700]/10 text-[#f95700] border border-[#f95700]/30 inline-block">
                        {l.action}
                      </span>
                    </td>
                    <td className="text-white font-semibold">
                      {l.actor} {l.actor_employee_id && <span className="font-mono text-[11px] text-[#f95700]">({l.actor_employee_id})</span>}
                    </td>
                    <td className="text-slate-200">
                      {l.target} {l.target_employee_id && <span className="font-mono text-[11px] text-slate-400">({l.target_employee_id})</span>}
                    </td>
                    <td className="font-mono text-[11px] text-slate-300 max-w-xs truncate" title={JSON.stringify(l.details)}>
                      {l.details ? JSON.stringify(l.details) : '--'}
                    </td>
                    <td className="font-mono text-slate-400 text-[11px]">{l.ip_address}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default AuditLogScreen;
