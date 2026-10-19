import React, { createContext, useContext, useState, useEffect, useCallback, useRef } from 'react';
import { ServerTime } from '../types';
import { api } from '../services/api';

export type ConnectionStatus = 'CONNECTED' | 'DISCONNECTED' | 'RECONNECTING';

interface TimeOfficeContextType {
  selectedDate: string;
  setSelectedDate: (date: string) => void;
  serverTime: ServerTime | null;
  displayClock: string;
  connectionStatus: ConnectionStatus;
  lastSyncTime: string | null;
  refreshKey: number;
  triggerRefresh: () => void;
  isRefreshing: boolean;
  activeBaseUrl: string;
}

const TimeOfficeContext = createContext<TimeOfficeContextType | undefined>(undefined);

const getTodayStr = (): string => {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
};

export const TimeOfficeProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [selectedDate, setSelectedDate] = useState<string>(getTodayStr());
  const [serverTime, setServerTime] = useState<ServerTime | null>(null);
  const [displayClock, setDisplayClock] = useState<string>('--:--:--');
  const [connectionStatus, setConnectionStatus] = useState<ConnectionStatus>('RECONNECTING');
  const [lastSyncTime, setLastSyncTime] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState<number>(0);
  const [isRefreshing, setIsRefreshing] = useState<boolean>(false);
  const [activeBaseUrl, setActiveBaseUrl] = useState<string>(api.getBaseUrl());

  // Clock synchronization reference
  const serverOffsetMs = useRef<number>(0);

  // Sync server time from backend
  const syncServerTime = useCallback(async () => {
    try {
      const startMs = Date.now();
      const st = await api.getServerTime();
      const endMs = Date.now();
      const latency = (endMs - startMs) / 2;

      // Compute clock offset: Server Epoch - (Local Epoch + latency)
      serverOffsetMs.current = st.epoch_ms - (startMs + latency);

      setServerTime(st);
      if (st && st.server_date) {
        setSelectedDate((prev) => (!prev ? st.server_date : prev));
      }
      setConnectionStatus('CONNECTED');
      setActiveBaseUrl(api.getBaseUrl());
      setLastSyncTime(new Date().toLocaleTimeString());
    } catch (err) {
      console.warn('[TimeOffice] Server time synchronization failed:', err);
      setConnectionStatus('DISCONNECTED');
    }
  }, []);

  // Tick authoritative clock every second based on serverOffset
  useEffect(() => {
    const timer = setInterval(() => {
      if (serverTime) {
        const estimatedServerMs = Date.now() + serverOffsetMs.current;
        const dt = new Date(estimatedServerMs);
        // Format as Indian Standard Time (or configured timezone)
        const timeStr = dt.toLocaleTimeString('en-US', {
          timeZone: serverTime.timezone || 'Asia/Kolkata',
          hour: '2-digit',
          minute: '2-digit',
          second: '2-digit',
          hour12: true,
        });
        setDisplayClock(timeStr);
      }
    }, 1000);

    return () => clearInterval(timer);
  }, [serverTime]);

  // Periodic server sync and health polling (every 15 seconds)
  useEffect(() => {
    syncServerTime();
    const syncInterval = setInterval(() => {
      syncServerTime();
    }, 15000);

    return () => clearInterval(syncInterval);
  }, [syncServerTime]);

  // Manual refresh trigger
  const triggerRefresh = useCallback(() => {
    setIsRefreshing(true);
    setRefreshKey((prev) => prev + 1);
    syncServerTime().finally(() => {
      setTimeout(() => setIsRefreshing(false), 600);
    });
  }, [syncServerTime]);

  return (
    <TimeOfficeContext.Provider
      value={{
        selectedDate,
        setSelectedDate,
        serverTime,
        displayClock,
        connectionStatus,
        lastSyncTime,
        refreshKey,
        triggerRefresh,
        isRefreshing,
        activeBaseUrl,
      }}
    >
      {children}
    </TimeOfficeContext.Provider>
  );
};

export const useTimeOffice = () => {
  const context = useContext(TimeOfficeContext);
  if (!context) {
    throw new Error('useTimeOffice must be used within a TimeOfficeProvider');
  }
  return context;
};
