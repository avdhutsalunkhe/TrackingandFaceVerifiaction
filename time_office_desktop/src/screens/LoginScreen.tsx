import React, { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import { api, isElectronApp, getEndpointLabel } from '../services/api';
import { 
  Building2, 
  Lock, 
  User, 
  Eye, 
  EyeOff, 
  Wifi, 
  WifiOff, 
  CheckCircle2, 
  AlertCircle,
  Server,
  Globe
} from 'lucide-react';

export const LoginScreen: React.FC = () => {
  const { login, error, clearError, isLoading } = useAuth();
  const [employeeId, setEmployeeId] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [autoSwitchEnabled, setAutoSwitchEnabled] = useState<boolean>(api.isAutoSwitchEnabled());
  const [serverOnline, setServerOnline] = useState<boolean | null>(null);
  const [serverTimeStr, setServerTimeStr] = useState<string>('');
  const [selectedBackend, setSelectedBackend] = useState<string>(api.getBaseUrl());
  const isElectron = isElectronApp();

  useEffect(() => {
    let isMounted = true;
    const testServer = async () => {
      try {
        // Automatically probe and connect to fastest responding backend
        const fastest = await api.discoverWorkingUrl();
        if (fastest && isMounted) {
          setSelectedBackend(fastest);
        }
        const res = await api.getServerTime();
        if (isMounted) {
          if (res && res.server_time) {
            setServerOnline(true);
            setServerTimeStr(`${res.server_date} ${res.server_time}`);
          } else {
            setServerOnline(false);
          }
        }
      } catch {
        if (isMounted) setServerOnline(false);
      }
    };

    testServer();
    const interval = setInterval(testServer, 10000);
    return () => {
      isMounted = false;
      clearInterval(interval);
    };
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!employeeId.trim() || !password) return;
    clearError();
    await login(employeeId, password);
  };

  const handleBackendChange = (url: string) => {
    setSelectedBackend(url);
    api.setBaseUrl(url);
    setServerOnline(null);
  };

  return (
    <div className="h-screen w-screen flex items-center justify-center bg-white select-none p-4 relative overflow-hidden">
      {/* Soft ambient background gradient */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-brand-50/60 via-slate-50 to-white pointer-events-none" />

      <div className="relative w-full max-w-md bg-white border border-slate-200/90 rounded-2xl shadow-xl overflow-hidden p-8 z-10">
        {/* Header Branding */}
        <div className="flex flex-col items-center text-center mb-8">
          <div className="w-14 h-14 rounded-2xl bg-gradient-to-tr from-brand-600 to-brand-500 flex items-center justify-center shadow-lg shadow-brand-500/25 mb-3 border border-brand-400/30">
            <Building2 className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-xl font-bold tracking-tight text-slate-900 flex items-center gap-2">
            <span>TIME OFFICE</span>
            <span className="text-[10px] px-2 py-0.5 rounded bg-brand-50 text-brand-600 border border-brand-200 uppercase font-mono font-semibold">
              {isElectron ? 'Desktop PC' : 'Web Console'}
            </span>
          </h1>
          <p className="text-xs text-slate-500 mt-1 font-medium">FieldStaff AI Biometric Attendance System</p>
        </div>

        {/* Error notification banner */}
        {error && (
          <div className="mb-5 p-3 rounded-lg bg-rose-50 border border-rose-200 flex items-start gap-2.5 text-xs text-rose-700 font-medium">
            <AlertCircle className="w-4 h-4 text-rose-500 shrink-0 mt-0.5" />
            <div>{error}</div>
          </div>
        )}

        {/* Login Form */}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1.5 uppercase tracking-wider">
              Operator / Employee ID
            </label>
            <div className="relative">
              <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-slate-400">
                <User className="w-4 h-4" />
              </div>
              <input
                type="text"
                required
                value={employeeId}
                onChange={(e) => setEmployeeId(e.target.value)}
                placeholder="Enter ID"
                className="w-full bg-slate-50 border border-slate-300 rounded-lg pl-9 pr-3 py-2.5 text-sm text-slate-900 placeholder-slate-400 focus:outline-none focus:bg-white focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 transition-all"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1.5 uppercase tracking-wider">
              Password
            </label>
            <div className="relative">
              <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-slate-400">
                <Lock className="w-4 h-4" />
              </div>
              <input
                type={showPassword ? 'text' : 'password'}
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                className="w-full bg-slate-50 border border-slate-300 rounded-lg pl-9 pr-10 py-2.5 text-sm text-slate-900 placeholder-slate-400 focus:outline-none focus:bg-white focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 transition-all"
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute inset-y-0 right-0 pr-3 flex items-center text-slate-400 hover:text-slate-600 transition-colors"
              >
                {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </div>

          <button
            type="submit"
            disabled={isLoading}
            className="w-full mt-2 py-2.5 px-4 bg-brand-600 hover:bg-brand-500 active:bg-brand-700 text-white font-semibold text-sm rounded-lg shadow-md shadow-brand-500/20 transition-colors flex items-center justify-center gap-2 disabled:opacity-50"
          >
            {isLoading ? (
              <>
                <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                <span>Authenticating...</span>
              </>
            ) : (
              <span>Sign In to Time Office</span>
            )}
          </button>
        </form>

      </div>
    </div>
  );
};
