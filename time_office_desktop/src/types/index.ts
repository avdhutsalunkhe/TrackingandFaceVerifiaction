export type UserRole = 'ADMIN' | 'USER' | 'TIME_OFFICE';

export interface User {
  id: number;
  employee_id: string;
  full_name: string;
  role: UserRole;
  is_active: boolean;
  must_change_password?: boolean;
}

export interface ServerTime {
  server_timestamp: string;
  server_date: string;
  server_time: string;
  formatted_date: string;
  formatted_time: string;
  timezone: string;
  epoch_ms: number;
}

export interface DashboardKPIs {
  scheduled: number;
  present: number;
  late: number;
  not_marked: number;
  pending_requests: number;
  rejected_attempts: number;
}

export interface ShiftActivity {
  shift_id: number;
  shift_code: string;
  shift_name: string;
  total_scheduled: number;
  completed_count: number;
  remaining_count: number;
  current_rule: string;
  completion_percentage: number;
}

export interface RecentPunch {
  id: number;
  employee_id: string;
  full_name: string;
  shift_name: string;
  verification_no: number;
  verification_window: string;
  status: 'PRESENT' | 'LATE';
  server_time: string;
  formatted_time: string;
  face_result: string;
  liveness_result: string;
  gps_distance: number;
  source: string;
  device_id?: string;
}

export interface DashboardData {
  server_time: ServerTime;
  selected_date: string;
  kpis: DashboardKPIs;
  shift_activity: ShiftActivity[];
  recent_punches: RecentPunch[];
}

export interface AttendanceItem {
  id: number;
  employee_id: string;
  employee_name: string;
  shift_id?: number;
  shift_code: string;
  shift_name: string;
  current_verification_period: string;
  verification_no: number;
  status: 'PRESENT' | 'LATE' | 'NOT_MARKED';
  verification_status: string;
  attendance_time: string;
  server_time: string;
  attendance_date: string;
  face_result: string;
  face_similarity_score: number;
  liveness_result: string;
  gps_distance: number;
  gps_accuracy?: number;
  verified_latitude?: number;
  verified_longitude?: number;
  source: string;
  device: string;
  last_updated: string;
}

export interface NotMarkedItem {
  employee_id: string;
  full_name: string;
  shift_id?: number;
  shift_code: string;
  shift_name: string;
  expected_time_window: string;
  verification_no: number;
  current_server_time: string;
  status: 'NOT_MARKED';
  rule_status: 'WINDOW_OPEN' | 'UPCOMING' | 'WINDOW_EXPIRED' | 'PENDING_PUNCH';
  time_remaining: string;
}

export interface ShiftPunchPeriodStatus {
  punch_no: number;
  period_name: string;
  start_time: string;
  end_time: string;
  label: string;
  priority: number;
  state: 'ACTIVE_NOW' | 'CLOSED' | 'UPCOMING';
  completed_count: number;
  remaining_count: number;
  completion_rate: number;
}

export interface ShiftMonitoringItem {
  shift_id: number;
  shift_code: string;
  shift_name: string;
  total_employees: number;
  punch_periods: ShiftPunchPeriodStatus[];
}

export interface EmployeeListItem {
  id: number;
  employee_id: string;
  full_name: string;
  role: string;
  is_active: boolean;
  department?: string;
  department_id?: number;
  unit_number?: number;
  designation?: string;
  has_face_enrolled: boolean;
  assigned_shift: {
    id?: number;
    shift_code: string;
    shift_name: string;
  };
  location_name: string;
  created_at?: string;
}

export interface AttendanceAttemptItem {
  id: number;
  employee_id: string;
  full_name: string;
  timestamp: string;
  attempt_status: 'SUCCESS' | 'REJECTED';
  rejection_reason: string;
  calculated_distance?: number;
  gps_accuracy?: number;
  latitude?: number;
  longitude?: number;
  face_similarity?: number;
  liveness_result: string;
  source: string;
  device: string;
  request_id?: string;
  details?: Record<string, any>;
}

export interface AttendanceRequestItem {
  id: number;
  employee_id: string;
  full_name: string;
  request_date: string;
  verification_no: number;
  server_timestamp: string;
  status: 'PENDING' | 'APPROVED' | 'REJECTED';
  rejection_trigger?: string;
  location_name: string;
  distance_meters: number;
  is_within_geofence: boolean;
  has_evidence_image: boolean;
  has_image?: boolean;
  admin_notes?: string;
  reviewed_by?: string;
  reviewed_at?: string;
}

export interface AuditLogItem {
  id: number;
  timestamp: string;
  action: string;
  actor: string;
  actor_employee_id?: string;
  target: string;
  target_employee_id?: string;
  details?: Record<string, any>;
  ip_address: string;
}

export interface DailyReportRow {
  employee_id: string;
  full_name: string;
  shift_code: string;
  shift_name: string;
  attendance_date: string;
  verification_count: number;
  first_verification: string;
  last_verification: string;
  status: 'PRESENT' | 'LATE' | 'NOT_MARKED';
  late_status: string;
}

export interface ShiftReportRow {
  shift_id: number;
  shift_code: string;
  shift_name: string;
  total_employees: number;
  present: number;
  late: number;
  not_marked: number;
  attendance_rate: number;
}

export interface PresentFirstPunchReportRow {
  employee_id: string;
  employee_name: string;
  department: string;
  shift_name: string;
  attendance_date: string;
  first_punch_time: string;
  attendance_status: string;
  late_status: string;
  location_name: string;
}

export interface AbsentFirstPunchReportRow {
  employee_id: string;
  employee_name: string;
  department: string;
  shift_code: string;
  shift_name: string;
  attendance_date: string;
  first_punch_window_start: string;
  first_punch_window_end: string;
  first_punch_status: string;
  actual_first_valid_punch: string;
  punch_timing: string;
  location_name: string;
}

export interface RoleMaster {
  id: number;
  role_code: string;
  role_name: string;
  description?: string;
  is_admin: boolean;
  permissions?: string;
  is_system_role: boolean;
  is_active: boolean;
  assigned_users_count: number;
  created_at: string;
  updated_at: string;
}

export interface RoleMasterCreate {
  role_code: string;
  role_name: string;
  description?: string;
  is_admin: boolean;
  permissions?: string;
  is_active: boolean;
}

export interface RoleMasterUpdate {
  role_name?: string;
  description?: string;
  is_admin?: boolean;
  permissions?: string;
  is_active?: boolean;
}

