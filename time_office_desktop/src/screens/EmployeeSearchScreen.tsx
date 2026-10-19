import React, { useState, useEffect, useCallback } from 'react';
import { api } from '../services/api';
import { EmployeeListItem } from '../types';
import { EmployeeProfileModal } from './EmployeeProfileModal';
import { UserModal } from '../components/common/UserModal';
import { ExportButtons } from '../components/common/ExportButtons';
import { 
  Users, 
  Search, 
  ChevronLeft, 
  ChevronRight, 
  CheckCircle2, 
  XCircle,
  ExternalLink,
  UserPlus,
  Edit3,
  Building2,
  RefreshCw
} from 'lucide-react';

export const EmployeeSearchScreen: React.FC = () => {
  const [employees, setEmployees] = useState<EmployeeListItem[]>([]);
  const [total, setTotal] = useState<number>(0);
  const [loading, setLoading] = useState<boolean>(true);
  const [search, setSearch] = useState<string>('');
  const [shiftFilter, setShiftFilter] = useState<number | undefined>(undefined);
  const [shifts, setShifts] = useState<{ id: number; shift_code: string; shift_name: string }[]>([]);
  const [page, setPage] = useState<number>(1);
  const pageSize = 50;

  // Modals state
  const [selectedEmployeeId, setSelectedEmployeeId] = useState<string | null>(null);
  const [isUserModalOpen, setIsUserModalOpen] = useState<boolean>(false);
  const [userToEdit, setUserToEdit] = useState<any | null>(null);

  // Load shifts for filter
  useEffect(() => {
    api.getShifts()
      .then((data) => {
        const arr = Array.isArray(data) ? data : (data?.shifts ?? data?.data ?? []);
        setShifts(arr);
      })
      .catch((err) => {
        console.error('[EmployeeSearch] getShifts error:', err);
        setShifts([]);
      });
  }, []);

  // Fetch employees
  const loadEmployees = useCallback(() => {
    setLoading(true);
    api.getEmployees({
      search: search.trim() || undefined,
      shift_id: shiftFilter,
      page,
      page_size: pageSize,
    })
      .then((res) => {
        setEmployees(res.records || []);
        setTotal(res.total || 0);
        setLoading(false);
      })
      .catch((err) => {
        console.error('[EmployeeSearch] Error:', err);
        setLoading(false);
      });
  }, [search, shiftFilter, page]);

  useEffect(() => {
    loadEmployees();
  }, [loadEmployees]);

  const handleOpenAddModal = () => {
    setUserToEdit(null);
    setIsUserModalOpen(true);
  };

  const handleOpenEditModal = (emp: EmployeeListItem, e: React.MouseEvent) => {
    e.stopPropagation();
    setUserToEdit({
      id: emp.id,
      employee_id: emp.employee_id,
      full_name: emp.full_name,
      role: emp.role,
      department: emp.department,
      department_id: emp.department_id,
      unit_number: emp.unit_number,
      designation: emp.designation,
      is_active: emp.is_active,
    });
    setIsUserModalOpen(true);
  };

  const totalPages = Math.ceil(total / pageSize) || 1;

  return (
    <div className="p-6 space-y-5 bg-[#090d16] min-h-screen text-slate-200">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-[#111622] p-5 rounded-2xl border border-[#1e2638] shadow-lg">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2.5 tracking-tight">
            <Users className="w-6 h-6 text-[#f95700]" />
            <span>Employee Master Directory & User Management</span>
          </h2>
          <p className="text-xs text-slate-400 mt-1">
            Search active staff, add new users with department & unit assignment, or edit profiles
          </p>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={handleOpenAddModal}
            className="flex items-center gap-2 px-4 py-2 bg-[#f95700] hover:bg-[#e04e00] text-white text-xs font-bold rounded-xl shadow-md transition-colors"
          >
            <UserPlus className="w-4 h-4" />
            <span>+ Add New User</span>
          </button>

          <ExportButtons
            data={employees.map((e) => ({
              'Employee ID': e.employee_id,
              'Full Name': e.full_name,
              'Department': e.department || 'N/A',
              'Department ID': e.department_id || 'N/A',
              'Unit Number': e.unit_number || 'N/A',
              'Designation': e.designation || 'N/A',
              'Role': e.role,
              'Active': e.is_active ? 'YES' : 'NO',
              'Shift Name': e.assigned_shift?.shift_name || 'NONE',
              'Face Enrolled': e.has_face_enrolled ? 'YES' : 'NO'
            }))}
            fileName="Employees_Directory"
          />
        </div>
      </div>

      {/* Filter Bar */}
      <div className="flex flex-wrap items-center justify-between gap-3 bg-[#111622] p-4 rounded-xl border border-[#1e2638] text-xs shadow-md">
        <div className="flex flex-wrap items-center gap-3 flex-1 min-w-[280px]">
          {/* Search box */}
          <div className="relative flex-1 max-w-sm">
            <Search className="w-4 h-4 text-slate-500 absolute left-3 top-2.5" />
            <input
              type="text"
              placeholder="Search by Employee ID, Full Name, or Department..."
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setPage(1);
              }}
              className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl pl-9 pr-3 py-2 text-xs font-medium text-white placeholder-slate-500 focus:outline-none focus:border-[#f95700]"
            />
          </div>

          {/* Shift filter */}
          <select
            value={shiftFilter || ''}
            onChange={(e) => {
              setShiftFilter(e.target.value ? Number(e.target.value) : undefined);
              setPage(1);
            }}
            className="bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-xs font-medium text-white focus:outline-none focus:border-[#f95700]"
          >
            <option value="">All Shifts</option>
            {Array.isArray(shifts) && shifts.map((s) => (
              <option key={s.id} value={s.id}>
                {s.shift_name} ({s.shift_code})
              </option>
            ))}
          </select>

          <button
            onClick={loadEmployees}
            className="p-2 bg-[#0c1018] border border-[#242f48] rounded-xl text-slate-400 hover:text-white transition-colors"
            title="Refresh List"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>

        {/* Counter & Pagination controls */}
        <div className="flex items-center gap-3">
          <span className="text-slate-400 font-mono text-xs">
            Total: <strong className="text-white">{total}</strong> employees
          </span>

          <div className="flex items-center gap-1 border border-[#242f48] rounded-xl bg-[#0c1018] px-1 py-0.5">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page <= 1}
              className="p-1 text-slate-400 hover:text-white disabled:opacity-30 rounded"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            <span className="text-[11px] font-mono px-2 text-slate-300">
              {page} / {totalPages}
            </span>
            <button
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={page >= totalPages}
              className="p-1 text-slate-400 hover:text-white disabled:opacity-30 rounded"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      {/* Main Table */}
      <div className="bg-[#111622] border border-[#1e2638] rounded-2xl overflow-hidden shadow-lg">
        <div className="overflow-x-auto max-h-[64vh]">
          <table className="w-full text-left table-dense">
            <thead>
              <tr>
                <th>Emp ID</th>
                <th>Employee Name</th>
                <th>Department & Unit</th>
                <th>Assigned Shift</th>
                <th>Face Enrolled</th>
                <th>Role</th>
                <th>Account Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={8} className="text-center py-16 text-slate-400 text-xs font-mono">
                    <div className="w-7 h-7 border-2 border-[#f95700] border-t-transparent rounded-full animate-spin mx-auto mb-3" />
                    Searching employee directory...
                  </td>
                </tr>
              ) : employees.length === 0 ? (
                <tr>
                  <td colSpan={8} className="text-center py-16 text-slate-400 text-xs">
                    No employees found matching search query.
                  </td>
                </tr>
              ) : (
                employees.map((emp) => (
                  <tr
                    key={emp.id}
                    onClick={() => setSelectedEmployeeId(emp.employee_id)}
                    className="cursor-pointer hover:bg-slate-800/40 transition-colors"
                  >
                    <td className="font-mono font-bold text-[#f95700]">{emp.employee_id}</td>
                    <td>
                      <div className="font-semibold text-white">{emp.full_name}</div>
                      {emp.designation && (
                        <div className="text-[10px] text-slate-400 font-mono">{emp.designation}</div>
                      )}
                    </td>
                    <td>
                      {emp.department ? (
                        <div className="flex items-center gap-1.5 text-xs">
                          <Building2 className="w-3.5 h-3.5 text-[#f95700] shrink-0" />
                          <div>
                            <span className="font-bold text-white">{emp.department}</span>
                            <div className="text-[10px] text-slate-400 font-mono flex items-center gap-2">
                              {emp.department_id && <span>ID: <strong className="text-amber-400">{emp.department_id}</strong></span>}
                              {emp.unit_number && <span>Unit: <strong className="text-emerald-400">{emp.unit_number}</strong></span>}
                            </div>
                          </div>
                        </div>
                      ) : (
                        <span className="text-slate-500 italic text-xs">Unassigned</span>
                      )}
                    </td>
                    <td className="text-slate-300">
                      <div>{emp.assigned_shift?.shift_name || 'Unassigned'}</div>
                      <div className="font-mono text-slate-400 text-[10px]">{emp.assigned_shift?.shift_code || '--'}</div>
                    </td>
                    <td>
                      {emp.has_face_enrolled ? (
                        <span className="inline-flex items-center gap-1 text-[11px] font-bold text-emerald-400 bg-emerald-500/15 border border-emerald-500/30 px-2.5 py-0.5 rounded-full">
                          <CheckCircle2 className="w-3 h-3" /> Enrolled
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 text-[11px] font-medium text-slate-400 bg-slate-800 px-2.5 py-0.5 rounded-full">
                          <XCircle className="w-3 h-3 text-slate-500" /> Pending
                        </span>
                      )}
                    </td>
                    <td className="font-mono text-slate-400 text-[11px]">{emp.role}</td>
                    <td>
                      <span className={`px-2.5 py-0.5 rounded-full text-[10px] font-bold border ${
                        emp.is_active ? 'bg-emerald-500/15 text-emerald-400 border-emerald-500/30' : 'bg-rose-500/15 text-rose-400 border-rose-500/30'
                      }`}>
                        {emp.is_active ? 'ACTIVE' : 'INACTIVE'}
                      </span>
                    </td>
                    <td>
                      <div className="flex items-center gap-2">
                        <button
                          onClick={(e) => handleOpenEditModal(emp, e)}
                          className="px-2.5 py-1 text-xs rounded-lg bg-slate-800 hover:bg-slate-700 text-amber-300 border border-slate-700 flex items-center gap-1 font-semibold transition-colors"
                          title="Edit Department / User Details"
                        >
                          <Edit3 className="w-3 h-3 text-amber-400" />
                          Edit
                        </button>

                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            setSelectedEmployeeId(emp.employee_id);
                          }}
                          className="px-2.5 py-1 text-xs rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 flex items-center gap-1 font-semibold transition-colors"
                        >
                          <ExternalLink className="w-3 h-3 text-[#f95700]" />
                          Profile
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Add / Edit User Modal */}
      <UserModal
        isOpen={isUserModalOpen}
        onClose={() => setIsUserModalOpen(false)}
        onSuccess={loadEmployees}
        userToEdit={userToEdit}
      />

      {/* Employee Profile Detailed Modal */}
      {selectedEmployeeId && (
        <EmployeeProfileModal
          isOpen={!!selectedEmployeeId}
          onClose={() => setSelectedEmployeeId(null)}
          employeeId={selectedEmployeeId}
        />
      )}
    </div>
  );
};

export default EmployeeSearchScreen;
