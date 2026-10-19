import { EmployeeTravelMapScreen } from './screens/EmployeeTravelMapScreen';
import React from 'react';
import { HashRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './context/AuthContext';
import { TimeOfficeProvider } from './context/TimeOfficeContext';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

import { LoginScreen } from './screens/LoginScreen';
import { DesktopLayout } from './components/layout/DesktopLayout';
import { DashboardScreen } from './screens/DashboardScreen';
import { AttendanceScreen } from './screens/AttendanceScreen';
import { PresentScreen } from './screens/PresentScreen';
import { LateScreen } from './screens/LateScreen';
import { NotMarkedScreen } from './screens/NotMarkedScreen';
import { ShiftMonitoringScreen } from './screens/ShiftMonitoringScreen';
import { EmployeeSearchScreen } from './screens/EmployeeSearchScreen';
import { AttendanceAttemptsScreen } from './screens/AttendanceAttemptsScreen';
import { AttendanceRequestsScreen } from './screens/AttendanceRequestsScreen';
import { ReportsScreen } from './screens/ReportsScreen';
import { CorrectionScreen } from './screens/CorrectionScreen';
import { AuditLogScreen } from './screens/AuditLogScreen';
import { SettingsScreen } from './screens/SettingsScreen';
import { ShiftManagementScreen } from './screens/ShiftManagementScreen';
import { DepartmentsScreen } from './screens/DepartmentsScreen';
import { RolesScreen } from './screens/RolesScreen';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
      retry: 1,
    },
  },
});

const AppRoutes: React.FC = () => {
  const { isAuthenticated, isLoading } = useAuth();

  if (isLoading) {
    return (
      <div className="h-screen w-screen flex flex-col items-center justify-center bg-slate-950 text-slate-400 gap-3">
        <div className="w-8 h-8 border-2 border-brand-500 border-t-transparent rounded-full animate-spin" />
        <span className="text-xs uppercase tracking-wider font-mono">Initializing Time Office Desktop...</span>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <LoginScreen />;
  }

  return (
    <TimeOfficeProvider>
      <Routes>
        <Route element={<DesktopLayout />}>
          <Route path="/" element={<DashboardScreen />} />
          <Route path="/attendance" element={<AttendanceScreen />} />
          <Route path="/present" element={<PresentScreen />} />
          <Route path="/late" element={<LateScreen />} />
          <Route path="/not-marked" element={<NotMarkedScreen />} />
          <Route path="/shift-monitoring" element={<ShiftMonitoringScreen />} />
          <Route path="/shift-rules" element={<ShiftManagementScreen />} />
          <Route path="/departments" element={<DepartmentsScreen />} />
          <Route path="/roles" element={<RolesScreen />} />
          <Route path="/employees" element={<EmployeeSearchScreen />} />
          <Route path="/attempts" element={<AttendanceAttemptsScreen />} />
          <Route path="/requests" element={<AttendanceRequestsScreen />} />
          <Route path="/reports" element={<ReportsScreen />} />
          <Route path="/correction" element={<CorrectionScreen />} />
          <Route path="/audit-log" element={<AuditLogScreen />} />
          <Route path="/settings" element={<SettingsScreen />} />
          <Route path="/travel-map" element={<EmployeeTravelMapScreen />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Route>
      </Routes>
    </TimeOfficeProvider>
  );
};

export const App: React.FC = () => {
  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <HashRouter>
          <AppRoutes />
        </HashRouter>
      </AuthProvider>
    </QueryClientProvider>
  );
};

export default App;
