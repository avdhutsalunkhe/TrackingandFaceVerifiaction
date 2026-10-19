import React, { useState, useEffect } from 'react';
import { api } from '../services/api';
import { UserModal } from '../components/common/UserModal';
import {
  Building2,
  Search,
  RefreshCw,
  ChevronRight,
  UserPlus,
  Edit3
} from 'lucide-react';

interface EmployeeItem {
  id: number;
  employee_id: string;
  full_name: string;
  role?: string;
  department?: string;
  department_id?: number;
  unit_number?: number;
  designation?: string;
  is_active?: boolean;
  shift_name?: string;
}

interface DepartmentGroup {
  name: string;
  total: number;
  active: number;
  employees: EmployeeItem[];
}

export const DepartmentsScreen: React.FC = () => {
  const [employees, setEmployees] = useState<EmployeeItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [selectedDept, setSelectedDept] = useState<string | null>(null);

  // User modal state
  const [isUserModalOpen, setIsUserModalOpen] = useState<boolean>(false);
  const [userToEdit, setUserToEdit] = useState<any | null>(null);

  useEffect(() => {
    loadEmployees();
  }, []);

  const loadEmployees = async () => {
    setLoading(true);
    try {
      const res = await api.getEmployees({ page_size: 1000 });
      setEmployees(res.records || []);
    } catch (err) {
      console.error('Failed to load employees for department grouping', err);
    } finally {
      setLoading(false);
    }
  };

  const handleOpenAddModal = (presetDeptName?: string) => {
    setUserToEdit(presetDeptName ? { department: presetDeptName } : null);
    setIsUserModalOpen(true);
  };

  const handleOpenEditModal = (emp: EmployeeItem) => {
    setUserToEdit({
      id: emp.id,
      employee_id: emp.employee_id,
      full_name: emp.full_name,
      role: emp.role || 'USER',
      department: emp.department,
      department_id: emp.department_id,
      unit_number: emp.unit_number,
      designation: emp.designation,
      is_active: emp.is_active,
    });
    setIsUserModalOpen(true);
  };

  // Group employees by department
  const departmentMap: Record<string, EmployeeItem[]> = {};
  employees.forEach((emp) => {
    const dept = emp.department?.trim() || 'General / Unassigned';
    if (!departmentMap[dept]) {
      departmentMap[dept] = [];
    }
    departmentMap[dept].push(emp);
  });

  const departmentGroups: DepartmentGroup[] = Object.keys(departmentMap)
    .sort()
    .map((name) => {
      const emps = departmentMap[name];
      return {
        name,
        total: emps.length,
        active: emps.filter((e) => e.is_active !== false).length,
        employees: emps,
      };
    });

  const filteredDepts = departmentGroups.filter(
    (g) =>
      g.name.toLowerCase().includes(search.toLowerCase()) ||
      g.employees.some((e) => e.full_name.toLowerCase().includes(search.toLowerCase()))
  );

  const activeDept = selectedDept
    ? departmentGroups.find((g) => g.name === selectedDept) || filteredDepts[0]
    : filteredDepts[0];

  return (
    <div className="p-6 space-y-6 bg-[#090d16] min-h-screen text-slate-200">
      {/* Header Banner */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-[#111622] p-5 rounded-2xl border border-[#1e2638] shadow-lg">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-[#f95700]/10 text-[#f95700] border border-[#f95700]/30 flex items-center justify-center">
            <Building2 className="w-5 h-5" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-white tracking-tight">Department Master Management</h1>
            <p className="text-xs text-slate-400 mt-0.5">
              Overview of department headcount, unit numbers, and employee roster assignments
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={() => handleOpenAddModal(activeDept?.name)}
            className="flex items-center gap-2 px-4 py-2 bg-[#f95700] hover:bg-[#e04e00] text-white text-xs font-bold rounded-xl shadow-md transition-colors"
          >
            <UserPlus className="w-4 h-4" />
            <span>+ Add User to Department</span>
          </button>

          <button
            onClick={loadEmployees}
            className="flex items-center gap-2 px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold rounded-xl border border-slate-700 transition-colors self-start md:self-auto"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            <span>Refresh</span>
          </button>
        </div>
      </div>

      {/* Main Grid Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left Column: Department List */}
        <div className="space-y-4">
          <div className="relative">
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" />
            <input
              type="text"
              placeholder="Search department..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full bg-[#111622] border border-[#1e2638] rounded-xl pl-9 pr-4 py-2.5 text-xs text-white placeholder:text-slate-500 focus:outline-none focus:border-[#f95700] transition-colors"
            />
          </div>

          <div className="space-y-2 max-h-[70vh] overflow-y-auto pr-1">
            {loading ? (
              <div className="p-8 text-center bg-[#111622] rounded-xl border border-[#1e2638] text-xs text-slate-400 font-mono">
                Loading Departments...
              </div>
            ) : filteredDepts.length === 0 ? (
              <div className="p-8 text-center bg-[#111622] rounded-xl border border-[#1e2638] text-xs text-slate-500">
                No departments found.
              </div>
            ) : (
              filteredDepts.map((group) => {
                const isSelected = activeDept?.name === group.name;
                return (
                  <div
                    key={group.name}
                    onClick={() => setSelectedDept(group.name)}
                    className={`p-4 rounded-xl border transition-all cursor-pointer flex items-center justify-between ${
                      isSelected
                        ? 'bg-gradient-to-r from-[#f95700]/15 to-transparent border-[#f95700] text-white shadow-md'
                        : 'bg-[#111622] border-[#1e2638] hover:border-slate-700 text-slate-300'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <div
                        className={`w-8 h-8 rounded-lg flex items-center justify-center ${
                          isSelected
                            ? 'bg-[#f95700] text-white'
                            : 'bg-slate-800 text-slate-400'
                        }`}
                      >
                        <Building2 className="w-4 h-4" />
                      </div>
                      <div>
                        <h3 className="text-xs font-bold text-white">{group.name}</h3>
                        <p className="text-[10px] text-slate-400 font-mono">
                          {group.active} Active / {group.total} Total
                        </p>
                      </div>
                    </div>
                    <ChevronRight
                      className={`w-4 h-4 transition-transform ${
                        isSelected ? 'text-[#f95700] translate-x-1' : 'text-slate-600'
                      }`}
                    />
                  </div>
                );
              })
            )}
          </div>
        </div>

        {/* Right Column: Selected Department Details & Roster */}
        <div className="lg:col-span-2">
          {activeDept ? (
            <div className="bg-[#111622] border border-[#1e2638] rounded-2xl p-5 space-y-5 shadow-lg">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-[#1e2638] pb-4">
                <div>
                  <h2 className="text-lg font-bold text-white flex items-center gap-2">
                    <Building2 className="w-5 h-5 text-[#f95700]" />
                    <span>{activeDept.name}</span>
                  </h2>
                  <p className="text-xs text-slate-400 mt-0.5">
                    Department employee roster and unit assignments
                  </p>
                </div>
                <div className="flex items-center gap-3 text-xs font-mono">
                  <span className="px-3 py-1 bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 rounded-xl font-bold">
                    Active: {activeDept.active}
                  </span>
                  <span className="px-3 py-1 bg-slate-800 border border-slate-700 text-slate-200 rounded-xl font-bold">
                    Total: {activeDept.total}
                  </span>
                </div>
              </div>

              {/* Employee Table */}
              <div className="overflow-x-auto rounded-xl border border-[#1e2638]">
                <table className="w-full text-left table-dense">
                  <thead>
                    <tr>
                      <th>Emp ID</th>
                      <th>Name</th>
                      <th>Department ID & Unit</th>
                      <th>Designation</th>
                      <th>Status</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {activeDept.employees.map((emp) => (
                      <tr key={emp.id} className="hover:bg-slate-800/40 transition-colors">
                        <td className="font-mono font-bold text-[#f95700]">
                          {emp.employee_id}
                        </td>
                        <td className="font-semibold text-white">
                          {emp.full_name}
                        </td>
                        <td className="font-mono text-xs text-slate-300">
                          {emp.department_id ? `ID: ${emp.department_id}` : '--'}
                          {emp.unit_number ? ` (Unit ${emp.unit_number})` : ''}
                        </td>
                        <td className="text-slate-300">
                          {emp.designation || 'Staff'}
                        </td>
                        <td>
                          <span
                            className={`px-2.5 py-0.5 rounded-full text-[10px] font-bold border ${
                              emp.is_active !== false
                                ? 'bg-emerald-500/15 text-emerald-400 border-emerald-500/30'
                                : 'bg-rose-500/15 text-rose-400 border-rose-500/30'
                            }`}
                          >
                            {emp.is_active !== false ? 'ACTIVE' : 'INACTIVE'}
                          </span>
                        </td>
                        <td>
                          <button
                            onClick={() => handleOpenEditModal(emp)}
                            className="px-2 py-1 text-xs rounded-lg bg-slate-800 hover:bg-slate-700 text-amber-300 border border-slate-700 flex items-center gap-1 font-semibold transition-colors"
                          >
                            <Edit3 className="w-3 h-3 text-amber-400" />
                            Edit
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          ) : (
            <div className="bg-[#111622] border border-[#1e2638] rounded-2xl p-12 text-center text-slate-400 text-xs font-medium">
              Select a department on the left to view details.
            </div>
          )}
        </div>
      </div>

      {/* Add / Edit User Modal */}
      <UserModal
        isOpen={isUserModalOpen}
        onClose={() => setIsUserModalOpen(false)}
        onSuccess={loadEmployees}
        userToEdit={userToEdit}
      />
    </div>
  );
};

export default DepartmentsScreen;
