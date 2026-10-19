import axios, { AxiosInstance } from 'axios';

// Detect whether running in native Electron desktop app or web browser
export const isElectronApp = (): boolean => {
  return typeof window !== 'undefined' && Boolean((window as any).electronAPI);
};

// Candidate backend URLs in priority order (Local port first, then LAN/Public)
export const BACKEND_URLS = [
  'http://192.168.1.91:8084',    // 1st: Office LAN IP
  'http://182.66.233.66:8084',   // 2nd: Public Primary
  'http://115.244.240.22:8084',  // 3rd: Public Secondary
];

export const getEndpointLabel = (url: string): string => {
  if (!url) return 'Office LAN (Auto)';
  if (url.includes('192.168.1.91')) return '192.168.1.91:8084 (Office LAN)';
  if (url.includes('192.168.1.93')) return '192.168.1.93:8084 (Office LAN)';
  if (url.includes('182.66')) return '182.66.233.66:8084 (Public Primary)';
  if (url.includes('115.244')) return '115.244.240.22:8084 (Public Secondary)';
  return url.replace('http://', '');
};

class ApiClient {
  private activeBaseUrl: string = BACKEND_URLS[0];
  private client: AxiosInstance;
  private isTestingFailover = false;
  private autoSwitchEnabled = localStorage.getItem('time_office_autoswitch') !== 'false';
  private listeners: ((url: string) => void)[] = [];

  constructor() {
    const isWeb = typeof window !== 'undefined' && !Boolean((window as any).electronAPI);
    const isHttps = typeof window !== 'undefined' && window.location.protocol === 'https:';
    const saved = localStorage.getItem('time_office_base_url');

    if (saved && (BACKEND_URLS.includes(saved) || saved === '')) {
      this.activeBaseUrl = saved;
    } else if (isHttps || isWeb) {
      // In web mode, use same-origin / relative path ('') so Vite proxy handles requests regardless of local port
      this.activeBaseUrl = '';
    } else {
      this.activeBaseUrl = BACKEND_URLS[0];
    }

    this.client = axios.create({
      baseURL: this.activeBaseUrl,
      timeout: 10000,
      headers: {
        'Content-Type': 'application/json',
      },
    });

    // Request interceptor to attach JWT token
    this.client.interceptors.request.use((config) => {
      const token = localStorage.getItem('time_office_token');
      if (token && config.headers) {
        config.headers.Authorization = `Bearer ${token}`;
      }
      return config;
    });

    // Response interceptor for automatic failover on network/server errors
    this.client.interceptors.response.use(
      (response) => response,
      async (error) => {
        const originalRequest = error.config;
        if (!originalRequest || originalRequest._retry || this.isTestingFailover) {
          return Promise.reject(error);
        }

        // Check if error is network/timeout or 5xx server down
        const isNetworkError = !error.response || error.code === 'ECONNABORTED' || (error.response.status >= 502 && error.response.status <= 504);
        if (isNetworkError && this.autoSwitchEnabled) {
          console.warn(`[API] Current URL ${this.activeBaseUrl} unreachable. Triggering automatic network failover...`);
          const newUrl = await this.discoverWorkingUrl();
          if (newUrl !== null && newUrl !== this.activeBaseUrl) {
            this.setBaseUrl(newUrl);
            originalRequest._retry = true;
            originalRequest.baseURL = newUrl;
            return this.client(originalRequest);
          }
        }

        return Promise.reject(error);
      }
    );

    // Initial check in background to verify & lock in the fastest active candidate
    this.discoverWorkingUrl();
  }

  public getBaseUrl(): string {
    return this.activeBaseUrl;
  }

  public isAutoSwitchEnabled(): boolean {
    return this.autoSwitchEnabled;
  }

  public setAutoSwitchEnabled(enabled: boolean) {
    this.autoSwitchEnabled = enabled;
    localStorage.setItem('time_office_autoswitch', enabled ? 'true' : 'false');
  }

  public onUrlChange(cb: (url: string) => void) {
    this.listeners.push(cb);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== cb);
    };
  }

  public setBaseUrl(url: string) {
    this.activeBaseUrl = url;
    this.client.defaults.baseURL = url;
    localStorage.setItem('time_office_base_url', url);
    this.listeners.forEach((cb) => cb(url));
  }

  public getCandidates(): string[] {
    const isWeb = typeof window !== 'undefined' && !Boolean((window as any).electronAPI);
    const isHttps = typeof window !== 'undefined' && window.location.protocol === 'https:';
    if (isHttps) {
      // On HTTPS (Netlify), direct HTTP requests to IPs are blocked as mixed content.
      // Only use same-origin proxy which Netlify redirects to the backend.
      return [''];
    }
    if (isWeb) {
      // HTTP web (local dev / random local port): try relative proxy path first
      return ['', ...BACKEND_URLS];
    }
    return [...BACKEND_URLS];
  }

  public async discoverWorkingUrl(): Promise<string | null> {
    if (this.isTestingFailover) return this.activeBaseUrl;
    this.isTestingFailover = true;

    try {
      const candidates = this.getCandidates();

      // Test all candidates concurrently for instant resolution
      const checkCandidate = async (url: string): Promise<string> => {
        const targetUrl = url ? `${url}/api/user/server-time` : '/api/user/server-time';
        const res = await axios.get(targetUrl, { timeout: 2500 });
        if (res.status === 200 && res.data?.server_time) {
          return url;
        }
        throw new Error(`Candidate ${url} unreachable`);
      };

      try {
        const fastestUrl = await Promise.any(candidates.map((url) => checkCandidate(url)));
        if (fastestUrl !== this.activeBaseUrl) {
          console.log(`[API] Auto-switched to fastest responsive backend: ${fastestUrl || 'Local Proxy'}`);
          this.setBaseUrl(fastestUrl);
        }
        return fastestUrl;
      } catch {
        console.warn('[API] None of the candidate URLs responded to health check.');
      }
    } finally {
      this.isTestingFailover = false;
    }
    return null;
  }

  public async checkHealth(): Promise<boolean> {
    try {
      const res = await this.client.get('/api/user/server-time', { timeout: 3500 });
      return res.status === 200;
    } catch {
      return false;
    }
  }

  public async getPublicServerTime() {
    const res = await this.client.get('/api/user/server-time', { timeout: 4000 });
    return res.data;
  }

  // --------------------------------------------------------------------------
  // AUTH
  // --------------------------------------------------------------------------
  public async login(employee_id: string, password: string) {
    const res = await this.client.post(
      '/api/auth/login',
      { employee_id, password, client_type: 'WEB' },
      { headers: { 'X-Client-Type': 'WEB' } }
    );
    return res.data;
  }

  public async getMe() {
    const res = await this.client.get('/api/auth/me');
    return res.data;
  }

  // --------------------------------------------------------------------------
  // TIME OFFICE OPERATIONS
  // --------------------------------------------------------------------------
  public async getServerTime() {
    const res = await this.client.get('/api/time-office/server-time');
    return res.data;
  }

  public async getDashboard(date?: string) {
    const res = await this.client.get('/api/time-office/dashboard', { params: { date } });
    return res.data;
  }

  public async getTodayAttendance(params?: {
    date?: string;
    shift_id?: number;
    status_filter?: string;
    search?: string;
    page?: number;
    page_size?: number;
  }) {
    const res = await this.client.get('/api/time-office/attendance/today', { params });
    const d = res.data;
    // API returns { records:[...], total, page, limit }
    // Normalise to { records, total } so all screens work identically
    const records = d?.records ?? d?.items ?? d?.data ?? (Array.isArray(d) ? d : []);
    return { records, total: d?.total ?? records.length, page: d?.page ?? 1 };
  }

  public async getPresentEmployees(params?: {
    date?: string;
    shift_id?: number;
    search?: string;
    page?: number;
    page_size?: number;
  }) {
    const res = await this.client.get('/api/time-office/attendance/present', { params });
    const d = res.data;
    const records = d?.records ?? d?.items ?? d?.data ?? (Array.isArray(d) ? d : []);
    return { records, total: d?.total ?? records.length };
  }

  public async getLateEmployees(params?: {
    date?: string;
    shift_id?: number;
    search?: string;
    page?: number;
    page_size?: number;
  }) {
    const res = await this.client.get('/api/time-office/attendance/late', { params });
    const d = res.data;
    const records = d?.records ?? d?.items ?? d?.data ?? (Array.isArray(d) ? d : []);
    return { records, total: d?.total ?? records.length };
  }

  public async getNotMarkedEmployees(params?: {
    date?: string;
    shift_id?: number;
    search?: string;
    page?: number;
    page_size?: number;
  }) {
    const res = await this.client.get('/api/time-office/attendance/not-marked', { params });
    const d = res.data;
    const records = d?.records ?? d?.employees ?? d?.items ?? d?.data ?? (Array.isArray(d) ? d : []);
    return { records, total: d?.total ?? records.length };
  }

  public async getEmployees(params?: { search?: string; shift_id?: number; page?: number; page_size?: number }) {
    const res = await this.client.get('/api/time-office/employees', { params });
    const d = res.data;
    // API returns { count, employees: [...] }
    const records = d?.employees ?? d?.records ?? d?.items ?? d?.data ?? (Array.isArray(d) ? d : []);
    return { records, total: d?.count ?? d?.total ?? records.length };
  }

  public async getEmployeeDetail(employeeId: string, date?: string) {
    const res = await this.client.get(`/api/time-office/employees/${encodeURIComponent(employeeId)}`, { params: { date } });
    return res.data;
  }

  public async createUser(payload: {
    employee_id: string;
    full_name: string;
    role?: string;
    initial_password?: string;
    department?: string;
    department_id?: number;
    unit_number?: number;
    designation?: string;
    is_active?: boolean;
  }) {
    try {
      const res = await this.client.post('/api/time-office/employees', payload);
      return res.data;
    } catch (err: any) {
      const res = await this.client.post('/api/admin/users', payload);
      return res.data;
    }
  }

  public async updateUser(userId: number, payload: {
    full_name?: string;
    role?: string;
    password?: string;
    department?: string;
    department_id?: number;
    unit_number?: number;
    designation?: string;
    is_active?: boolean;
  }) {
    try {
      const res = await this.client.put(`/api/time-office/employees/${userId}`, payload);
      return res.data;
    } catch (err: any) {
      const res = await this.client.put(`/api/admin/users/${userId}`, payload);
      return res.data;
    }
  }

  public async getShifts() {
    try {
      const res = await this.client.get('/api/time-office/shifts');
      const d = res.data;
      if (Array.isArray(d)) return d;
      if (Array.isArray(d?.shifts)) return d.shifts;
      if (Array.isArray(d?.data)) return d.data;
      if (Array.isArray(d?.items)) return d.items;
      return [];
    } catch (e) {
      console.error('[API] getShifts failed:', e);
      return [];
    }
  }

  public async getShiftMonitoring(date?: string) {
    const res = await this.client.get('/api/time-office/shift-monitoring', { params: { date } });
    return res.data;
  }

  public async getAttempts(params?: {
    date?: string;
    employee_id?: string;
    status_filter?: string;
    rejection_reason?: string;
    page?: number;
    page_size?: number;
  }) {
    const res = await this.client.get('/api/time-office/attempts', { params });
    const d = res.data;
    // API returns { count, attempts: [...] }
    const records = d?.attempts ?? d?.records ?? d?.items ?? d?.data ?? (Array.isArray(d) ? d : []);
    return { records, total: d?.count ?? d?.total ?? records.length };
  }

  public async getRequests(params?: {
    date?: string;
    status_filter?: string;
    search?: string;
    page?: number;
    page_size?: number;
  }) {
    const res = await this.client.get('/api/time-office/requests', { params });
    const d = res.data;
    // API may return { requests: [...], total } or { items: [...], total }
    const records = d?.requests ?? d?.records ?? d?.items ?? d?.data ?? (Array.isArray(d) ? d : []);
    return { records, total: d?.count ?? d?.total ?? records.length };
  }

  public getRequestImageUrl(requestId: number): string {
    const token = localStorage.getItem('time_office_token');
    return `${this.activeBaseUrl}/api/time-office/requests/${requestId}/image?token=${token}`;
  }

  public async approveRequest(requestId: number, notes?: string) {
    const res = await this.client.post(`/api/time-office/requests/${requestId}/approve`, { notes });
    return res.data;
  }

  public async rejectRequest(requestId: number, notes?: string) {
    const res = await this.client.post(`/api/time-office/requests/${requestId}/reject`, { notes });
    return res.data;
  }

  public async correctAttendance(payload: {
    employee_id: string;
    attendance_date: string;
    verification_no: number;
    new_status: string;
    reason: string;
  }) {
    const res = await this.client.post('/api/time-office/attendance/correction', payload);
    return res.data;
  }

  public async getDailyReport(date?: string, shift_id?: number) {
    const res = await this.client.get('/api/time-office/reports/daily', { params: { date, shift_id } });
    return res.data;
  }

  public async getShiftReport(date?: string) {
    const res = await this.client.get('/api/time-office/reports/shift', { params: { date } });
    return res.data;
  }

  public async getPresentFirstPunchReport(date?: string) {
    const res = await this.client.get('/api/time-office/reports/present-first-punch', { params: { date } });
    return res.data;
  }

  public async getAbsentFirstPunchReport(date?: string) {
    const res = await this.client.get('/api/time-office/reports/absent-first-punch', { params: { date } });
    return res.data;
  }

  public async getRawReportDataset(date?: string) {
    const res = await this.client.get('/api/time-office/reports/raw-dataset', { params: { date } });
    return res.data;
  }

  public async getAuditLogs(params?: { search?: string; action?: string; page?: number; page_size?: number }) {
    const res = await this.client.get('/api/time-office/audit-logs', { params });
    const d = res.data;
    const records = d?.logs ?? d?.audit_logs ?? d?.records ?? d?.items ?? d?.data ?? (Array.isArray(d) ? d : []);
    return { records, total: d?.count ?? d?.total ?? records.length };
  }

  public async getHolidays() {
    const res = await this.client.get('/api/time-office/holidays');
    const d = res.data;
    const records = d?.holidays ?? d?.records ?? (Array.isArray(d) ? d : []);
    return { records, total: d?.count ?? records.length };
  }

  public async createHoliday(payload: { name: string; holiday_date: string; description?: string; is_optional?: boolean }) {
    const res = await this.client.post('/api/time-office/holidays', payload);
    return res.data;
  }

  public async deleteHoliday(id: number) {
    const res = await this.client.delete(`/api/time-office/holidays/${id}`);
    return res.data;
  }

  public async getWeeklyOffs() {
    const res = await this.client.get('/api/time-office/weekly-offs');
    const d = res.data;
    const records = d?.weekly_offs ?? d?.records ?? (Array.isArray(d) ? d : []);
    return { records, total: d?.count ?? records.length };
  }

  public async getExtraWorkReport(date?: string) {
    const res = await this.client.get('/api/time-office/extra-work', { params: { date } });
    const d = res.data;
    const records = d?.records ?? (Array.isArray(d) ? d : []);
    return { records, total: d?.count ?? records.length };
  }

  public async approveExtraWork(id: number, notes?: string) {
    const res = await this.client.post(`/api/time-office/extra-work/${id}/approve`, { admin_notes: notes });
    return res.data;
  }

  public async rejectExtraWork(id: number, notes?: string) {
    const res = await this.client.post(`/api/time-office/extra-work/${id}/reject`, { admin_notes: notes });
    return res.data;
  }

  public async getMultiLocationReport(date?: string) {
    const res = await this.client.get('/api/time-office/reports/multi-location', { params: { date } });
    const d = res.data;
    const records = d?.records ?? (Array.isArray(d) ? d : []);
    return { records, total: d?.count ?? records.length };
  }
  // --------------------------------------------------------------------------
  // SHIFT MANAGEMENT & MASTER DATA API ENDPOINTS
  // --------------------------------------------------------------------------
  public async getAdminShifts() {
    try {
      const res = await this.client.get('/api/admin/shifts');
      return Array.isArray(res.data) ? res.data : [];
    } catch {
      return this.getShifts();
    }
  }

  public async createShift(payload: {
    shift_code: string;
    shift_name: string;
    description?: string;
    is_active?: boolean;
    rules: any[];
  }) {
    const res = await this.client.post('/api/admin/shifts', {
      ...payload,
      punch_periods: payload.rules,
    });
    return res.data;
  }

  public async updateShift(shiftId: number, payload: {
    shift_code?: string;
    shift_name?: string;
    description?: string;
    is_active?: boolean;
    rules?: any[];
  }) {
    const res = await this.client.put(`/api/admin/shifts/${shiftId}`, {
      ...payload,
      punch_periods: payload.rules,
    });
    return res.data;
  }

  public async deleteShift(shiftId: number) {
    const res = await this.client.delete(`/api/admin/shifts/${shiftId}`);
    return res.data;
  }

  public async duplicateShift(shiftId: number, newShiftCode: string, newShiftName: string) {
    const res = await this.client.post(`/api/admin/shifts/${shiftId}/duplicate`, {
      new_shift_code: newShiftCode,
      new_shift_name: newShiftName,
    });
    return res.data;
  }

  public async assignShift(payload: {
    user_id: number;
    shift_id: number;
    effective_from: string;
    effective_to?: string | null;
  }) {
    const res = await this.client.post('/api/admin/shifts/assign', payload);
    return res.data;
  }

  public async getUserShiftHistory(userId: number) {
    try {
      const res = await this.client.get(`/api/admin/shifts/users/${userId}/shift-history`);
      return Array.isArray(res.data) ? res.data : [];
    } catch {
      return [];
    }
  }

  public async deleteShiftAssignment(assignmentId: number) {
    const res = await this.client.delete(`/api/admin/shifts/assignments/${assignmentId}`);
    return res.data;
  }

  // --------------------------------------------------------------------------
  // EMPLOYEE & GEOFENCE MANAGEMENT API ENDPOINTS
  // --------------------------------------------------------------------------
  public async registerEmployee(payload: {
    employee_id: string;
    full_name: string;
    initial_password?: string;
    role?: string;
    is_active?: boolean;
    department?: string;
    designation?: string;
  }) {
    const res = await this.client.post('/api/admin/users', {
      role: 'USER',
      is_active: true,
      ...payload,
      initial_password: payload.initial_password || payload.employee_id,
    });
    return res.data;
  }

  public async updateEmployee(userId: number, payload: Record<string, any>) {
    const res = await this.client.put(`/api/admin/users/${userId}`, payload);
    return res.data;
  }

  public async saveGeofence(userId: number, payload: {
    location_name: string;
    latitude: number;
    longitude: number;
    radius_meters: number;
    is_active?: boolean;
  }) {
    const res = await this.client.post(`/api/admin/users/${userId}/geofence`, {
      is_active: true,
      ...payload,
    });
    return res.data;
  }

  public async getBiometricSettings() {
    const res = await this.client.get('/api/admin/settings/biometric');
    return res.data;
  }

  public async updateBiometricSettings(payload: Record<string, any>) {
    const res = await this.client.put('/api/admin/settings/biometric', payload);
    return res.data;
  }

  // --------------------------------------------------------------------------
  // ROLE MASTER MANAGEMENT API ENDPOINTS
  // --------------------------------------------------------------------------
  public async getRoles() {
    const res = await this.client.get('/api/time-office/roles');
    return Array.isArray(res.data) ? res.data : [];
  }

  public async createRole(payload: {
    role_code: string;
    role_name: string;
    description?: string;
    is_admin: boolean;
    permissions?: string;
    is_active: boolean;
  }) {
    const res = await this.client.post('/api/time-office/roles', payload);
    return res.data;
  }

  public async updateRole(roleId: number, payload: {
    role_name?: string;
    description?: string;
    is_admin?: boolean;
    permissions?: string;
    is_active?: boolean;
  }) {
    const res = await this.client.put(`/api/time-office/roles/${roleId}`, payload);
    return res.data;
  }

  public async deleteRole(roleId: number) {
    const res = await this.client.delete(`/api/time-office/roles/${roleId}`);
    return res.data;
  }

  public async assignUserRole(userId: number, roleCode: string) {
    const res = await this.client.post('/api/time-office/roles/assign', {
      user_id: userId,
      role_code: roleCode,
    });
    return res.data;
  }
}

export const api = new ApiClient();


