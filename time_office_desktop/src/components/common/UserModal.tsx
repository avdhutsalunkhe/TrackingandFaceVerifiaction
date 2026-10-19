import React, { useState, useEffect, useRef } from 'react';
import { Modal } from './Modal';
import { api } from '../../services/api';
import { 
  searchDepartments, 
  getUniqueUnitNumbers, 
  DEPARTMENT_UNIT_LIST,
  DepartmentUnitItem 
} from '../../data/departmentsData';
import { 
  Search, 
  Building2, 
  Layers, 
  User, 
  ShieldCheck, 
  KeyRound, 
  Briefcase, 
  Check, 
  X,
  AlertCircle,
  CheckCircle2
} from 'lucide-react';

export interface UserModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  userToEdit?: {
    id: number;
    employee_id: string;
    full_name: string;
    role?: string;
    department?: string;
    department_id?: number;
    unit_number?: number;
    designation?: string;
    is_active?: boolean;
  } | null;
}

export const UserModal: React.FC<UserModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  userToEdit,
}) => {
  const isEdit = Boolean(userToEdit);

  // Form states
  const [employeeId, setEmployeeId] = useState<string>('');
  const [fullName, setFullName] = useState<string>('');
  const [role, setRole] = useState<string>('USER');
  const [password, setPassword] = useState<string>('');
  
  // Department & Unit states
  const [departmentSearch, setDepartmentSearch] = useState<string>('');
  const [departmentName, setDepartmentName] = useState<string>('');
  const [departmentId, setDepartmentId] = useState<string>('');
  const [unitNumber, setUnitNumber] = useState<string>('101');
  const [designation, setDesignation] = useState<string>('');
  const [isActive, setIsActive] = useState<boolean>(true);

  // UI / Search Dropdown states
  const [showDeptDropdown, setShowDeptDropdown] = useState<boolean>(false);
  const [filteredDepts, setFilteredDepts] = useState<DepartmentUnitItem[]>([]);
  const [loading, setLoading] = useState<boolean>(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  const dropdownRef = useRef<HTMLDivElement>(null);
  const uniqueUnits = getUniqueUnitNumbers();

  // Populate form on edit mode
  useEffect(() => {
    if (isOpen) {
      setErrorMsg(null);
      setSuccessMsg(null);
      if (userToEdit) {
        setEmployeeId(userToEdit.employee_id || '');
        setFullName(userToEdit.full_name || '');
        setRole(userToEdit.role || 'USER');
        setPassword('');
        setDepartmentName(userToEdit.department || '');
        setDepartmentSearch(userToEdit.department || '');
        setDepartmentId(userToEdit.department_id !== undefined && userToEdit.department_id !== null ? String(userToEdit.department_id) : '');
        setUnitNumber(userToEdit.unit_number !== undefined && userToEdit.unit_number !== null ? String(userToEdit.unit_number) : '101');
        setDesignation(userToEdit.designation || '');
        setIsActive(userToEdit.is_active !== false);
      } else {
        setEmployeeId('');
        setFullName('');
        setRole('USER');
        setPassword('');
        setDepartmentName('');
        setDepartmentSearch('');
        setDepartmentId('');
        setUnitNumber('101');
        setDesignation('');
        setIsActive(true);
      }
    }
  }, [isOpen, userToEdit]);

  // Handle department search filtering
  useEffect(() => {
    const results = searchDepartments(departmentSearch);
    setFilteredDepts(results);
  }, [departmentSearch]);

  // Close dropdown on click outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setShowDeptDropdown(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleSelectDepartment = (item: DepartmentUnitItem) => {
    setDepartmentName(item.department_name);
    setDepartmentSearch(item.department_name);
    setDepartmentId(String(item.department_id));
    setUnitNumber(String(item.unit_number));
    setShowDeptDropdown(false);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg(null);
    setSuccessMsg(null);

    if (!employeeId.trim()) {
      setErrorMsg('Employee ID is required.');
      return;
    }
    if (!fullName.trim()) {
      setErrorMsg('Full Name is required.');
      return;
    }

    setLoading(true);
    try {
      const payload: any = {
        employee_id: employeeId.trim(),
        full_name: fullName.trim(),
        role,
        department: departmentName.trim() || undefined,
        department_id: departmentId ? Number(departmentId) : undefined,
        unit_number: unitNumber ? Number(unitNumber) : undefined,
        designation: designation.trim() || undefined,
        is_active: isActive,
      };

      if (isEdit && userToEdit) {
        if (password.trim()) {
          payload.password = password.trim();
        }
        await api.updateUser(userToEdit.id, payload);
        setSuccessMsg(`User ${employeeId} updated successfully.`);
      } else {
        if (password.trim()) {
          payload.initial_password = password.trim();
        }
        await api.createUser(payload);
        setSuccessMsg(`New user ${employeeId} created successfully.`);
      }

      setTimeout(() => {
        onSuccess();
        onClose();
      }, 1000);
    } catch (err: any) {
      console.error('[UserModal] Error saving user:', err);
      const detail = err.response?.data?.detail || err.message || 'Failed to save user.';
      setErrorMsg(typeof detail === 'string' ? detail : JSON.stringify(detail));
    } finally {
      setLoading(false);
    }
  };

  if (!isOpen) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEdit ? `Edit User: ${userToEdit?.employee_id}` : 'Add New Employee / User'}
      subtitle={isEdit ? 'Update employee department, unit, role, and details' : 'Register a new employee with department & unit assignment'}
      maxWidth="max-w-2xl"
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Status Alerts */}
        {errorMsg && (
          <div className="flex items-center gap-2 p-3 bg-rose-500/10 border border-rose-500/30 text-rose-400 text-xs rounded-xl font-medium">
            <AlertCircle className="w-4 h-4 shrink-0 text-rose-400" />
            <span>{errorMsg}</span>
          </div>
        )}

        {successMsg && (
          <div className="flex items-center gap-2 p-3 bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 text-xs rounded-xl font-medium">
            <CheckCircle2 className="w-4 h-4 shrink-0 text-emerald-400" />
            <span>{successMsg}</span>
          </div>
        )}

        {/* Form Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Employee ID */}
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Employee ID <span className="text-rose-400">*</span>
            </label>
            <div className="relative">
              <User className="w-4 h-4 text-slate-500 absolute left-3 top-2.5" />
              <input
                type="text"
                placeholder="e.g. EMP1001"
                value={employeeId}
                disabled={isEdit}
                onChange={(e) => setEmployeeId(e.target.value)}
                className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl pl-9 pr-3 py-2 text-xs font-medium text-white placeholder-slate-500 focus:outline-none focus:border-[#f95700] disabled:opacity-60"
                required
              />
            </div>
          </div>

          {/* Full Name */}
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Full Name <span className="text-rose-400">*</span>
            </label>
            <input
              type="text"
              placeholder="e.g. Ramesh Sharma"
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-xs font-medium text-white placeholder-slate-500 focus:outline-none focus:border-[#f95700]"
              required
            />
          </div>

          {/* Role selection */}
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1 flex items-center gap-1">
              <ShieldCheck className="w-3.5 h-3.5 text-[#f95700]" />
              <span>System Role</span>
            </label>
            <select
              value={role}
              onChange={(e) => setRole(e.target.value)}
              className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-xs font-medium text-white focus:outline-none focus:border-[#f95700]"
            >
              <option value="USER">USER (Standard Employee)</option>
              <option value="TIME_OFFICE">TIME_OFFICE (Operator)</option>
              <option value="ADMIN">ADMIN (Administrator)</option>
            </select>
          </div>

          {/* Password field */}
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1 flex items-center gap-1">
              <KeyRound className="w-3.5 h-3.5 text-slate-400" />
              <span>{isEdit ? 'Reset Password (Optional)' : 'Initial Password'}</span>
            </label>
            <input
              type="password"
              placeholder={isEdit ? 'Leave blank to keep unchanged' : 'Defaults to Employee ID'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-xs font-medium text-white placeholder-slate-500 focus:outline-none focus:border-[#f95700]"
            />
          </div>

          {/* ------------------------------------------------------------- */}
          {/* DEPARTMENT SEARCH & SELECTION SECTION WITH JSON AUTO-FILL */}
          {/* ------------------------------------------------------------- */}
          <div className="md:col-span-2 bg-[#090d16] p-4 rounded-xl border border-[#1e2638] space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-[#f95700] flex items-center gap-1.5 uppercase tracking-wider">
                <Building2 className="w-4 h-4" />
                Department & Unit Master Lookup
              </span>
              <span className="text-[11px] text-slate-400 font-mono">
                {DEPARTMENT_UNIT_LIST.length} Master Departments
              </span>
            </div>

            {/* Department Search Input Box */}
            <div className="relative" ref={dropdownRef}>
              <label className="block text-xs font-semibold text-slate-300 mb-1">
                Search Department (Type to search department name or ID)
              </label>
              <div className="relative">
                <Search className="w-4 h-4 text-slate-500 absolute left-3 top-2.5" />
                <input
                  type="text"
                  placeholder="Search department (e.g. ACCOUNT, STORE, TIME, 100...)"
                  value={departmentSearch}
                  onFocus={() => setShowDeptDropdown(true)}
                  onChange={(e) => {
                    setDepartmentSearch(e.target.value);
                    setDepartmentName(e.target.value);
                    setShowDeptDropdown(true);
                  }}
                  className="w-full bg-[#111622] border border-[#242f48] rounded-xl pl-9 pr-8 py-2 text-xs font-medium text-white placeholder-slate-500 focus:outline-none focus:border-[#f95700]"
                />
                {departmentSearch && (
                  <button
                    type="button"
                    onClick={() => {
                      setDepartmentSearch('');
                      setDepartmentName('');
                      setDepartmentId('');
                    }}
                    className="absolute right-2.5 top-2.5 text-slate-500 hover:text-white"
                  >
                    <X className="w-3.5 h-3.5" />
                  </button>
                )}
              </div>

              {/* Department Dropdown Search Results */}
              {showDeptDropdown && filteredDepts.length > 0 && (
                <div className="absolute z-50 left-0 right-0 mt-1 max-h-48 overflow-y-auto bg-[#111622] border border-[#242f48] rounded-xl shadow-2xl divide-y divide-[#1e2638]">
                  {filteredDepts.map((item, idx) => (
                    <div
                      key={`${item.department_id}-${item.unit_number}-${idx}`}
                      onClick={() => handleSelectDepartment(item)}
                      className="p-2.5 hover:bg-[#f95700]/15 cursor-pointer flex items-center justify-between text-xs transition-colors"
                    >
                      <div className="flex items-center gap-2">
                        <Building2 className="w-3.5 h-3.5 text-[#f95700]" />
                        <span className="font-bold text-white">{item.department_name}</span>
                      </div>
                      <div className="flex items-center gap-3 text-[11px] font-mono text-slate-400">
                        <span>ID: <strong className="text-amber-400">{item.department_id}</strong></span>
                        <span>Unit: <strong className="text-emerald-400">{item.unit_number}</strong></span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Editable Department Name & Department ID */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
              <div>
                <label className="block text-[11px] font-medium text-slate-400 mb-1">
                  Department Name (Editable)
                </label>
                <input
                  type="text"
                  placeholder="Department Name"
                  value={departmentName}
                  onChange={(e) => {
                    setDepartmentName(e.target.value);
                    setDepartmentSearch(e.target.value);
                  }}
                  className="w-full bg-[#111622] border border-[#242f48] rounded-xl px-3 py-1.5 text-xs text-white focus:outline-none focus:border-[#f95700]"
                />
              </div>

              <div>
                <label className="block text-[11px] font-medium text-slate-400 mb-1">
                  Department ID (Editable)
                </label>
                <input
                  type="number"
                  placeholder="Department ID (e.g. 100)"
                  value={departmentId}
                  onChange={(e) => setDepartmentId(e.target.value)}
                  className="w-full bg-[#111622] border border-[#242f48] rounded-xl px-3 py-1.5 text-xs text-white focus:outline-none focus:border-[#f95700] font-mono"
                />
              </div>
            </div>

            {/* Unit Input Dropdown & Custom Unit */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
              <div>
                <label className="block text-xs font-semibold text-slate-300 mb-1 flex items-center gap-1">
                  <Layers className="w-3.5 h-3.5 text-emerald-400" />
                  <span>Unit Number Dropdown</span>
                </label>
                <select
                  value={unitNumber}
                  onChange={(e) => setUnitNumber(e.target.value)}
                  className="w-full bg-[#111622] border border-[#242f48] rounded-xl px-3 py-1.5 text-xs font-mono text-white focus:outline-none focus:border-[#f95700]"
                >
                  {uniqueUnits.map((u) => (
                    <option key={u} value={u}>
                      Unit {u}
                    </option>
                  ))}
                  {!uniqueUnits.includes(Number(unitNumber)) && unitNumber && (
                    <option value={unitNumber}>Unit {unitNumber} (Custom)</option>
                  )}
                </select>
              </div>

              <div>
                <label className="block text-[11px] font-medium text-slate-400 mb-1">
                  Unit Number (Editable Direct Input)
                </label>
                <input
                  type="number"
                  placeholder="Unit Number"
                  value={unitNumber}
                  onChange={(e) => setUnitNumber(e.target.value)}
                  className="w-full bg-[#111622] border border-[#242f48] rounded-xl px-3 py-1.5 text-xs text-white focus:outline-none focus:border-[#f95700] font-mono"
                />
              </div>
            </div>
          </div>

          {/* Designation */}
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1 flex items-center gap-1">
              <Briefcase className="w-3.5 h-3.5 text-slate-400" />
              <span>Designation</span>
            </label>
            <input
              type="text"
              placeholder="e.g. Senior Operator / Manager"
              value={designation}
              onChange={(e) => setDesignation(e.target.value)}
              className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-xs font-medium text-white placeholder-slate-500 focus:outline-none focus:border-[#f95700]"
            />
          </div>

          {/* Active status */}
          <div className="flex items-center justify-between bg-[#0c1018] border border-[#242f48] rounded-xl px-4 py-2 mt-auto">
            <div>
              <span className="text-xs font-semibold text-white block">Account Status</span>
              <span className="text-[10px] text-slate-400 block">Enable or suspend attendance access</span>
            </div>
            <label className="relative inline-flex items-center cursor-pointer">
              <input
                type="checkbox"
                checked={isActive}
                onChange={(e) => setIsActive(e.target.checked)}
                className="sr-only peer"
              />
              <div className="w-9 h-5 bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-emerald-500"></div>
            </label>
          </div>
        </div>

        {/* Buttons */}
        <div className="flex items-center justify-end gap-3 pt-3 border-t border-[#1e2638]">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 rounded-xl text-xs font-semibold bg-slate-800 text-slate-300 hover:bg-slate-700 border border-slate-700 transition-colors"
          >
            Cancel
          </button>

          <button
            type="submit"
            disabled={loading}
            className="flex items-center gap-2 px-5 py-2 rounded-xl text-xs font-semibold bg-[#f95700] hover:bg-[#e04e00] text-white shadow-md transition-colors disabled:opacity-50"
          >
            {loading ? (
              <div className="w-3.5 h-3.5 border-2 border-white border-t-transparent rounded-full animate-spin" />
            ) : (
              <Check className="w-4 h-4" />
            )}
            <span>{isEdit ? 'Update User' : 'Create User'}</span>
          </button>
        </div>
      </form>
    </Modal>
  );
};
