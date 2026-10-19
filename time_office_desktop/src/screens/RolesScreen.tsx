import React, { useState, useEffect } from 'react';
import { api } from '../services/api';
import { RoleMaster } from '../types';
import { Modal } from '../components/common/Modal';
import { 
  ShieldCheck, 
  ShieldAlert, 
  UserCheck, 
  Users, 
  Plus, 
  Edit3, 
  Trash2, 
  Search, 
  CheckCircle2, 
  AlertCircle,
  KeyRound,
  Sliders,
  Check,
  UserPlus
} from 'lucide-react';

const MODULE_PERMISSIONS = [
  { id: 'attendance', label: 'Attendance Monitoring', desc: 'View and audit real-time employee attendance stream' },
  { id: 'requests', label: 'Attendance Requests', desc: 'Approve or reject fallback punch requests' },
  { id: 'reports', label: 'Reports & Analytics', desc: 'Generate and export attendance rollup reports' },
  { id: 'shifts', label: 'Shift Rule Management', desc: 'Create and configure dynamic shift punch periods' },
  { id: 'departments', label: 'Department Master', desc: 'Manage organizational departments and assignments' },
  { id: 'roles', label: 'Role & Access Control', desc: 'Create and edit master roles and admin privileges' },
  { id: 'settings', label: 'System Settings', desc: 'Configure biometric thresholds and network failover' },
];

export const RolesScreen: React.FC = () => {
  const [roles, setRoles] = useState<RoleMaster[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [filterType, setFilterType] = useState<'ALL' | 'ADMIN' | 'STANDARD'>('ALL');

  // Modal States
  const [isModalOpen, setIsModalOpen] = useState<boolean>(false);
  const [editingRole, setEditingRole] = useState<RoleMaster | null>(null);

  // Form Fields
  const [roleCode, setRoleCode] = useState<string>('');
  const [roleName, setRoleName] = useState<string>('');
  const [description, setDescription] = useState<string>('');
  const [isAdminRole, setIsAdminRole] = useState<boolean>(false);
  const [selectedPermissions, setSelectedPermissions] = useState<string[]>(['attendance', 'reports']);
  const [isActive, setIsActive] = useState<boolean>(true);
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(null);

  // Quick Assign User Modal State
  const [assignModalRole, setAssignModalRole] = useState<RoleMaster | null>(null);
  const [assignEmployees, setAssignEmployees] = useState<any[]>([]);
  const [selectedUserId, setSelectedUserId] = useState<string>('');

  const loadRoles = async () => {
    setLoading(true);
    try {
      const data = await api.getRoles();
      setRoles(data);
    } catch (err: any) {
      console.error('[RolesScreen] Error loading master roles:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadRoles();
  }, []);

  const openCreateModal = () => {
    setEditingRole(null);
    setRoleCode('');
    setRoleName('');
    setDescription('');
    setIsAdminRole(false);
    setSelectedPermissions(['attendance', 'reports']);
    setIsActive(true);
    setFeedback(null);
    setIsModalOpen(true);
  };

  const openEditModal = (role: RoleMaster) => {
    setEditingRole(role);
    setRoleCode(role.role_code);
    setRoleName(role.role_name);
    setDescription(role.description || '');
    setIsAdminRole(role.is_admin);
    setSelectedPermissions(role.permissions ? role.permissions.split(',') : ['attendance']);
    setIsActive(role.is_active);
    setFeedback(null);
    setIsModalOpen(true);
  };

  const togglePermission = (permId: string) => {
    if (selectedPermissions.includes(permId)) {
      setSelectedPermissions(selectedPermissions.filter((p) => p !== permId));
    } else {
      setSelectedPermissions([...selectedPermissions, permId]);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!roleName.trim()) {
      setFeedback({ type: 'error', message: 'Role Name is required.' });
      return;
    }
    if (!editingRole && !roleCode.trim()) {
      setFeedback({ type: 'error', message: 'Role Code is required.' });
      return;
    }

    setIsSubmitting(true);
    setFeedback(null);

    const permissionsStr = selectedPermissions.join(',');

    try {
      if (editingRole) {
        await api.updateRole(editingRole.id, {
          role_name: roleName.trim(),
          description: description.trim(),
          is_admin: isAdminRole,
          permissions: permissionsStr,
          is_active: isActive,
        });
        setFeedback({ type: 'success', message: `Role '${roleName}' updated successfully.` });
      } else {
        await api.createRole({
          role_code: roleCode.trim(),
          role_name: roleName.trim(),
          description: description.trim(),
          is_admin: isAdminRole,
          permissions: permissionsStr,
          is_active: isActive,
        });
        setFeedback({ type: 'success', message: `Master Role '${roleName}' created successfully.` });
      }

      await loadRoles();
      setTimeout(() => {
        setIsModalOpen(false);
      }, 1200);
    } catch (err: any) {
      setFeedback({
        type: 'error',
        message: err.response?.data?.detail || err.message || 'Failed to save role.',
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDelete = async (role: RoleMaster) => {
    if (role.is_system_role) {
      alert(`System Role '${role.role_code}' is built-in and cannot be deleted.`);
      return;
    }
    if (role.assigned_users_count > 0) {
      alert(`Role '${role.role_name}' is currently assigned to ${role.assigned_users_count} user(s). Please reassign them first.`);
      return;
    }

    if (!window.confirm(`Are you sure you want to delete custom role '${role.role_name}'?`)) return;

    try {
      await api.deleteRole(role.id);
      await loadRoles();
    } catch (err: any) {
      alert(err.response?.data?.detail || err.message || 'Failed to delete role.');
    }
  };

  const openAssignModal = async (role: RoleMaster) => {
    setAssignModalRole(role);
    setSelectedUserId('');
    try {
      const { records } = await api.getEmployees();
      setAssignEmployees(records);
    } catch (err) {
      console.error(err);
    }
  };

  const handleAssignSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!assignModalRole || !selectedUserId) return;
    try {
      await api.assignUserRole(Number(selectedUserId), assignModalRole.role_code);
      alert(`Role '${assignModalRole.role_code}' assigned successfully!`);
      setAssignModalRole(null);
      await loadRoles();
    } catch (err: any) {
      alert(err.response?.data?.detail || err.message || 'Failed to assign role.');
    }
  };

  // Filtered Roles List
  const filteredRoles = roles.filter((r) => {
    const matchesSearch =
      r.role_name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      r.role_code.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (r.description && r.description.toLowerCase().includes(searchQuery.toLowerCase()));

    if (filterType === 'ADMIN') return matchesSearch && r.is_admin;
    if (filterType === 'STANDARD') return matchesSearch && !r.is_admin;
    return matchesSearch;
  });

  const totalRoles = roles.length;
  const adminRolesCount = roles.filter((r) => r.is_admin).length;
  const standardRolesCount = roles.filter((r) => !r.is_admin).length;
  const totalAssignedUsers = roles.reduce((sum, r) => sum + r.assigned_users_count, 0);

  return (
    <div className="space-y-5 animate-in fade-in duration-150">
      {/* Top Header Card */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-white p-5 rounded-xl border border-slate-200/90 shadow-sm">
        <div>
          <h2 className="text-xl font-bold tracking-tight text-slate-900 flex items-center gap-2">
            <KeyRound className="w-5 h-5 text-brand-600" />
            <span>ROLE & PERMISSIONS MASTER</span>
          </h2>
          <p className="text-xs text-slate-500 mt-0.5">
            Configure administrative supervisor privileges, custom user roles, and module access permissions
          </p>
        </div>

        <button
          onClick={openCreateModal}
          className="flex items-center gap-2 px-4 py-2.5 bg-brand-600 hover:bg-brand-500 active:bg-brand-700 text-white font-bold text-xs rounded-xl shadow-sm transition-all"
        >
          <Plus className="w-4 h-4" />
          <span>Add New Master Role</span>
        </button>
      </div>

      {/* KPI Stats Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3.5">
        <div className="bg-white border border-slate-200 p-4 rounded-xl shadow-sm">
          <div className="flex items-center justify-between text-slate-500 mb-1">
            <span className="text-xs font-bold uppercase tracking-wider text-slate-600">Total Configured Roles</span>
            <KeyRound className="w-4 h-4 text-brand-500" />
          </div>
          <div className="text-2xl font-bold font-mono text-slate-900">{totalRoles}</div>
          <div className="text-[11px] text-slate-500 mt-1">Active Master System Roles</div>
        </div>

        <div className="bg-white border border-orange-200 p-4 rounded-xl shadow-sm">
          <div className="flex items-center justify-between text-brand-600 mb-1">
            <span className="text-xs font-bold uppercase tracking-wider text-brand-700">Supervisor / Admin Roles</span>
            <ShieldCheck className="w-4 h-4 text-brand-600" />
          </div>
          <div className="text-2xl font-bold font-mono text-brand-600">{adminRolesCount}</div>
          <div className="text-[11px] text-slate-500 mt-1">With Management Privileges</div>
        </div>

        <div className="bg-white border border-blue-200 p-4 rounded-xl shadow-sm">
          <div className="flex items-center justify-between text-blue-600 mb-1">
            <span className="text-xs font-bold uppercase tracking-wider text-blue-700">Standard User Roles</span>
            <Users className="w-4 h-4 text-blue-600" />
          </div>
          <div className="text-2xl font-bold font-mono text-blue-600">{standardRolesCount}</div>
          <div className="text-[11px] text-slate-500 mt-1">Field Staff & Mobile App</div>
        </div>

        <div className="bg-white border border-emerald-200 p-4 rounded-xl shadow-sm">
          <div className="flex items-center justify-between text-emerald-600 mb-1">
            <span className="text-xs font-bold uppercase tracking-wider text-emerald-700">Assigned Employees</span>
            <UserCheck className="w-4 h-4 text-emerald-600" />
          </div>
          <div className="text-2xl font-bold font-mono text-emerald-600">{totalAssignedUsers}</div>
          <div className="text-[11px] text-slate-500 mt-1">Across all role definitions</div>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div className="bg-white border border-slate-200/90 rounded-xl p-4 flex flex-col md:flex-row md:items-center justify-between gap-3 shadow-sm">
        <div className="relative flex-1 max-w-md">
          <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search role code, name, description..."
            className="w-full bg-slate-50 border border-slate-300 rounded-lg pl-9 pr-3 py-2 text-xs text-slate-900 focus:outline-none focus:border-brand-500 shadow-xs"
          />
        </div>

        <div className="flex items-center gap-2 text-xs">
          <span className="text-slate-500 font-semibold uppercase tracking-wider text-[11px]">Role Filter:</span>
          <button
            onClick={() => setFilterType('ALL')}
            className={`px-3 py-1.5 rounded-lg font-bold transition-colors ${
              filterType === 'ALL'
                ? 'bg-slate-900 text-white'
                : 'bg-slate-100 text-slate-700 hover:bg-slate-200'
            }`}
          >
            All Roles ({roles.length})
          </button>
          <button
            onClick={() => setFilterType('ADMIN')}
            className={`px-3 py-1.5 rounded-lg font-bold transition-colors ${
              filterType === 'ADMIN'
                ? 'bg-brand-600 text-white'
                : 'bg-slate-100 text-slate-700 hover:bg-slate-200'
            }`}
          >
            Supervisor / Admin ({adminRolesCount})
          </button>
          <button
            onClick={() => setFilterType('STANDARD')}
            className={`px-3 py-1.5 rounded-lg font-bold transition-colors ${
              filterType === 'STANDARD'
                ? 'bg-blue-600 text-white'
                : 'bg-slate-100 text-slate-700 hover:bg-slate-200'
            }`}
          >
            Standard User ({standardRolesCount})
          </button>
        </div>
      </div>

      {/* Main Roles Table */}
      <div className="bg-white border border-slate-200/90 rounded-xl overflow-hidden shadow-sm">
        <div className="overflow-x-auto">
          <table className="w-full text-left table-dense">
            <thead>
              <tr>
                <th>Role Code</th>
                <th>Role Name</th>
                <th>Privilege Level</th>
                <th>Granted Module Permissions</th>
                <th>Assigned Users</th>
                <th>Role Type</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={8} className="text-center py-10 text-slate-400 text-xs">
                    <div className="w-6 h-6 border-2 border-brand-500 border-t-transparent rounded-full animate-spin mx-auto mb-2" />
                    Loading Master Roles...
                  </td>
                </tr>
              ) : filteredRoles.length === 0 ? (
                <tr>
                  <td colSpan={8} className="text-center py-10 text-slate-400 text-xs">
                    No master roles matching search query.
                  </td>
                </tr>
              ) : (
                filteredRoles.map((r) => (
                  <tr key={r.id} className="hover:bg-slate-50 transition-colors">
                    {/* Role Code Badge */}
                    <td>
                      <span className="px-2.5 py-1 bg-slate-900 text-white rounded font-mono text-[11px] font-bold tracking-wider inline-block">
                        {r.role_code}
                      </span>
                    </td>

                    {/* Role Name & Description */}
                    <td>
                      <div className="font-bold text-slate-900">{r.role_name}</div>
                      {r.description && <div className="text-[11px] text-slate-500 mt-0.5">{r.description}</div>}
                    </td>

                    {/* Admin Status Privilege */}
                    <td>
                      {r.is_admin ? (
                        <span className="px-2.5 py-0.5 rounded-full bg-orange-100 text-orange-800 border border-orange-300 font-bold text-[10px] uppercase inline-flex items-center gap-1">
                          <ShieldCheck className="w-3 h-3 text-brand-600" />
                          SUPERVISOR / ADMIN
                        </span>
                      ) : (
                        <span className="px-2.5 py-0.5 rounded-full bg-blue-50 text-blue-700 border border-blue-200 font-bold text-[10px] uppercase inline-flex items-center gap-1">
                          <Users className="w-3 h-3 text-blue-600" />
                          STANDARD USER
                        </span>
                      )}
                    </td>

                    {/* Granted Permissions Pills */}
                    <td>
                      <div className="flex flex-wrap gap-1 max-w-xs">
                        {r.permissions ? (
                          r.permissions.split(',').map((p) => (
                            <span key={p} className="px-2 py-0.5 rounded bg-slate-100 border border-slate-300 text-slate-700 text-[10px] font-mono font-bold">
                              {p}
                            </span>
                          ))
                        ) : (
                          <span className="text-slate-400 text-[11px]">None</span>
                        )}
                      </div>
                    </td>

                    {/* Assigned Users Count */}
                    <td>
                      <div className="flex items-center gap-2">
                        <span className="font-mono font-bold text-slate-900 text-sm">{r.assigned_users_count}</span>
                        <span className="text-[11px] text-slate-500">Users</span>
                        <button
                          onClick={() => openAssignModal(r)}
                          className="p-1 rounded bg-slate-100 hover:bg-slate-200 text-brand-600 transition-colors ml-1"
                          title="Assign this role to a user"
                        >
                          <UserPlus className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </td>

                    {/* Role Type */}
                    <td>
                      {r.is_system_role ? (
                        <span className="px-2 py-0.5 rounded bg-slate-200 text-slate-700 text-[10px] font-mono font-bold">
                          SYSTEM DEFAULT
                        </span>
                      ) : (
                        <span className="px-2 py-0.5 rounded bg-emerald-50 text-emerald-700 border border-emerald-200 text-[10px] font-mono font-bold">
                          CUSTOM
                        </span>
                      )}
                    </td>

                    {/* Active Status */}
                    <td>
                      {r.is_active ? (
                        <span className="text-[11px] text-emerald-700 font-bold flex items-center gap-1">
                          <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
                          Active
                        </span>
                      ) : (
                        <span className="text-[11px] text-slate-400 font-semibold">Disabled</span>
                      )}
                    </td>

                    {/* Actions */}
                    <td>
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => openEditModal(r)}
                          className="px-2.5 py-1 rounded bg-slate-100 hover:bg-slate-200 text-slate-800 font-semibold text-xs border border-slate-300 transition-colors flex items-center gap-1"
                        >
                          <Edit3 className="w-3.5 h-3.5 text-brand-600" />
                          Edit
                        </button>
                        {!r.is_system_role && (
                          <button
                            onClick={() => handleDelete(r)}
                            disabled={r.assigned_users_count > 0}
                            className="p-1.5 rounded bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200 disabled:opacity-40 transition-colors"
                            title={r.assigned_users_count > 0 ? "Cannot delete assigned role" : "Delete custom role"}
                          >
                            <Trash2 className="w-3.5 h-3.5" />
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Add / Edit Master Role Modal */}
      {isModalOpen && (
        <Modal
          isOpen={isModalOpen}
          onClose={() => setIsModalOpen(false)}
          title={editingRole ? `Edit Master Role: ${editingRole.role_code}` : 'Create New Master Role'}
          subtitle="Define supervisor privileges, role code, and module permission access"
          maxWidth="max-w-xl"
        >
          <form onSubmit={handleSubmit} className="space-y-4 text-xs">
            {feedback && (
              <div
                className={`p-3 rounded-lg border flex items-start gap-2 ${
                  feedback.type === 'success'
                    ? 'bg-emerald-50 border-emerald-200 text-emerald-800'
                    : 'bg-rose-50 border-rose-200 text-rose-800'
                }`}
              >
                {feedback.type === 'success' ? (
                  <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0 mt-0.5" />
                ) : (
                  <AlertCircle className="w-4 h-4 text-rose-600 shrink-0 mt-0.5" />
                )}
                <span className="font-semibold">{feedback.message}</span>
              </div>
            )}

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-slate-700 font-bold mb-1 uppercase tracking-wider text-[10px]">
                  Role Code (Unique Key) *
                </label>
                <input
                  type="text"
                  required
                  disabled={!!editingRole}
                  value={roleCode}
                  onChange={(e) => setRoleCode(e.target.value)}
                  placeholder="e.g. SUPERVISOR, FIELD_ADMIN"
                  className="w-full bg-white border border-slate-300 rounded-lg px-3 py-2 text-slate-900 font-mono text-xs focus:outline-none focus:border-brand-500 disabled:bg-slate-100 shadow-xs"
                />
              </div>

              <div>
                <label className="block text-slate-700 font-bold mb-1 uppercase tracking-wider text-[10px]">
                  Role Display Name *
                </label>
                <input
                  type="text"
                  required
                  value={roleName}
                  onChange={(e) => setRoleName(e.target.value)}
                  placeholder="e.g. Zone Supervisor"
                  className="w-full bg-white border border-slate-300 rounded-lg px-3 py-2 text-slate-900 text-xs focus:outline-none focus:border-brand-500 shadow-xs"
                />
              </div>
            </div>

            <div>
              <label className="block text-slate-700 font-bold mb-1 uppercase tracking-wider text-[10px]">
                Role Description
              </label>
              <textarea
                rows={2}
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Describe role responsibilities and operational supervisor scope..."
                className="w-full bg-white border border-slate-300 rounded-lg p-2.5 text-slate-900 text-xs focus:outline-none focus:border-brand-500 shadow-xs"
              />
            </div>

            {/* Grant Admin / Supervisor Privilege Toggle (Key User Requirement) */}
            <div className="bg-orange-50/70 border border-orange-200 p-3.5 rounded-xl space-y-2">
              <label className="flex items-center justify-between cursor-pointer">
                <div className="flex items-center gap-2.5">
                  <ShieldCheck className="w-5 h-5 text-brand-600" />
                  <div>
                    <span className="font-bold text-slate-900 text-xs block">Grant Admin / Supervisor Privileges</span>
                    <span className="text-[11px] text-slate-600 block">
                      Enables supervisor access to management endpoints, shift controls, and fallback request approvals.
                    </span>
                  </div>
                </div>
                <input
                  type="checkbox"
                  checked={isAdminRole}
                  onChange={(e) => setIsAdminRole(e.target.checked)}
                  className="w-5 h-5 accent-brand-600 rounded cursor-pointer"
                />
              </label>
            </div>

            {/* Granular Permissions Selection */}
            <div>
              <label className="block text-slate-700 font-bold mb-1.5 uppercase tracking-wider text-[10px]">
                Module Access Permissions
              </label>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-2 max-h-48 overflow-y-auto p-1">
                {MODULE_PERMISSIONS.map((perm) => {
                  const isChecked = selectedPermissions.includes(perm.id);
                  return (
                    <div
                      key={perm.id}
                      onClick={() => togglePermission(perm.id)}
                      className={`p-2.5 rounded-lg border cursor-pointer transition-colors flex items-start gap-2.5 ${
                        isChecked
                          ? 'bg-slate-900 text-white border-slate-900'
                          : 'bg-white text-slate-700 border-slate-200 hover:border-slate-300'
                      }`}
                    >
                      <div className={`w-4 h-4 rounded border mt-0.5 flex items-center justify-center shrink-0 ${
                        isChecked ? 'bg-brand-500 border-brand-500 text-white' : 'border-slate-300 bg-slate-50'
                      }`}>
                        {isChecked && <Check className="w-3 h-3 stroke-[3]" />}
                      </div>
                      <div>
                        <div className="font-bold text-xs">{perm.label}</div>
                        <div className={`text-[10px] ${isChecked ? 'text-slate-300' : 'text-slate-500'}`}>{perm.desc}</div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Status Toggle */}
            <div className="flex items-center justify-between pt-2 border-t border-slate-200">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={isActive}
                  onChange={(e) => setIsActive(e.target.checked)}
                  className="w-4 h-4 accent-brand-600 rounded"
                />
                <span className="font-bold text-slate-800 text-xs">Role is Active</span>
              </label>

              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  className="px-4 py-2 rounded-lg bg-slate-100 hover:bg-slate-200 text-slate-700 font-semibold text-xs"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="px-5 py-2 rounded-lg bg-brand-600 hover:bg-brand-500 active:bg-brand-700 text-white font-bold text-xs shadow-sm transition-all disabled:opacity-50"
                >
                  {isSubmitting ? 'Saving...' : editingRole ? 'Update Role' : 'Create Role'}
                </button>
              </div>
            </div>
          </form>
        </Modal>
      )}

      {/* Quick Assign User Role Modal */}
      {assignModalRole && (
        <Modal
          isOpen={!!assignModalRole}
          onClose={() => setAssignModalRole(null)}
          title={`Assign Role: ${assignModalRole.role_name}`}
          subtitle={`Set employee / supervisor role code to '${assignModalRole.role_code}'`}
          maxWidth="max-w-md"
        >
          <form onSubmit={handleAssignSubmit} className="space-y-4 text-xs">
            <div>
              <label className="block text-slate-700 font-bold mb-1 uppercase tracking-wider text-[10px]">
                Select Employee / Supervisor *
              </label>
              <select
                required
                value={selectedUserId}
                onChange={(e) => setSelectedUserId(e.target.value)}
                className="w-full bg-white border border-slate-300 rounded-lg px-3 py-2 text-slate-900 text-xs focus:outline-none focus:border-brand-500 shadow-xs"
              >
                <option value="">-- Choose User --</option>
                {assignEmployees.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.full_name} ({u.employee_id}) — Current Role: {u.role}
                  </option>
                ))}
              </select>
            </div>

            <div className="flex items-center justify-end gap-2 pt-2 border-t border-slate-200">
              <button
                type="button"
                onClick={() => setAssignModalRole(null)}
                className="px-4 py-2 rounded-lg bg-slate-100 hover:bg-slate-200 text-slate-700 font-semibold text-xs"
              >
                Cancel
              </button>
              <button
                type="submit"
                className="px-4 py-2 rounded-lg bg-brand-600 hover:bg-brand-500 text-white font-bold text-xs shadow-sm"
              >
                Assign Role
              </button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
};
