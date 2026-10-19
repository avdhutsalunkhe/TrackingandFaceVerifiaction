import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { 
  ShieldCheck, RefreshCw, Search, Filter, Clock, User, 
  AlertTriangle, CheckCircle2, XCircle, Trash2, Calendar, FileText
} from 'lucide-react';
import { API_BASE } from '../api/client';
import { useAuth } from '../context/AuthContext';

export default function AuditLogs() {
  const { isAdmin } = useAuth();
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const pageSize = 30;

  // Filters
  const [search, setSearch] = useState('');
  const [selectedAction, setSelectedAction] = useState('All');
  const [selectedCategory, setSelectedCategory] = useState('All');
  const [summary, setSummary] = useState({ today_total: 0, today_logins: 0, failed_attempts: 0 });

  const fetchLogs = async () => {
    setLoading(true);
    try {
      const res = await axios.get(`${API_BASE}/audit-logs/`, {
        params: {
          page,
          size: pageSize,
          search: search || undefined,
          action: selectedAction !== 'All' ? selectedAction : undefined,
          category: selectedCategory !== 'All' ? selectedCategory : undefined
        }
      });
      setLogs(res.data.items || []);
      setTotal(res.data.total || 0);
      if (res.data.summary) {
        setSummary(res.data.summary);
      }
    } catch (err) {
      console.error('Failed to fetch audit logs:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchLogs();
  }, [page, search, selectedAction, selectedCategory]);

  const handleClearLogs = async () => {
    if (!window.confirm('Are you sure you want to clear historical audit logs?')) return;
    try {
      await axios.delete(`${API_BASE}/audit-logs/clear`);
      fetchLogs();
    } catch (err) {
      alert('Failed to clear audit logs: ' + (err.response?.data?.detail || err.message));
    }
  };

  const getActionBadge = (action, status) => {
    if (status === 'FAILED') {
      return 'bg-rose-50 text-rose-700 border-rose-200';
    }
    if (action.includes('LOGIN')) {
      return 'bg-emerald-50 text-emerald-700 border-emerald-200';
    }
    if (action.includes('DELETE')) {
      return 'bg-rose-50 text-rose-700 border-rose-200';
    }
    if (action.includes('CREATE') || action.includes('ADD')) {
      return 'bg-blue-50 text-blue-700 border-blue-200';
    }
    if (action.includes('UPDATE') || action.includes('RESET')) {
      return 'bg-amber-50 text-amber-700 border-amber-200';
    }
    return 'bg-slate-100 text-slate-700 border-slate-200';
  };

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-6 animate-in fade-in duration-150">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-white p-6 rounded-2xl border border-slate-200 shadow-xs">
        <div>
          <div className="flex items-center gap-2.5">
            <div className="w-10 h-10 rounded-xl bg-orange-50 border border-orange-200 flex items-center justify-center text-orange-600 font-bold">
              <ShieldCheck size={22} />
            </div>
            <div>
              <h1 className="text-xl font-bold text-slate-900 tracking-tight">System Audit & Activity Logs</h1>
              <p className="text-xs text-slate-500 mt-0.5">
                Real-time security auditing for logins, updates, deletions, and policy events.
              </p>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-2.5">
          <button
            type="button"
            onClick={fetchLogs}
            disabled={loading}
            className="flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold text-slate-700 bg-slate-50 hover:bg-slate-100 border border-slate-300 rounded-xl transition-colors cursor-pointer"
          >
            <RefreshCw size={14} className={loading ? 'animate-spin text-orange-600' : ''} />
            Refresh
          </button>
          {isAdmin && (
            <button
              type="button"
              onClick={handleClearLogs}
              className="flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold text-rose-700 bg-rose-50 hover:bg-rose-100 border border-rose-200 rounded-xl transition-colors cursor-pointer"
            >
              <Trash2 size={14} />
              Clear Logs
            </button>
          )}
        </div>
      </div>

      {/* Summary KPI Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="bg-white p-5 rounded-2xl border border-slate-200 shadow-xs flex items-center justify-between">
          <div>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Events Today</p>
            <p className="text-2xl font-black text-slate-900 mt-1">{summary.today_total}</p>
            <p className="text-[11px] text-slate-400 mt-0.5">Recorded user & system actions</p>
          </div>
          <div className="w-10 h-10 rounded-xl bg-slate-100 text-slate-700 flex items-center justify-center">
            <Clock size={20} />
          </div>
        </div>

        <div className="bg-white p-5 rounded-2xl border border-slate-200 shadow-xs flex items-center justify-between">
          <div>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Successful Logins</p>
            <p className="text-2xl font-black text-emerald-600 mt-1">{summary.today_logins}</p>
            <p className="text-[11px] text-slate-400 mt-0.5">Admin & Clerk authenticated sessions</p>
          </div>
          <div className="w-10 h-10 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center">
            <CheckCircle2 size={20} />
          </div>
        </div>

        <div className="bg-white p-5 rounded-2xl border border-slate-200 shadow-xs flex items-center justify-between">
          <div>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Failed / Flagged</p>
            <p className="text-2xl font-black text-rose-600 mt-1">{summary.failed_attempts}</p>
            <p className="text-[11px] text-slate-400 mt-0.5">Bad passwords or rejected actions</p>
          </div>
          <div className="w-10 h-10 rounded-xl bg-rose-50 text-rose-600 flex items-center justify-center">
            <XCircle size={20} />
          </div>
        </div>
      </div>

      {/* Filters Bar */}
      <div className="bg-white p-4 rounded-2xl border border-slate-200 shadow-xs flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-3 flex-1">
          <div className="relative min-w-[240px] max-w-sm">
            <input
              type="text"
              placeholder="Search user, action, details..."
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setPage(1);
              }}
              className="w-full pl-9 pr-3 py-2 text-xs bg-slate-50 border border-slate-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-orange-500 text-slate-900"
            />
            <Search size={14} className="absolute left-3 top-2.5 text-slate-400" />
          </div>

          <select
            value={selectedAction}
            onChange={(e) => {
              setSelectedAction(e.target.value);
              setPage(1);
            }}
            className="px-3 py-2 text-xs bg-slate-50 border border-slate-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-orange-500 text-slate-700 font-semibold"
          >
            <option value="All">All Actions</option>
            <option value="LOGIN">LOGIN</option>
            <option value="LOGIN_FAILED">LOGIN_FAILED</option>
            <option value="CREATE_USER">CREATE_USER</option>
            <option value="BATCH_CREATE_USERS">BATCH_CREATE_USERS</option>
            <option value="UPDATE_USER">UPDATE_USER</option>
            <option value="DELETE_USER">DELETE_USER</option>
            <option value="ADMIN_RESET_PASSWORD">ADMIN_RESET_PASSWORD</option>
            <option value="PASSWORD_CHANGE">PASSWORD_CHANGE</option>
            <option value="CREATE_EMPLOYEE">CREATE_EMPLOYEE</option>
            <option value="UPDATE_EMPLOYEE">UPDATE_EMPLOYEE</option>
            <option value="DELETE_EMPLOYEE">DELETE_EMPLOYEE</option>
            <option value="CREATE_SHIFT">CREATE_SHIFT</option>
            <option value="UPDATE_SHIFT">UPDATE_SHIFT</option>
            <option value="DELETE_SHIFT">DELETE_SHIFT</option>
            <option value="UPDATE_SHIFT_RULES">UPDATE_SHIFT_RULES</option>
            <option value="CLEAR_ATTENDANCE_DATA">CLEAR_ATTENDANCE_DATA</option>
            <option value="SEED_DEMO_DATA">SEED_DEMO_DATA</option>
          </select>

          <select
            value={selectedCategory}
            onChange={(e) => {
              setSelectedCategory(e.target.value);
              setPage(1);
            }}
            className="px-3 py-2 text-xs bg-slate-50 border border-slate-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-orange-500 text-slate-700 font-semibold"
          >
            <option value="All">All Categories</option>
            <option value="auth">Auth & Security</option>
            <option value="employee">Employees</option>
            <option value="shift">Shifts & Rules</option>
            <option value="attendance">Attendance</option>
            <option value="system">System</option>
          </select>
        </div>

        <div className="text-xs text-slate-500 font-medium">
          Total Logs: <span className="font-bold text-slate-800">{total}</span>
        </div>
      </div>

      {/* Logs Table */}
      <div className="bg-white rounded-2xl border border-slate-200 shadow-xs overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs border-collapse">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200 text-slate-500 font-bold uppercase tracking-wider">
                <th className="p-3.5">TIMESTAMP</th>
                <th className="p-3.5">USER</th>
                <th className="p-3.5">ACTION</th>
                <th className="p-3.5">CATEGORY</th>
                <th className="p-3.5">DETAILS</th>
                <th className="p-3.5">IP ADDRESS</th>
                <th className="p-3.5 text-center">STATUS</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 font-medium">
              {loading ? (
                <tr>
                  <td colSpan="7" className="p-8 text-center text-slate-400">
                    Loading audit activity records...
                  </td>
                </tr>
              ) : logs.length === 0 ? (
                <tr>
                  <td colSpan="7" className="p-8 text-center text-slate-400">
                    No activity logs recorded yet. Actions like login, user management, and employee updates will appear here automatically.
                  </td>
                </tr>
              ) : (
                logs.map((log) => {
                  const badgeClass = getActionBadge(log.action, log.status);
                  const formattedTime = log.timestamp 
                    ? new Date(log.timestamp).toLocaleString() 
                    : '—';

                  return (
                    <tr key={log.id} className="hover:bg-slate-50/70 transition-colors">
                      <td className="p-3.5 font-mono text-slate-600 whitespace-nowrap">
                        {formattedTime}
                      </td>
                      <td className="p-3.5">
                        <span className="font-bold text-slate-900 flex items-center gap-1.5">
                          <User size={13} className="text-slate-400" />
                          @{log.username || 'system'}
                        </span>
                      </td>
                      <td className="p-3.5 whitespace-nowrap">
                        <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold border ${badgeClass}`}>
                          {log.action}
                        </span>
                      </td>
                      <td className="p-3.5 uppercase text-[10px] font-bold text-slate-500">
                        {log.category}
                      </td>
                      <td className="p-3.5 text-slate-700 max-w-md truncate" title={log.details}>
                        {log.details || '—'}
                      </td>
                      <td className="p-3.5 font-mono text-slate-500 whitespace-nowrap">
                        {log.ip_address || 'local'}
                      </td>
                      <td className="p-3.5 text-center">
                        <span className={`inline-flex px-2 py-0.5 rounded-full text-[10px] font-bold ${
                          log.status === 'SUCCESS' 
                            ? 'bg-emerald-50 text-emerald-700' 
                            : 'bg-rose-50 text-rose-700'
                        }`}>
                          {log.status}
                        </span>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
        {total > pageSize && (
          <div className="p-4 bg-slate-50 border-t border-slate-200 flex items-center justify-between text-xs">
            <span className="text-slate-500">
              Showing page <span className="font-bold text-slate-800">{page}</span> of {Math.ceil(total / pageSize)}
            </span>
            <div className="flex gap-2">
              <button
                type="button"
                disabled={page <= 1}
                onClick={() => setPage(page - 1)}
                className="px-3 py-1.5 bg-white border border-slate-300 rounded-lg hover:bg-slate-100 disabled:opacity-40 font-semibold"
              >
                Previous
              </button>
              <button
                type="button"
                disabled={page >= Math.ceil(total / pageSize)}
                onClick={() => setPage(page + 1)}
                className="px-3 py-1.5 bg-white border border-slate-300 rounded-lg hover:bg-slate-100 disabled:opacity-40 font-semibold"
              >
                Next
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
