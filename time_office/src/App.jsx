import React, { useState, useEffect } from 'react';
import { HashRouter, Routes, Route, NavLink, Navigate } from 'react-router-dom';
import { 
  Users, FileDown, Calendar, FileText, Settings as SettingsIcon, 
  Activity, Sparkles, CheckCircle2, ShieldCheck, ChevronRight, 
  Server, Globe, RefreshCw, X, CalendarClock, LogOut, UserCheck, KeyRound, Clock
} from 'lucide-react';
import axios from 'axios';

import { AuthProvider, useAuth } from './context/AuthContext';
import logoImg from './assets/logo.png';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Employees from './pages/Employees';
import Imports from './pages/Imports';
import DailyAttendance from './pages/DailyAttendance';
import MonthlyReports from './pages/MonthlyReports';
import Settings from './pages/Settings';
import Leaves from './pages/Leaves';
import AuditLogs from './pages/AuditLogs';

import { pingBackend, BACKEND_URL, setBackendUrl, DEFAULT_BACKEND_URL, API_BASE } from './api/client';


function ServerConfigModal({ isOpen, onClose, currentUrl, onSave, onCheck, isChecking }) {
  const [inputUrl, setInputUrl] = useState(currentUrl);

  useEffect(() => {
    setInputUrl(currentUrl);
  }, [currentUrl]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4 animate-in fade-in duration-150">
      <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 w-full max-w-md overflow-hidden">
        <div className="px-6 py-4 bg-slate-900 text-white flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="p-1.5 rounded-lg bg-orange-500/20 text-orange-400">
              <Server size={18} />
            </div>
            <div>
              <h3 className="text-sm font-bold text-white">Backend Server Connection</h3>
              <p className="text-[11px] text-slate-400">Configure Report API target host & port</p>
            </div>
          </div>
          <button onClick={onClose} className="p-1 text-slate-400 hover:text-white rounded-lg hover:bg-slate-800 transition-colors cursor-pointer">
            <X size={18} />
          </button>
        </div>

        <div className="p-6 space-y-4">
          <div>
            <label className="block text-xs font-bold text-slate-700 mb-1.5">
              API Server URL
            </label>
            <div className="flex gap-2">
              <input
                type="text"
                value={inputUrl}
                onChange={(e) => setInputUrl(e.target.value)}
                placeholder="http://182.66.233.66:8073"
                className="flex-1 px-3.5 py-2 text-xs border border-slate-300 rounded-xl font-mono focus:ring-2 focus:ring-orange-500 focus:outline-none"
              />
            </div>
            <p className="text-[11px] text-slate-500 mt-1.5">
              Default Target: <code className="bg-slate-100 px-1 py-0.5 rounded text-orange-700 font-bold">{DEFAULT_BACKEND_URL}</code>
            </p>
          </div>

          <div className="bg-slate-50 border border-slate-200 rounded-xl p-3 space-y-2 text-xs">
            <div className="font-semibold text-slate-700 flex items-center gap-1.5">
              <Globe size={14} className="text-slate-400" /> Connection Quick Presets:
            </div>
            <div className="grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => setInputUrl('http://182.66.233.66:8073')}
                className="px-2.5 py-1.5 text-[11px] font-mono text-left bg-white border border-slate-200 hover:border-orange-400 hover:bg-orange-50/50 rounded-lg text-slate-700 transition-colors"
              >
                182.66.233.66:8073
                <span className="block text-[9px] text-slate-400 font-sans">Remote / Public</span>
              </button>
              <button
                type="button"
                onClick={() => setInputUrl('http://127.0.0.1:8073')}
                className="px-2.5 py-1.5 text-[11px] font-mono text-left bg-white border border-slate-200 hover:border-orange-400 hover:bg-orange-50/50 rounded-lg text-slate-700 transition-colors"
              >
                127.0.0.1:8073
                <span className="block text-[9px] text-slate-400 font-sans">Local Machine</span>
              </button>
            </div>
          </div>

          <div className="flex items-center justify-end gap-2.5 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition-colors cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={() => {
                onSave(inputUrl);
                onClose();
              }}
              className="px-4 py-2 text-xs font-bold bg-orange-600 hover:bg-orange-700 text-white rounded-xl shadow-xs transition-colors cursor-pointer"
            >
              Save & Connect
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function ChangePasswordModal({ isOpen, onClose, username }) {
  const [oldPassword, setOldPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(null);

  if (!isOpen) return null;

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (newPassword.length < 4) {
      setError('New password must be at least 4 characters');
      return;
    }
    if (newPassword !== confirmPassword) {
      setError('Passwords do not match');
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const res = await axios.post(`${API_BASE}/auth/change-password`, {
        username,
        old_password: oldPassword,
        new_password: newPassword
      });

      if (res.data && res.data.success) {
        setSuccess('Password updated successfully! 15-day reset timer renewed.');
        setTimeout(() => {
          onClose();
          window.location.reload();
        }, 1200);
      }
    } catch (err) {
      setError(err.response?.data?.detail || err.message || 'Failed to update password');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4 animate-in fade-in">
      <div className="bg-white rounded-2xl shadow-xl border border-slate-200 w-full max-w-md overflow-hidden">
        <div className="px-6 py-4 bg-slate-900 text-white flex items-center justify-between">
          <div className="flex items-center gap-2">
            <KeyRound size={18} className="text-orange-400" />
            <h3 className="text-sm font-bold text-white">Change Account Password</h3>
          </div>
          <button onClick={onClose} className="p-1 text-slate-400 hover:text-white rounded-lg cursor-pointer">
            <X size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-4 text-xs">
          <div className="p-3 bg-orange-50 border border-orange-200 rounded-xl text-orange-800 text-[11px] leading-relaxed">
            <span className="font-bold">15-Day Policy Notice:</span> Updating your password will renew your 15-day timer.
          </div>

          {error && (
            <div className="p-3 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 font-semibold">
              {error}
            </div>
          )}

          {success && (
            <div className="p-3 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-800 font-semibold">
              {success}
            </div>
          )}

          <div>
            <label className="block font-semibold text-slate-700 mb-1">Current Password *</label>
            <input
              type="password"
              required
              value={oldPassword}
              onChange={(e) => setOldPassword(e.target.value)}
              placeholder="••••••••"
              className="w-full p-2.5 bg-slate-50 border border-slate-300 rounded-lg text-slate-900 focus:bg-white"
            />
          </div>

          <div>
            <label className="block font-semibold text-slate-700 mb-1">New Password *</label>
            <input
              type="password"
              required
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              placeholder="Minimum 4 characters"
              className="w-full p-2.5 bg-slate-50 border border-slate-300 rounded-lg text-slate-900 focus:bg-white"
            />
          </div>

          <div>
            <label className="block font-semibold text-slate-700 mb-1">Confirm New Password *</label>
            <input
              type="password"
              required
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              placeholder="Repeat new password"
              className="w-full p-2.5 bg-slate-50 border border-slate-300 rounded-lg text-slate-900 focus:bg-white"
            />
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-slate-600 hover:bg-slate-100 rounded-xl font-semibold cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={loading}
              className="px-4 py-2 bg-orange-600 hover:bg-orange-700 text-white font-bold rounded-xl shadow-xs transition-colors cursor-pointer disabled:opacity-50"
            >
              {loading ? 'Saving...' : 'Update Password'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

function Sidebar({ backendOnline, isChecking, onRetry, onOpenConfig, onOpenPasswordModal, activeUrl }) {
  const { currentUser, logout, isAdmin } = useAuth();

  const navItems = [
    { to: '/', label: 'Dashboard', icon: Activity },
    { to: '/leaves', label: 'Leaves & Absences', icon: CalendarClock },
    { to: '/daily', label: 'Daily Attendance', icon: Calendar },
    { to: '/employees', label: 'Employees', icon: Users },
    { to: '/imports', label: 'Data Imports', icon: FileDown },
    { to: '/reports', label: 'Monthly Reports', icon: FileText },
    ...(isAdmin ? [{ to: '/audit-logs', label: 'Audit & Activity Logs', icon: ShieldCheck }] : []),
    { to: '/settings', label: 'Settings & Policy', icon: SettingsIcon },
  ];

  const daysLeft = currentUser?.days_until_expiration ?? 15;
  const isExpired = currentUser?.is_password_expired;

  return (
    <aside className="w-64 bg-slate-900 border-r border-slate-800 flex flex-col justify-between shrink-0 select-none">
      <div>
        {/* Brand Header */}
        <div className="p-5 border-b border-slate-800/80">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-white flex items-center justify-center p-1 shadow-md shadow-brand-500/20 overflow-hidden shrink-0">
              <img 
                src={logoImg} 
                alt="Report" 
                onError={(e) => {
                  e.currentTarget.onerror = null;
                  e.currentTarget.src = './logo.png';
                }}
                className="w-full h-full object-contain rounded-lg" 
              />
            </div>
            <div>
              <h2 className="text-base font-bold text-white tracking-tight">REPORT</h2>
              <p className="text-[10px] text-slate-400 font-medium uppercase tracking-wider">Attendance Intelligence</p>
            </div>
          </div>
        </div>

        {/* User Profile Card */}
        <div className="px-4 py-3 border-b border-slate-800/80 bg-slate-950/30 space-y-2">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5 overflow-hidden">
              <div className={`w-8 h-8 rounded-xl flex items-center justify-center font-bold text-xs shrink-0 ${
                isAdmin ? 'bg-orange-500/20 text-orange-400 border border-orange-500/30' : 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
              }`}>
                {isAdmin ? <ShieldCheck size={16} /> : <UserCheck size={16} />}
              </div>
              <div className="truncate">
                <div className="text-xs font-bold text-white truncate">{currentUser?.full_name || 'Staff User'}</div>
                <div className="flex items-center gap-1.5 mt-0.5">
                  <span className={`px-1.5 py-0.2 rounded text-[9px] font-bold uppercase tracking-wider ${
                    isAdmin ? 'bg-orange-500/20 text-orange-300' : 'bg-emerald-500/20 text-emerald-300'
                  }`}>
                    {currentUser?.role || 'User'}
                  </span>
                  <span className="text-[10px] text-slate-400 font-mono">@{currentUser?.username}</span>
                </div>
              </div>
            </div>
            <button
              onClick={logout}
              title="Sign out of system"
              className="p-1.5 text-slate-400 hover:text-rose-400 hover:bg-slate-800 rounded-lg transition-colors cursor-pointer"
            >
              <LogOut size={15} />
            </button>
          </div>

          {/* 15-Day Password Indicator & Reset Shortcut */}
          <div className="flex items-center justify-between pt-1 text-[10px] text-slate-400 border-t border-slate-800/60">
            <div className="flex items-center gap-1">
              <Clock size={11} className={isExpired ? 'text-rose-400' : 'text-orange-400'} />
              <span>Pass: {isExpired ? <span className="text-rose-400 font-bold">Expired</span> : `${daysLeft}d left`}</span>
            </div>
            <button
              type="button"
              onClick={onOpenPasswordModal}
              title="Change Password (renews 15-day period)"
              className="flex items-center gap-1 text-orange-400 hover:text-orange-300 font-medium hover:underline cursor-pointer"
            >
              <KeyRound size={11} />
              Reset
            </button>
          </div>
        </div>

        {/* Navigation Links */}
        <nav className="p-4 space-y-1.5">
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.to === '/'}
                className={({ isActive }) =>
                  `flex items-center justify-between px-3.5 py-2.5 rounded-xl text-xs font-semibold transition-all group ${
                    isActive
                      ? 'bg-brand-600 text-white shadow-sm shadow-brand-600/30 font-bold'
                      : 'text-slate-400 hover:text-white hover:bg-slate-800/60'
                  }`
                }
              >
                {({ isActive }) => (
                  <>
                    <div className="flex items-center gap-3">
                      <Icon size={17} className={isActive ? 'text-white' : 'text-slate-400 group-hover:text-slate-200'} />
                      <span>{item.label}</span>
                    </div>
                    {isActive && <div className="w-1.5 h-1.5 rounded-full bg-white" />}
                  </>
                )}
              </NavLink>
            );
          })}
        </nav>
      </div>


      {/* Footer / System Status */}
      <div className="p-4 border-t border-slate-800/80 bg-slate-950/40 space-y-2">
        <div className="flex items-center justify-between px-1">
          <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider">Server Link</span>
          <button
            onClick={onOpenConfig}
            title="Configure Backend URL"
            className="text-[10px] text-orange-400 hover:text-orange-300 font-mono hover:underline cursor-pointer"
          >
            Config
          </button>
        </div>

        <button
          onClick={onRetry}
          disabled={isChecking}
          title="Click to re-check backend connection"
          className="w-full flex items-center justify-between px-3 py-2 rounded-lg bg-slate-900 border border-slate-800 hover:border-slate-700 transition-colors text-left cursor-pointer"
        >
          <div className="flex items-center gap-2 overflow-hidden">
            <span
              className={`w-2.5 h-2.5 rounded-full shrink-0 ${
                backendOnline === true
                  ? 'bg-emerald-500 shadow-sm shadow-emerald-500/50'
                  : backendOnline === false
                  ? 'bg-rose-500 shadow-sm shadow-rose-500/50'
                  : 'bg-amber-500 animate-pulse'
              }`}
            />
            <div className="truncate">
              <div className="text-[11px] font-semibold text-slate-200 truncate">
                {backendOnline === true
                  ? 'Connected'
                  : backendOnline === false
                  ? 'Disconnected'
                  : 'Connecting...'}
              </div>
              <div className="text-[9px] font-mono text-slate-400 truncate">
                {activeUrl ? activeUrl.replace(/^https?:\/\//, '') : '182.66.233.66:8073'}
              </div>
            </div>
          </div>
          <RefreshCw size={13} className={`text-slate-500 shrink-0 ${isChecking ? 'animate-spin text-orange-400' : ''}`} />
        </button>
      </div>
    </aside>
  );
}

function MainApp() {
  const { isAuthenticated, currentUser } = useAuth();
  const [backendOnline, setBackendOnline] = useState(null);
  const [isChecking, setIsChecking] = useState(false);
  const [lastChecked, setLastChecked] = useState(null);
  const [activeUrl, setActiveUrl] = useState(BACKEND_URL);
  const [statusNotice, setStatusNotice] = useState(null);
  const [isConfigOpen, setIsConfigOpen] = useState(false);
  const [isPasswordModalOpen, setIsPasswordModalOpen] = useState(false);


  const checkHealth = async () => {
    setIsChecking(true);
    const result = await pingBackend();
    setBackendOnline(result.ok);
    if (result.ok && result.url) {
      setActiveUrl(result.url);
      if (result.fallbackNotice) {
        setStatusNotice(result.fallbackNotice);
      } else {
        setStatusNotice(null);
      }
    } else {
      setStatusNotice(null);
    }
    setIsChecking(false);
    setLastChecked(new Date());
  };

  const handleSaveUrl = (newUrl) => {
    setBackendUrl(newUrl);
    setActiveUrl(newUrl);
    checkHealth();
  };

  useEffect(() => {
    checkHealth();
    const intervalTime = backendOnline === false ? 6000 : 30000;
    const interval = setInterval(checkHealth, intervalTime);
    return () => clearInterval(interval);
  }, [backendOnline]);

  if (!isAuthenticated) {
    return (
      <>
        <Login
          onOpenConfig={() => setIsConfigOpen(true)}
          backendOnline={backendOnline}
        />
        <ServerConfigModal
          isOpen={isConfigOpen}
          onClose={() => setIsConfigOpen(false)}
          currentUrl={activeUrl}
          onSave={handleSaveUrl}
          onCheck={checkHealth}
          isChecking={isChecking}
        />
      </>
    );
  }

  return (
    <div className="flex min-h-screen bg-slate-50 text-slate-900 font-sans antialiased">
      <Sidebar
        backendOnline={backendOnline}
        isChecking={isChecking}
        onRetry={checkHealth}
        onOpenConfig={() => setIsConfigOpen(true)}
        onOpenPasswordModal={() => setIsPasswordModalOpen(true)}
        activeUrl={activeUrl}
      />
      <main className="flex-1 overflow-y-auto flex flex-col">
        {backendOnline === false && (
          <div className="bg-rose-50 border-b border-rose-200 px-6 py-3 text-rose-900 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 shadow-xs">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-full bg-rose-100 flex items-center justify-center text-rose-600 shrink-0 font-bold text-sm">
                !
              </div>
              <div>
                <h4 className="text-xs font-bold text-rose-900">Backend Server is Offline or Unreachable</h4>
                <p className="text-[11px] text-rose-700">
                  Cannot connect to API at <code className="bg-rose-100 px-1 py-0.5 rounded font-mono text-[10px]">{activeUrl}</code>.
                  Run <code className="bg-rose-100 px-1 py-0.5 rounded font-mono text-[10px]">backend\start_backend.bat</code> to launch on port 8073.
                </p>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setIsConfigOpen(true)}
                className="px-3 py-1.5 text-xs font-semibold bg-white border border-rose-300 text-rose-800 rounded-lg hover:bg-rose-100 transition-colors shrink-0 cursor-pointer"
              >
                Change Host/Port
              </button>
              <button
                onClick={checkHealth}
                disabled={isChecking}
                className="px-3.5 py-1.5 text-xs font-semibold bg-rose-600 text-white rounded-lg hover:bg-rose-700 active:bg-rose-800 transition-colors shrink-0 disabled:opacity-50 cursor-pointer shadow-xs"
              >
                {isChecking ? 'Checking...' : 'Retry Connection'}
              </button>
            </div>
          </div>
        )}

        {statusNotice && (
          <div className="bg-amber-50 border-b border-amber-200 px-6 py-2 text-amber-900 flex items-center justify-between text-xs">
            <div className="flex items-center gap-2">
              <span className="font-semibold text-amber-700">Notice:</span>
              <span>{statusNotice}</span>
            </div>
            <button
              onClick={() => setStatusNotice(null)}
              className="text-amber-700 hover:text-amber-900 font-bold text-xs"
            >
              Dismiss
            </button>
          </div>
        )}

        <div className="flex-1">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/leaves" element={<Leaves />} />
            <Route path="/employees" element={<Employees />} />
            <Route path="/imports" element={<Imports />} />
            <Route path="/daily" element={<DailyAttendance />} />
            <Route path="/reports" element={<MonthlyReports />} />
            <Route path="/audit-logs" element={<AuditLogs />} />
            <Route path="/settings" element={<Settings />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </div>
      </main>

      <ServerConfigModal
        isOpen={isConfigOpen}
        onClose={() => setIsConfigOpen(false)}
        currentUrl={activeUrl}
        onSave={handleSaveUrl}
        onCheck={checkHealth}
        isChecking={isChecking}
      />

      <ChangePasswordModal
        isOpen={isPasswordModalOpen}
        onClose={() => setIsPasswordModalOpen(false)}
        username={currentUser?.username}
      />
    </div>
  );

}

export default function App() {
  return (
    <HashRouter>
      <AuthProvider>
        <MainApp />
      </AuthProvider>
    </HashRouter>
  );
}
