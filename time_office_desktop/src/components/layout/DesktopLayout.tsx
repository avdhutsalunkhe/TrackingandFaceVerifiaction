import React from 'react';
import { Outlet } from 'react-router-dom';
import { TopBar } from './TopBar';
import { Sidebar } from './Sidebar';
import { useTimeOffice } from '../../context/TimeOfficeContext';
import { AlertCircle } from 'lucide-react';

export const DesktopLayout: React.FC = () => {
  const { connectionStatus, lastSyncTime } = useTimeOffice();

  return (
    <div className="flex flex-col h-screen w-screen overflow-hidden bg-[#faf8f5] text-slate-800 font-sans">
      <TopBar />

      {/* Disconnection Warning Banner if backend unavailable */}
      {connectionStatus === 'DISCONNECTED' && (
        <div className="bg-rose-50 border-b border-rose-200 px-4 py-2 flex items-center justify-between text-xs text-rose-800 shrink-0">
          <div className="flex items-center gap-2">
            <AlertCircle className="w-4 h-4 text-rose-600" />
            <span>
              <strong>Backend Disconnected:</strong> Live updates paused. Displayed records may be outdated.
            </span>
          </div>
          {lastSyncTime && (
            <span className="font-mono text-[11px] text-rose-600">
              Last synced: {lastSyncTime}
            </span>
          )}
        </div>
      )}

      {/* Main Content Area */}
      <div className="flex flex-1 overflow-hidden">
        <Sidebar />
        <main className="flex-1 overflow-y-auto bg-[#faf8f5] p-6 text-slate-800">
          <Outlet />
        </main>
      </div>
    </div>
  );
};

