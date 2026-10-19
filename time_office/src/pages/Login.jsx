import React, { useState } from 'react';
import { 
  User, Lock, Activity, ArrowRight, AlertCircle, Server, Eye, EyeOff, 
  KeyRound, CheckCircle2, ShieldAlert, ShieldCheck, Clock
} from 'lucide-react';
import axios from 'axios';
import { useAuth } from '../context/AuthContext';
import { BACKEND_URL, API_BASE } from '../api/client';
import logoImg from '../assets/logo.png';

export default function Login({ onOpenConfig, backendOnline }) {
  const { login, updateCurrentUser } = useAuth();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  // Forced / 15-day Password Reset Modal State
  const [resetModalOpen, setResetModalOpen] = useState(false);
  const [resetUsername, setResetUsername] = useState('');
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [resetLoading, setResetLoading] = useState(false);
  const [resetError, setResetError] = useState(null);
  const [resetSuccess, setResetSuccess] = useState(null);

  const handleSubmit = async (e) => {
    if (e) e.preventDefault();
    if (!username.trim() || !password.trim()) {
      setError('Please enter both username and password');
      return;
    }

    setError(null);
    setLoading(true);
    const res = await login(username, password);
    setLoading(false);

    if (!res.success) {
      setError(res.error);
      return;
    }

    // Check if 15-day password policy requires reset
    if (res.password_expired || res.must_reset_password) {
      setResetUsername(username);
      setCurrentPassword(password);
      setResetModalOpen(true);
    }
  };

  const handlePasswordResetSubmit = async (e) => {
    e.preventDefault();
    if (newPassword.length < 4) {
      setResetError('New password must be at least 4 characters');
      return;
    }
    if (newPassword !== confirmPassword) {
      setResetError('New passwords do not match');
      return;
    }

    setResetError(null);
    setResetLoading(true);

    try {
      const res = await axios.post(`${API_BASE}/auth/change-password`, {
        username: resetUsername,
        old_password: currentPassword,
        new_password: newPassword
      });

      if (res.data && res.data.success) {
        setResetSuccess('Password reset successfully! 15-day policy renewed.');
        setTimeout(() => {
          setResetModalOpen(false);
          // Auto login or reload
          window.location.reload();
        }, 1200);
      }
    } catch (err) {
      setResetError(err.response?.data?.detail || err.message || 'Failed to reset password');
    } finally {
      setResetLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-50 relative flex flex-col justify-center items-center p-4 selection:bg-orange-500 selection:text-white overflow-hidden">
      {/* Background Soft Glow / Elements */}
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[800px] h-[400px] bg-gradient-to-b from-orange-100/60 via-amber-50/40 to-transparent rounded-full blur-3xl pointer-events-none" />
      <div className="absolute -bottom-10 -right-10 w-80 h-80 bg-orange-100/40 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute -top-10 -left-10 w-80 h-80 bg-slate-200/50 rounded-full blur-3xl pointer-events-none" />

      <div className="w-full max-w-md relative z-10 space-y-6">
        {/* Brand Header */}
        <div className="text-center space-y-2">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-white shadow-lg shadow-orange-500/10 mb-1 hover:scale-105 transition-transform p-1.5 border border-slate-100">
            <img 
              src={logoImg} 
              alt="Report Logo" 
              onError={(e) => {
                e.currentTarget.onerror = null;
                e.currentTarget.src = './logo.png';
              }}
              className="w-full h-full object-contain rounded-xl" 
            />
          </div>
          <h1 className="text-2xl font-black text-slate-900 tracking-tight">REPORT</h1>
          <p className="text-xs text-slate-500 font-medium">Enterprise Attendance & Shift Intelligence System</p>
        </div>

        {/* Login Card (Crisp White Background) */}
        <div className="bg-white border border-slate-200/90 rounded-3xl p-6 sm:p-8 shadow-xl shadow-slate-200/60 backdrop-blur-md space-y-6">
          <div className="flex items-center justify-between border-b border-slate-100 pb-4">
            <div>
              <h2 className="text-base font-bold text-slate-900">Sign In</h2>
              <p className="text-[11px] text-slate-500">Enter your credentials to access system</p>
            </div>
            <button
              type="button"
              onClick={onOpenConfig}
              title="Configure API Server IP / Port"
              className="flex items-center gap-1.5 px-2.5 py-1 text-[11px] font-mono text-slate-600 hover:text-slate-900 bg-slate-100 hover:bg-slate-200/80 rounded-lg transition-colors border border-slate-200 cursor-pointer"
            >
              <Server size={12} className={backendOnline ? 'text-emerald-500' : 'text-amber-500'} />
              <span>{BACKEND_URL.replace(/^https?:\/\//, '')}</span>
            </button>
          </div>

          {error && (
            <div className="p-3 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs flex items-center gap-2.5 animate-in fade-in">
              <AlertCircle size={16} className="text-rose-500 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {/* Form */}
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1.5">Username</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none text-slate-400">
                  <User size={16} />
                </div>
                <input
                  type="text"
                  required
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="Enter your username"
                  className="w-full pl-10 pr-4 py-2.5 text-xs bg-slate-50 border border-slate-300 rounded-xl text-slate-900 placeholder-slate-400 focus:bg-white focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent font-medium transition-all"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1.5">Password</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none text-slate-400">
                  <Lock size={16} />
                </div>
                <input
                  type={showPassword ? 'text' : 'password'}
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••"
                  className="w-full pl-10 pr-10 py-2.5 text-xs bg-slate-50 border border-slate-300 rounded-xl text-slate-900 placeholder-slate-400 focus:bg-white focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent font-medium transition-all"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute inset-y-0 right-0 pr-3.5 flex items-center text-slate-400 hover:text-slate-600 cursor-pointer"
                >
                  {showPassword ? <EyeOff size={15} /> : <Eye size={15} />}
                </button>
              </div>
            </div>

            {/* 15-Day Policy Badge */}
            <div className="flex items-center gap-1.5 py-1 text-[11px] text-slate-500">
              <Clock size={12} className="text-orange-500 shrink-0" />
              <span>15-Day Password Reset Security Policy Active</span>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full py-2.5 px-4 bg-gradient-to-r from-orange-600 to-amber-600 hover:from-orange-500 hover:to-amber-500 active:scale-[0.99] text-white rounded-xl font-bold text-xs shadow-md shadow-orange-500/25 transition-all flex items-center justify-center gap-2 cursor-pointer disabled:opacity-50"
            >
              {loading ? (
                <span>Authenticating...</span>
              ) : (
                <>
                  <span>Sign In to System</span>
                  <ArrowRight size={15} />
                </>
              )}
            </button>
          </form>
        </div>

        {/* Footer info */}
        <p className="text-center text-[11px] text-slate-400">
          Report Attendance Intelligence • Build v2.0 • Windows Desktop Edition
        </p>
      </div>

      {/* 15-Day Mandatory Password Reset Modal */}
      {resetModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4 animate-in fade-in">
          <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 w-full max-w-md overflow-hidden animate-in zoom-in-95 duration-150">
            <div className="px-6 py-4 bg-gradient-to-r from-orange-600 to-amber-600 text-white flex items-center gap-3">
              <div className="p-2 rounded-xl bg-white/20 text-white">
                <ShieldAlert size={20} />
              </div>
              <div>
                <h3 className="text-sm font-bold text-white">15-Day Security Policy: Password Reset Required</h3>
                <p className="text-[11px] text-orange-100">Every account must update its password every 15 days</p>
              </div>
            </div>

            <form onSubmit={handlePasswordResetSubmit} className="p-6 space-y-4 text-xs">
              {resetError && (
                <div className="p-3 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 flex items-center gap-2 font-medium">
                  <AlertCircle size={15} className="shrink-0 text-rose-500" />
                  <span>{resetError}</span>
                </div>
              )}

              {resetSuccess && (
                <div className="p-3 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-800 flex items-center gap-2 font-medium">
                  <CheckCircle2 size={15} className="shrink-0 text-emerald-600" />
                  <span>{resetSuccess}</span>
                </div>
              )}

              <p className="text-slate-600 text-xs leading-relaxed">
                Your password for account <span className="font-bold text-slate-900">@{resetUsername}</span> is due for a renewal according to the 15-day enterprise security rule. Please specify your new password below.
              </p>

              <div>
                <label className="block font-semibold text-slate-700 mb-1">New Password *</label>
                <input
                  type="password"
                  required
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  placeholder="Enter new secure password (min 4 chars)"
                  className="w-full p-2.5 bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500 focus:bg-white text-slate-900 font-mono"
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
                  className="w-full p-2.5 bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500 focus:bg-white text-slate-900 font-mono"
                />
              </div>

              <div className="pt-2 flex justify-end gap-2.5">
                <button
                  type="submit"
                  disabled={resetLoading}
                  className="w-full py-2.5 px-4 bg-orange-600 hover:bg-orange-700 text-white font-bold rounded-xl shadow-xs transition-colors cursor-pointer disabled:opacity-50"
                >
                  {resetLoading ? 'Updating Password...' : 'Save New Password & Continue'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
