import React from 'react';
import { useAuth } from '../../context/AuthContext';
import { useTimeOffice } from '../../context/TimeOfficeContext';
import { isElectronApp } from '../../services/api';
import { 
  Calendar, 
  Wifi, 
  WifiOff, 
  Minus, 
  Square, 
  X, 
  ChevronDown,
  RotateCw,
  Clock
} from 'lucide-react';

export const TopBar: React.FC = () => {
  const { user } = useAuth();
  const { 
    selectedDate, 
    serverTime, 
    displayClock, 
    connectionStatus, 
    triggerRefresh, 
    isRefreshing
  } = useTimeOffice();

  const isElectron = isElectronApp();

  // Format date like screenshot: "Mon, 29 Sep 2026 10:24 AM"
  const formattedDateTime = React.useMemo(() => {
    try {
      const now = new Date();
      const dateStr = now.toLocaleDateString('en-GB', {
        weekday: 'short',
        day: '2-digit',
        month: 'short',
        year: 'numeric'
      });
      const timeStr = displayClock || now.toLocaleTimeString('en-US', {
        hour: '2-digit',
        minute: '2-digit',
        hour12: true
      });
      return `${dateStr}  ${timeStr}`;
    } catch {
      return `Mon, 29 Sep 2026 ${displayClock}`;
    }
  }, [displayClock]);

  // Electron window controls
  const handleMinimize = () => {
    (window as any).electronAPI?.minimize();
  };

  const handleMaximize = () => {
    (window as any).electronAPI?.maximize();
  };

  const handleClose = () => {
    (window as any).electronAPI?.close();
  };

  return (
    <header className="h-14 bg-[#faf8f5] border-b border-[#e2e8f0] flex items-center justify-between px-6 select-none shrink-0 z-30 font-sans">
      {/* Left: Backend Sync & Refresh Indicator */}
      <div className="flex items-center gap-4">
        <div 
          className={`flex items-center gap-2 px-3 py-1 rounded-full text-xs font-semibold border ${
            connectionStatus === 'CONNECTED'
              ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
              : connectionStatus === 'RECONNECTING'
              ? 'bg-amber-50 text-amber-700 border-amber-200'
              : 'bg-rose-50 text-rose-700 border-rose-200'
          }`}
          title={`Backend status: ${connectionStatus}`}
        >
          {connectionStatus === 'CONNECTED' ? (
            <>
              <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
              <span>LIVE SYNC</span>
            </>
          ) : (
            <>
              <WifiOff className="w-3.5 h-3.5 text-rose-600" />
              <span>OFFLINE</span>
            </>
          )}
        </div>

        {/* Server Time Badge */}
        <div className="flex items-center gap-2 text-xs font-medium text-slate-600">
          <Clock className="w-3.5 h-3.5 text-[#f95700]" />
          <span className="font-mono">{displayClock}</span>
          <button
            onClick={triggerRefresh}
            disabled={isRefreshing}
            className="p-1 text-slate-400 hover:text-slate-700 transition-colors disabled:opacity-50"
            title="Refresh Sync Data"
          >
            <RotateCw className={`w-3.5 h-3.5 ${isRefreshing ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      {/* Right: Date String & Admin Profile Dropdown */}
      <div className="flex items-center gap-6">
        {/* Date Display (Mon, 29 Sep 2026 10:24 AM) */}
        <div className="flex items-center gap-2 text-xs font-medium text-slate-700">
          <Calendar className="w-4 h-4 text-slate-600" />
          <span>{formattedDateTime}</span>
        </div>

        {/* User Profile Badge matching screenshot */}
        <div className="flex items-center gap-2.5 cursor-pointer hover:opacity-90 transition-opacity">
          {/* Circular badge with dark gray background and letter A */}
          <div className="w-8 h-8 rounded-full bg-[#2d3748] text-white flex items-center justify-center font-bold text-xs shadow-sm">
            {user?.full_name?.charAt(0) || 'A'}
          </div>
          <span className="text-xs font-semibold text-slate-800">
            {user?.full_name || 'Admin'}
          </span>
          <ChevronDown className="w-3.5 h-3.5 text-slate-500" />
        </div>

        {/* Window controls for Desktop App */}
        {isElectron && (
          <div className="flex items-center gap-1 text-slate-500 border-l border-slate-200 pl-4">
            <button
              onClick={handleMinimize}
              className="p-1.5 hover:bg-slate-200/60 hover:text-slate-800 rounded transition-colors"
              title="Minimize"
            >
              <Minus className="w-3.5 h-3.5" />
            </button>
            <button
              onClick={handleMaximize}
              className="p-1.5 hover:bg-slate-200/60 hover:text-slate-800 rounded transition-colors"
              title="Maximize"
            >
              <Square className="w-3 h-3" />
            </button>
            <button
              onClick={handleClose}
              className="p-1.5 hover:bg-rose-600 hover:text-white rounded transition-colors"
              title="Close"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>
        )}
      </div>
    </header>
  );
};

