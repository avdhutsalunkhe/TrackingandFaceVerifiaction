import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { useTimeOffice } from '../context/TimeOfficeContext';
import { api } from '../services/api';
import { ExportButtons } from '../components/common/ExportButtons';
import { 
  AttendanceRuleEngine, 
  AttendanceDecision, 
  StatusDefinition 
} from '../services/AttendanceRuleEngine';
import { 
  FileText, 
  Calendar as CalendarIcon, 
  Search, 
  RotateCw, 
  CheckCircle2, 
  Info, 
  ChevronDown,
  Clock,
  ChevronLeft,
  ChevronRight,
  Building2,
  UserX,
  MapPin,
  ShieldCheck,
  AlertTriangle,
  Users,
  Award
} from 'lucide-react';

export type ReportType = 
  | 'roll_up'
  | 'shift_summary'
  | 'daily'
  | 'present'
  | 'present_first_punch'
  | 'absent_first_punch'
  | 'full_day_absent'
  | 'late'
  | 'not_marked'
  | 'shift_monitoring'
  | 'monthly_summary'
  | 'holiday_weekly_off'
  | 'extra_work'
  | 'multi_location'
  | 'biometric_attempts'
  | 'requests'
  | 'audit_log'
  | 'employee_directory';

export const ReportsScreen: React.FC = () => {
  const { selectedDate, refreshKey } = useTimeOffice();
  const location = useLocation();

  // Read report type from query params
  const queryParams = new URLSearchParams(location.search);
  const initialType = (queryParams.get('type') as ReportType) || 'full_day_absent';

  const [reportType, setReportType] = useState<ReportType>(initialType);
  const [selectedDept, setSelectedDept] = useState<string>('All Departments');
  const [selectedShift, setSelectedShift] = useState<string>('All Shifts');
  const [filterDate, setFilterDate] = useState<string>(selectedDate || new Date().toISOString().slice(0, 10));

  const [decisions, setDecisions] = useState<AttendanceDecision[]>([]);
  const [statusDefs, setStatusDefs] = useState<StatusDefinition[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // Additional dataset states for specialized report views
  const [extraWorkData, setExtraWorkData] = useState<any[]>([]);
  const [multiLocationData, setMultiLocationData] = useState<any[]>([]);
  const [attemptsData, setAttemptsData] = useState<any[]>([]);
  const [requestsData, setRequestsData] = useState<any[]>([]);
  const [auditLogData, setAuditLogData] = useState<any[]>([]);
  const [employeesData, setEmployeesData] = useState<any[]>([]);
  const [holidaysData, setHolidaysData] = useState<any[]>([]);
  const [weeklyOffsData, setWeeklyOffsData] = useState<any[]>([]);

  // Sync state with URL search param changes
  useEffect(() => {
    const p = new URLSearchParams(location.search);
    const typeFromUrl = p.get('type') as ReportType;
    if (typeFromUrl && typeFromUrl !== reportType) {
      setReportType(typeFromUrl);
    }
  }, [location.search]);

  // Fetch report data
  const handleFetchReport = () => {
    let isMounted = true;
    setLoading(true);
    setErrorMsg(null);

    // Primary generic raw dataset + rule engine call
    api.getRawReportDataset(filterDate)
      .then((res) => {
        if (isMounted) {
          if (res && res.raw_data && res.configuration) {
            const evaluatedDecisions = AttendanceRuleEngine.evaluateDataset(res);
            setDecisions(evaluatedDecisions);
            setStatusDefs(res.configuration.status_definitions || []);
          } else {
            setDecisions([]);
          }
        }
      })
      .catch((err) => {
        console.error('[Reports] Error fetching raw configuration dataset:', err);
        if (isMounted) {
          setDecisions([]);
          setErrorMsg('Failed to load attendance dataset from backend.');
        }
      })
      .finally(() => {
        if (isMounted) setLoading(false);
      });

    // Specialized data fetches based on report type
    if (reportType === 'extra_work') {
      api.getExtraWorkReport(filterDate).then(r => setExtraWorkData(r.records || [])).catch(() => setExtraWorkData([]));
    } else if (reportType === 'multi_location') {
      api.getMultiLocationReport(filterDate).then(r => setMultiLocationData(r.records || [])).catch(() => setMultiLocationData([]));
    } else if (reportType === 'biometric_attempts') {
      api.getAttempts({ date: filterDate, page_size: 100 }).then(r => setAttemptsData(r.records || [])).catch(() => setAttemptsData([]));
    } else if (reportType === 'requests') {
      api.getRequests({ date: filterDate, page_size: 100 }).then(r => setRequestsData(r.records || [])).catch(() => setRequestsData([]));
    } else if (reportType === 'audit_log') {
      api.getAuditLogs({ page_size: 100 }).then(r => setAuditLogData(r.records || [])).catch(() => setAuditLogData([]));
    } else if (reportType === 'employee_directory') {
      api.getEmployees({ page_size: 500 }).then(r => setEmployeesData(r.records || [])).catch(() => setEmployeesData([]));
    } else if (reportType === 'holiday_weekly_off') {
      api.getHolidays().then(r => setHolidaysData(r.records || [])).catch(() => setHolidaysData([]));
      api.getWeeklyOffs().then(r => setWeeklyOffsData(r.records || [])).catch(() => setWeeklyOffsData([]));
    }
  };

  useEffect(() => {
    handleFetchReport();
  }, [filterDate, reportType, refreshKey]);

  const handleResetFilters = () => {
    setFilterDate(selectedDate || new Date().toISOString().slice(0, 10));
    setSelectedDept('All Departments');
    setSelectedShift('All Shifts');
  };

  // Dynamically extract available departments and shifts from API results (ZERO HARDCODING)
  const availableDepartments = Array.from(
    new Set(decisions.map(d => d.department).filter(Boolean))
  ).sort();

  const availableShifts = Array.from(
    new Set(decisions.map(d => d.shift_name).filter(Boolean))
  ).sort();

  // Report details title & subtitle mapping
  const getReportMeta = (type: ReportType) => {
    switch (type) {
      case 'roll_up':
        return { title: 'Daily Roll-Up Attendance Report', subtitle: 'Aggregated attendance totals by date and department using the Time Office decision engine.' };
      case 'shift_summary':
        return { title: 'Shift-Wise Attendance Summary', subtitle: 'Breakdown of employee status across dynamically configured shift schedules.' };
      case 'daily':
        return { title: 'Daily Attendance Register', subtitle: 'Complete log of employee attendance events and verification details for the selected date.' };
      case 'present':
        return { title: 'Present Employees Report', subtitle: 'All employees evaluated as Present by the generic attendance decision engine.' };
      case 'present_first_punch':
        return { title: 'Present Report – 1st Punch', subtitle: 'Employees who completed a valid first punch during their shift period.' };
      case 'absent_first_punch':
        return { title: 'Absent Report – 1st Punch', subtitle: 'Employees who missed the first punch period on the selected date.' };
      case 'full_day_absent':
        return { title: 'Full-Day Absent Report – Department-wise', subtitle: 'Employees classified as full-day absent according to configured shift rules.' };
      case 'late':
        return { title: 'Late Report – 1st Punch', subtitle: 'Employees whose first punch occurred after the configured reference time.' };
      case 'not_marked':
        return { title: 'Not Marked / Absenteeism Risk Report', subtitle: 'Active employees who have not marked attendance for the target date.' };
      case 'shift_monitoring':
        return { title: 'Shift Monitoring & Period Progress', subtitle: 'Live verification window completion and period card monitoring.' };
      case 'monthly_summary':
        return { title: 'Employee-wise Monthly Summary', subtitle: 'Monthly aggregation of Present, Late, Absent, Half-day & Working Days per employee.' };
      case 'holiday_weekly_off':
        return { title: 'Holiday & Weekly-Off Calendar Report', subtitle: 'Database configured organizational holidays and weekly-off schedule.' };
      case 'extra_work':
        return { title: 'Extra Work / Overtime Report', subtitle: 'Submissions for extra work hours logged by mobile field staff.' };
      case 'multi_location':
        return { title: 'Multi-Location Punch Report', subtitle: 'Attendance punches tagged with GPS coordinates, accuracy, site name, and device ID.' };
      case 'biometric_attempts':
        return { title: 'Biometric Verification Attempts', subtitle: 'Raw telemetry of facial recognition and liveness verification attempts.' };
      case 'requests':
        return { title: 'Attendance Exceptions & Requests', subtitle: 'Fallback selfie attendance requests requiring operator approval.' };
      case 'audit_log':
        return { title: 'System Audit Log', subtitle: 'Immutable administrative action trail logged by backend.' };
      case 'employee_directory':
        return { title: 'Employee Master Directory', subtitle: 'Central database directory of active staff, designations, and department assignments.' };
    }
  };

  const { title, subtitle } = getReportMeta(reportType);

  // Filter evaluated decision objects dynamically
  const filteredDecisions = decisions.filter((d) => {
    if (reportType === 'full_day_absent' && d.full_day_status !== 'FULL_DAY_ABSENT') return false;
    if (reportType === 'late' && d.timing_status !== 'LATE') return false;
    if ((reportType === 'present' || reportType === 'present_first_punch') && d.attendance_status !== 'PRESENT') return false;
    if (reportType === 'absent_first_punch' && d.first_punch_status !== 'ABSENT_FIRST_PUNCH') return false;

    if (selectedDept !== 'All Departments' && d.department && d.department !== selectedDept) return false;
    if (selectedShift !== 'All Shifts' && !d.shift_name.toLowerCase().includes(selectedShift.toLowerCase())) return false;

    return true;
  });

  // Group decisions by Department dynamically for full_day_absent / roll_up report
  const departmentGroupedMap = React.useMemo(() => {
    const map = new Map<string, AttendanceDecision[]>();
    filteredDecisions.forEach((d) => {
      const dept = d.department || 'General / Unassigned';
      const list = map.get(dept) || [];
      list.push(d);
      map.set(dept, list);
    });
    return map;
  }, [filteredDecisions]);

  const departmentList = Array.from(departmentGroupedMap.keys()).sort();

  return (
    <div className="p-6 space-y-5 bg-[#090d16] min-h-screen text-slate-200">
      {/* 1. Page Main Header Area */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-[#111622] p-5 rounded-2xl border border-[#1e2638] shadow-lg">
        <div className="flex items-center gap-3.5">
          <div className="w-12 h-12 rounded-xl bg-[#f95700] text-white flex items-center justify-center shadow-md shadow-orange-500/20 shrink-0">
            <FileText className="w-6 h-6 stroke-[2.2]" />
          </div>
          <div>
            <h1 className="text-xl font-extrabold text-white tracking-tight">
              {title}
            </h1>
            <p className="text-xs font-medium text-slate-400 mt-0.5">
              {subtitle}
            </p>
          </div>
        </div>

        <div className="text-xs font-medium text-slate-400">
          <span>Reports</span>
          <span className="mx-1.5 text-slate-500">&gt;</span>
          <span className="text-[#f95700] font-semibold">{title}</span>
        </div>
      </div>

      {/* 2. Filter Bar Card */}
      <div className="bg-[#111622] border border-[#1e2638] rounded-2xl p-5 shadow-lg space-y-4">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-4 items-end">
          {/* Report Type Selector Dropdown */}
          <div className="md:col-span-2">
            <label className="block text-xs font-bold text-slate-300 mb-1.5">
              Select Report View <span className="text-[#f95700]">*</span>
            </label>
            <div className="relative">
              <select
                value={reportType}
                onChange={(e) => setReportType(e.target.value as ReportType)}
                className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl px-3.5 py-2 text-xs font-medium text-white appearance-none focus:outline-none focus:border-[#f95700]"
              >
                <option value="roll_up">1. Daily Roll-Up Attendance</option>
                <option value="shift_summary">2. Shift-Wise Attendance Summary</option>
                <option value="daily">3. Daily Attendance Register</option>
                <option value="present">4. Present Employees</option>
                <option value="present_first_punch">5. Present Report – 1st Punch</option>
                <option value="absent_first_punch">6. Absent Report – 1st Punch</option>
                <option value="full_day_absent">7. Full-Day Absent – Department-wise</option>
                <option value="late">8. Late Report – 1st Punch</option>
                <option value="not_marked">9. Not Marked / Absenteeism Risk</option>
                <option value="shift_monitoring">10. Shift Monitoring & Period Progress</option>
                <option value="monthly_summary">11. Employee-wise Monthly Summary</option>
                <option value="holiday_weekly_off">12. Holiday / Weekly-Off</option>
                <option value="extra_work">13. Extra Work</option>
                <option value="multi_location">14. Multi-Location Punch</option>
                <option value="biometric_attempts">15. Biometric Verification Attempts</option>
                <option value="requests">16. Attendance Exceptions & Requests</option>
                <option value="audit_log">17. System Audit Log</option>
                <option value="employee_directory">18. Employee Master Directory</option>
              </select>
              <ChevronDown className="w-4 h-4 text-slate-500 absolute right-3 top-2.5 pointer-events-none" />
            </div>
          </div>

          {/* Date Picker Field */}
          <div>
            <label className="block text-xs font-bold text-slate-300 mb-1.5">
              Target Date <span className="text-[#f95700]">*</span>
            </label>
            <div className="relative">
              <input
                type="text"
                value={filterDate}
                onChange={(e) => setFilterDate(e.target.value)}
                placeholder="YYYY-MM-DD"
                className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl px-3.5 py-2 text-xs font-medium text-white focus:outline-none focus:border-[#f95700]"
              />
              <CalendarIcon className="w-4 h-4 text-slate-500 absolute right-3 top-2.5 pointer-events-none" />
            </div>
          </div>

          {/* Department Select Dropdown (Dynamic options from API) */}
          <div>
            <label className="block text-xs font-bold text-slate-300 mb-1.5">
              Department
            </label>
            <div className="relative">
              <select
                value={selectedDept}
                onChange={(e) => setSelectedDept(e.target.value)}
                className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl px-3.5 py-2 text-xs font-medium text-white appearance-none focus:outline-none focus:border-[#f95700]"
              >
                <option value="All Departments">All Departments</option>
                {availableDepartments.map(dept => (
                  <option key={dept} value={dept}>{dept}</option>
                ))}
              </select>
              <ChevronDown className="w-4 h-4 text-slate-500 absolute right-3 top-2.5 pointer-events-none" />
            </div>
          </div>

          {/* Action Buttons: Generate & Reset */}
          <div className="flex items-center gap-2.5">
            <button
              onClick={handleFetchReport}
              className="flex-1 bg-[#f95700] hover:bg-[#ea4e00] text-white font-bold px-4 py-2 rounded-xl text-xs flex items-center justify-center gap-2 shadow-lg shadow-orange-500/20 transition-all cursor-pointer"
            >
              <Search className="w-4 h-4 stroke-[2.5]" />
              <span>Fetch</span>
            </button>
            <button
              onClick={handleResetFilters}
              className="bg-[#0c1018] border border-[#242f48] hover:bg-slate-800 text-slate-300 font-semibold px-3 py-2 rounded-xl text-xs flex items-center gap-1.5 transition-colors cursor-pointer"
            >
              <RotateCw className="w-3.5 h-3.5 text-slate-400" />
              <span>Reset</span>
            </button>
          </div>
        </div>
      </div>

      {/* 3. Export Buttons Container */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div className="flex-1 bg-[#111622] border border-[#1e2638] text-slate-300 px-4 py-2.5 rounded-xl flex items-center gap-2.5 text-xs font-medium shadow-sm">
          <Info className="w-4 h-4 text-[#f95700] shrink-0" />
          <span>Active Report: <strong className="text-white">{title}</strong> for date {filterDate}. Powered by backend configuration.</span>
        </div>

        <div className="shrink-0">
          <ExportButtons
            headers={['#', 'Employee ID', 'Employee Name', 'Department', 'Shift', 'Date', 'Status', 'Timing Status', 'First Punch Time', 'Location']}
            data={filteredDecisions.map((d, idx) => ({
              '#': idx + 1,
              'Employee ID': d.employee_id,
              'Employee Name': d.employee_name,
              'Department': d.department,
              'Shift': d.shift_name,
              'Date': d.attendance_date,
              'Status': d.attendance_status,
              'Timing Status': d.timing_status,
              'First Punch Time': d.first_punch_time || '—',
              'Location': d.location_name
            }))}
            fileName={`${reportType}_Report_${filterDate}`}
          />
        </div>
      </div>

      {/* 4. Dynamic Main Report Content Table */}
      {loading ? (
        <div className="bg-[#111622] border border-[#1e2638] rounded-2xl p-16 text-center text-xs text-slate-400 font-mono shadow-lg">
          <div className="w-7 h-7 border-2 border-[#f95700] border-t-transparent rounded-full animate-spin mx-auto mb-3" />
          <span>Evaluating attendance rules from backend API...</span>
        </div>
      ) : errorMsg ? (
        <div className="bg-[#111622] border border-rose-500/30 rounded-2xl p-16 text-center text-xs text-rose-400 font-medium shadow-lg">
          {errorMsg}
        </div>
      ) : (
        <div className="bg-white border border-slate-200/90 rounded-2xl overflow-hidden shadow-sm">
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse table-dense">
              <thead>
                <tr>
                  <th className="w-12 text-center">#</th>
                  <th>Employee ID</th>
                  <th>Employee Name</th>
                  <th>Department</th>
                  <th>Shift Code</th>
                  <th>Shift Name</th>
                  <th>Attendance Date</th>
                  <th>First Punch</th>
                  <th>Attendance Status</th>
                  <th>Timing Status</th>
                  <th>Location Name</th>
                </tr>
              </thead>
              <tbody>
                {filteredDecisions.length === 0 ? (
                  <tr>
                    <td colSpan={11} className="text-center py-16 text-slate-500">
                      <div className="flex flex-col items-center justify-center gap-2">
                        <div className="w-12 h-12 rounded-full bg-slate-100 flex items-center justify-center text-slate-400">
                          <Clock className="w-6 h-6" />
                        </div>
                        <span className="font-bold text-slate-700 text-sm">No records found for the selected date ({filterDate}).</span>
                        <span className="text-xs text-slate-400">Try adjusting the filter criteria or selecting another date.</span>
                      </div>
                    </td>
                  </tr>
                ) : (
                  filteredDecisions.map((d, idx) => (
                    <tr key={d.employee_id + idx} className="hover:bg-slate-50/80 transition-colors">
                      <td className="text-center font-medium text-slate-500">{idx + 1}</td>
                      <td className="font-semibold text-slate-800">{d.employee_id}</td>
                      <td className="font-medium text-slate-900">{d.employee_name || '—'}</td>
                      <td className="text-slate-700">{d.department}</td>
                      <td className="font-semibold text-slate-700">{d.shift_code}</td>
                      <td className="text-slate-700">{d.shift_name}</td>
                      <td className="text-slate-600">{d.attendance_date}</td>
                      <td className="font-bold text-slate-900 font-mono">{d.first_punch_time || '—'}</td>
                      <td>
                        <span className={`px-2.5 py-0.5 rounded-full font-bold text-[11px] uppercase tracking-wider inline-block ${
                          d.attendance_status === 'PRESENT'
                            ? 'bg-[#dcfce7] text-[#15803d] border border-[#bbf7d0]'
                            : 'bg-[#ffe4e6] text-[#be123c] border border-[#fecdd3]'
                        }`}>
                          {d.attendance_status}
                        </span>
                      </td>
                      <td>
                        <span className={`px-2.5 py-0.5 rounded-full font-bold text-[11px] uppercase tracking-wider inline-block ${
                          d.timing_status === 'LATE'
                            ? 'bg-[#ffe4e6] text-[#be123c] border border-[#fecdd3]'
                            : 'bg-[#dcfce7] text-[#15803d] border border-[#bbf7d0]'
                        }`}>
                          {d.timing_status}
                        </span>
                      </td>
                      <td className="text-slate-700">{d.location_name}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* 5. Pagination Footer */}
      <div className="px-5 py-3.5 bg-white border border-slate-200/90 rounded-2xl flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-xs text-slate-500 font-medium shadow-sm">
        <div>
          Showing {filteredDecisions.length} evaluated decision record(s)
        </div>

        <div className="flex items-center gap-1.5 select-none">
          <button className="w-8 h-8 rounded-lg border border-slate-200 flex items-center justify-center text-slate-400 hover:bg-slate-50 disabled:opacity-50">
            <ChevronLeft className="w-4 h-4" />
          </button>
          <button className="w-8 h-8 rounded-lg bg-[#f95700] text-white font-bold flex items-center justify-center shadow-sm">
            1
          </button>
          <button className="w-8 h-8 rounded-lg border border-slate-200 flex items-center justify-center text-slate-400 hover:bg-slate-50">
            <ChevronRight className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  );
};
