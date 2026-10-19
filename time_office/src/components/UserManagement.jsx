import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { 
  Users, UserPlus, RefreshCw, KeyRound, ShieldAlert, 
  Trash2, Power, CheckCircle2, AlertTriangle, Clock, X, Plus, ShieldCheck, Lock
} from 'lucide-react';
import { API_BASE } from '../api/client';
import { useAuth } from '../context/AuthContext';

export default function UserManagement() {
  const { currentUser } = useAuth();
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  // Single User Modal
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [singleUserForm, setSingleUserForm] = useState({
    username: '',
    full_name: '',
    role: 'clerk',
    password: ''
  });
  const [savingSingle, setSavingSingle] = useState(false);

  // Batch / Multiple Users Modal
  const [isBatchModalOpen, setIsBatchModalOpen] = useState(false);
  const [batchUsers, setBatchUsers] = useState([
    { username: '', full_name: '', role: 'clerk', password: '' },
    { username: '', full_name: '', role: 'clerk', password: '' }
  ]);
  const [savingBatch, setSavingBatch] = useState(false);

  // Admin Reset Password Modal
  const [resetModalUser, setResetModalUser] = useState(null);
  const [newPasswordInput, setNewPasswordInput] = useState('');
  const [confirmPasswordInput, setConfirmPasswordInput] = useState('');
  const [savingReset, setSavingReset] = useState(false);

  const fetchUsers = async () => {
    setLoading(true);
    try {
      const res = await axios.get(`${API_BASE}/auth/users`);
      setUsers(res.data || []);
    } catch (err) {
      console.error('Failed to load users:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchUsers();
  }, []);

  const handleCreateSingleUser = async (e) => {
    e.preventDefault();
    if (!singleUserForm.username.trim() || !singleUserForm.password.trim()) {
      setError('Username and password are required.');
      return;
    }
    setSavingSingle(true);
    setError('');
    setMessage('');

    try {
      await axios.post(`${API_BASE}/auth/users`, singleUserForm);
      setMessage(`User '@${singleUserForm.username}' created successfully.`);
      setIsAddModalOpen(false);
      setSingleUserForm({ username: '', full_name: '', role: 'clerk', password: '' });
      fetchUsers();
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to create user.');
    } finally {
      setSavingSingle(false);
    }
  };

  const handleAddBatchRow = () => {
    setBatchUsers([...batchUsers, { username: '', full_name: '', role: 'clerk', password: '' }]);
  };

  const handleRemoveBatchRow = (index) => {
    if (batchUsers.length <= 1) return;
    setBatchUsers(batchUsers.filter((_, i) => i !== index));
  };

  const handleBatchChange = (index, field, value) => {
    const updated = [...batchUsers];
    updated[index][field] = value;
    setBatchUsers(updated);
  };

  const handleCreateBatchUsers = async (e) => {
    e.preventDefault();
    const validRows = batchUsers.filter(u => u.username.trim() && u.password.trim());
    if (validRows.length === 0) {
      setError('Please fill in at least one user with username and password.');
      return;
    }

    setSavingBatch(true);
    setError('');
    setMessage('');

    try {
      const res = await axios.post(`${API_BASE}/auth/users/batch`, validRows);
      setMessage(`Batch completed: Created ${res.data.created_count} users!`);
      if (res.data.skipped && res.data.skipped.length > 0) {
        alert('Skipped existing accounts: ' + res.data.skipped.join(', '));
      }
      setIsBatchModalOpen(false);
      setBatchUsers([
        { username: '', full_name: '', role: 'clerk', password: '' },
        { username: '', full_name: '', role: 'clerk', password: '' }
      ]);
      fetchUsers();
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to create batch users.');
    } finally {
      setSavingBatch(false);
    }
  };

  const handleResetPassword = async (e) => {
    e.preventDefault();
    if (newPasswordInput.length < 4) {
      setError('Password must be at least 4 characters.');
      return;
    }
    if (newPasswordInput !== confirmPasswordInput) {
      setError('Passwords do not match.');
      return;
    }

    setSavingReset(true);
    setError('');
    setMessage('');

    try {
      await axios.post(`${API_BASE}/auth/users/${resetModalUser.id}/reset-password`, {
        new_password: newPasswordInput
      });
      setMessage(`Password for @${resetModalUser.username} updated! 15-day reset timer renewed.`);
      setResetModalUser(null);
      setNewPasswordInput('');
      setConfirmPasswordInput('');
      fetchUsers();
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to reset password.');
    } finally {
      setSavingReset(false);
    }
  };

  const handleForceReset = async (user) => {
    if (!window.confirm(`Force @${user.username} to reset password on their next login?`)) return;
    try {
      await axios.post(`${API_BASE}/auth/users/${user.id}/force-reset`);
      setMessage(`User @${user.username} will be required to change password on next sign-in.`);
      fetchUsers();
    } catch (err) {
      alert('Failed: ' + (err.response?.data?.detail || err.message));
    }
  };

  const handleToggleStatus = async (user) => {
    try {
      await axios.put(`${API_BASE}/auth/users/${user.id}`, {
        is_active: !user.is_active
      });
      fetchUsers();
    } catch (err) {
      alert('Status update failed: ' + (err.response?.data?.detail || err.message));
    }
  };

  const handleDeleteUser = async (user) => {
    if (!window.confirm(`Are you sure you want to delete user account '@${user.username}'?`)) return;
    try {
      await axios.delete(`${API_BASE}/auth/users/${user.id}`);
      setMessage(`User @${user.username} deleted.`);
      fetchUsers();
    } catch (err) {
      alert('Delete failed: ' + (err.response?.data?.detail || err.message));
    }
  };

  return (
    <div className="space-y-6">
      {/* Policy Information Banner */}
      <div className="bg-gradient-to-r from-orange-50 via-amber-50 to-orange-50 border border-orange-200/80 rounded-2xl p-5 flex flex-col md:flex-row items-start md:items-center justify-between gap-4 shadow-xs">
        <div className="flex items-start gap-3.5">
          <div className="p-2.5 rounded-xl bg-orange-600 text-white shrink-0 mt-0.5">
            <Clock size={20} />
          </div>
          <div>
            <h3 className="text-sm font-bold text-slate-900">
              15-Day Mandatory Password Reset Security Policy
            </h3>
            <p className="text-xs text-slate-600 mt-1 leading-relaxed">
              Every system user (Admin and Clerk) is required to update their credentials every <span className="font-bold text-orange-700">15 days</span>.
              Accounts with expired passwords will be prompted to set a new password upon login. Admin can manually reset or force password changes at any time.
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2 self-end md:self-auto shrink-0">
          <button
            type="button"
            onClick={() => {
              setError('');
              setMessage('');
              setIsAddModalOpen(true);
            }}
            className="flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold text-white bg-orange-600 hover:bg-orange-700 rounded-xl shadow-xs transition-colors cursor-pointer"
          >
            <UserPlus size={15} />
            + Add Single User
          </button>
          <button
            type="button"
            onClick={() => {
              setError('');
              setMessage('');
              setIsBatchModalOpen(true);
            }}
            className="flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold text-brand-800 bg-brand-50 hover:bg-brand-100 border border-brand-200 rounded-xl shadow-xs transition-colors cursor-pointer"
          >
            <Users size={15} />
            ⚡ Add Multiple Users
          </button>
        </div>
      </div>

      {message && (
        <div className="bg-emerald-50 border border-emerald-200 rounded-xl p-3.5 flex items-center gap-2 text-emerald-800 text-xs font-semibold animate-in fade-in">
          <CheckCircle2 size={16} className="text-emerald-600 shrink-0" />
          {message}
        </div>
      )}

      {error && (
        <div className="bg-rose-50 border border-rose-200 rounded-xl p-3.5 flex items-center gap-2 text-rose-800 text-xs font-semibold animate-in fade-in">
          <AlertTriangle size={16} className="text-rose-600 shrink-0" />
          {error}
        </div>
      )}

      {/* Users Table */}
      <div className="bg-white rounded-2xl border border-slate-200 shadow-xs overflow-hidden">
        <div className="p-4 border-b border-slate-100 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <h3 className="font-bold text-slate-900 text-sm">System Users & Security Credentials</h3>
            <span className="px-2 py-0.5 rounded-full text-[11px] font-bold bg-slate-100 text-slate-700">
              {users.length} Total
            </span>
          </div>

          <button
            type="button"
            onClick={fetchUsers}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-slate-700 bg-slate-50 hover:bg-slate-100 border border-slate-200 rounded-lg transition-colors cursor-pointer"
          >
            <RefreshCw size={13} className={loading ? 'animate-spin' : ''} />
            Refresh
          </button>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs border-collapse">
            <thead>
              <tr className="bg-slate-50 border-b border-slate-200 text-slate-500 font-bold uppercase tracking-wider">
                <th className="p-3.5">USER</th>
                <th className="p-3.5">ROLE</th>
                <th className="p-3.5">STATUS</th>
                <th className="p-3.5">PASSWORD AGE / EXPIRY (15 DAYS)</th>
                <th className="p-3.5 text-right">ACTIONS</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 font-medium">
              {loading ? (
                <tr>
                  <td colSpan="5" className="p-8 text-center text-slate-400">Loading user accounts...</td>
                </tr>
              ) : users.length === 0 ? (
                <tr>
                  <td colSpan="5" className="p-8 text-center text-slate-400">No users found.</td>
                </tr>
              ) : (
                users.map((u) => {
                  const daysLeft = u.days_until_expiration;
                  const isExpired = u.is_password_expired;
                  const mustReset = u.must_reset_password;

                  return (
                    <tr key={u.id} className="hover:bg-slate-50/70 transition-colors">
                      <td className="p-3.5">
                        <div className="flex items-center gap-2.5">
                          <div className={`w-8 h-8 rounded-xl flex items-center justify-center font-bold text-xs ${
                            u.role === 'admin' 
                              ? 'bg-orange-100 text-orange-700' 
                              : 'bg-emerald-100 text-emerald-700'
                          }`}>
                            {u.role === 'admin' ? <ShieldCheck size={16} /> : <Users size={16} />}
                          </div>
                          <div>
                            <div className="font-bold text-slate-900">{u.full_name || u.username}</div>
                            <div className="text-[11px] font-mono text-slate-400">@{u.username}</div>
                          </div>
                        </div>
                      </td>

                      <td className="p-3.5">
                        <span className={`inline-flex px-2 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wider border ${
                          u.role === 'admin'
                            ? 'bg-orange-50 text-orange-700 border-orange-200'
                            : 'bg-emerald-50 text-emerald-700 border-emerald-200'
                        }`}>
                          {u.role}
                        </span>
                      </td>

                      <td className="p-3.5">
                        <span className={`inline-flex px-2 py-0.5 rounded-full text-[10px] font-bold border ${
                          u.is_active
                            ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
                            : 'bg-slate-100 text-slate-500 border-slate-200'
                        }`}>
                          {u.is_active ? 'Active' : 'Deactivated'}
                        </span>
                      </td>

                      <td className="p-3.5">
                        <div className="space-y-1">
                          {isExpired ? (
                            <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-rose-50 text-rose-700 border border-rose-200">
                              <AlertTriangle size={12} />
                              EXPIRED — Reset Required on Login
                            </span>
                          ) : mustReset ? (
                            <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-amber-50 text-amber-700 border border-amber-200">
                              <ShieldAlert size={12} />
                              Forced Reset Scheduled
                            </span>
                          ) : (
                            <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                              <CheckCircle2 size={12} />
                              Expires in {daysLeft} {daysLeft === 1 ? 'day' : 'days'}
                            </span>
                          )}
                          <p className="text-[10px] text-slate-400">
                            Last changed: {u.password_updated_at ? new Date(u.password_updated_at).toLocaleDateString() : 'Initial Setup'}
                          </p>
                        </div>
                      </td>

                      <td className="p-3.5 text-right">
                        <div className="inline-flex items-center gap-1.5">
                          <button
                            type="button"
                            onClick={() => {
                              setResetModalUser(u);
                              setNewPasswordInput('');
                              setConfirmPasswordInput('');
                              setError('');
                            }}
                            title="Reset Password for this user"
                            className="p-1.5 rounded-lg text-slate-500 hover:text-orange-600 hover:bg-orange-50 border border-slate-200 hover:border-orange-200 transition-colors cursor-pointer"
                          >
                            <KeyRound size={14} />
                          </button>

                          <button
                            type="button"
                            onClick={() => handleForceReset(u)}
                            title="Force User to reset password on next login"
                            className="p-1.5 rounded-lg text-slate-500 hover:text-amber-600 hover:bg-amber-50 border border-slate-200 hover:border-amber-200 transition-colors cursor-pointer"
                          >
                            <ShieldAlert size={14} />
                          </button>

                          <button
                            type="button"
                            onClick={() => handleToggleStatus(u)}
                            title={u.is_active ? 'Deactivate account' : 'Activate account'}
                            className={`p-1.5 rounded-lg border border-slate-200 transition-colors cursor-pointer ${
                              u.is_active 
                                ? 'text-slate-500 hover:text-rose-600 hover:bg-rose-50' 
                                : 'text-slate-500 hover:text-emerald-600 hover:bg-emerald-50'
                            }`}
                          >
                            <Power size={14} />
                          </button>

                          {u.username !== 'admin' && (
                            <button
                              type="button"
                              onClick={() => handleDeleteUser(u)}
                              title="Delete user"
                              className="p-1.5 rounded-lg text-slate-400 hover:text-rose-600 hover:bg-rose-50 border border-slate-200 transition-colors cursor-pointer"
                            >
                              <Trash2 size={14} />
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Modal 1: Add Single User */}
      {isAddModalOpen && (
        <div className="fixed inset-0 z-50 bg-black/50 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl shadow-xl border border-slate-200 max-w-md w-full overflow-hidden animate-in zoom-in-95 duration-150">
            <div className="p-5 border-b border-slate-100 flex items-center justify-between bg-slate-50">
              <div className="flex items-center gap-2">
                <UserPlus size={18} className="text-orange-600" />
                <h3 className="font-bold text-slate-900 text-sm">Add New System User</h3>
              </div>
              <button onClick={() => setIsAddModalOpen(false)} className="text-slate-400 hover:text-slate-600 cursor-pointer">
                <X size={16} />
              </button>
            </div>

            <form onSubmit={handleCreateSingleUser} className="p-6 space-y-4 text-xs">
              <div>
                <label className="block font-semibold text-slate-700 mb-1">Username *</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. jdoe"
                  value={singleUserForm.username}
                  onChange={(e) => setSingleUserForm({ ...singleUserForm, username: e.target.value })}
                  className="w-full p-2.5 bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500 font-mono text-xs"
                />
              </div>

              <div>
                <label className="block font-semibold text-slate-700 mb-1">Full Name *</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. John Doe"
                  value={singleUserForm.full_name}
                  onChange={(e) => setSingleUserForm({ ...singleUserForm, full_name: e.target.value })}
                  className="w-full p-2.5 bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500 text-xs"
                />
              </div>

              <div>
                <label className="block font-semibold text-slate-700 mb-1">Assigned Role *</label>
                <select
                  value={singleUserForm.role}
                  onChange={(e) => setSingleUserForm({ ...singleUserForm, role: e.target.value })}
                  className="w-full p-2.5 bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500 font-semibold text-xs"
                >
                  <option value="clerk">Clerk (Leave & Attendance Operations)</option>
                  <option value="admin">Admin (Full System Control & Security)</option>
                </select>
              </div>

              <div>
                <label className="block font-semibold text-slate-700 mb-1">Initial Password *</label>
                <input
                  type="password"
                  required
                  placeholder="Minimum 4 characters"
                  value={singleUserForm.password}
                  onChange={(e) => setSingleUserForm({ ...singleUserForm, password: e.target.value })}
                  className="w-full p-2.5 bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500 font-mono text-xs"
                />
              </div>

              <div className="pt-2 flex justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setIsAddModalOpen(false)}
                  className="px-4 py-2 text-slate-600 hover:bg-slate-100 rounded-lg font-semibold"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={savingSingle}
                  className="px-5 py-2 bg-orange-600 hover:bg-orange-700 text-white rounded-lg font-bold shadow-xs disabled:opacity-50"
                >
                  {savingSingle ? 'Creating...' : 'Create User'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal 2: Add Multiple Users (Batch) */}
      {isBatchModalOpen && (
        <div className="fixed inset-0 z-50 bg-black/50 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl shadow-xl border border-slate-200 max-w-3xl w-full overflow-hidden animate-in zoom-in-95 duration-150">
            <div className="p-5 border-b border-slate-100 flex items-center justify-between bg-slate-50">
              <div className="flex items-center gap-2">
                <Users size={18} className="text-orange-600" />
                <div>
                  <h3 className="font-bold text-slate-900 text-sm">Add Multiple Users (Batch)</h3>
                  <p className="text-[11px] text-slate-500">Quickly create multiple employee/clerk accounts at once</p>
                </div>
              </div>
              <button onClick={() => setIsBatchModalOpen(false)} className="text-slate-400 hover:text-slate-600 cursor-pointer">
                <X size={16} />
              </button>
            </div>

            <form onSubmit={handleCreateBatchUsers} className="p-6 space-y-4 text-xs max-h-[75vh] overflow-y-auto">
              <div className="space-y-3">
                {batchUsers.map((u, idx) => (
                  <div key={idx} className="p-3 bg-slate-50 rounded-xl border border-slate-200 grid grid-cols-1 sm:grid-cols-4 gap-2.5 items-center">
                    <div>
                      <label className="block text-[10px] font-bold text-slate-500 uppercase">Username *</label>
                      <input
                        type="text"
                        required
                        placeholder="e.g. clerk1"
                        value={u.username}
                        onChange={(e) => handleBatchChange(idx, 'username', e.target.value)}
                        className="w-full p-2 bg-white border border-slate-300 rounded-lg font-mono text-xs"
                      />
                    </div>
                    <div>
                      <label className="block text-[10px] font-bold text-slate-500 uppercase">Full Name *</label>
                      <input
                        type="text"
                        required
                        placeholder="e.g. Sarah Connor"
                        value={u.full_name}
                        onChange={(e) => handleBatchChange(idx, 'full_name', e.target.value)}
                        className="w-full p-2 bg-white border border-slate-300 rounded-lg text-xs"
                      />
                    </div>
                    <div>
                      <label className="block text-[10px] font-bold text-slate-500 uppercase">Role</label>
                      <select
                        value={u.role}
                        onChange={(e) => handleBatchChange(idx, 'role', e.target.value)}
                        className="w-full p-2 bg-white border border-slate-300 rounded-lg text-xs font-semibold"
                      >
                        <option value="clerk">Clerk</option>
                        <option value="admin">Admin</option>
                      </select>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="flex-1">
                        <label className="block text-[10px] font-bold text-slate-500 uppercase">Password *</label>
                        <input
                          type="password"
                          required
                          placeholder="Password"
                          value={u.password}
                          onChange={(e) => handleBatchChange(idx, 'password', e.target.value)}
                          className="w-full p-2 bg-white border border-slate-300 rounded-lg font-mono text-xs"
                        />
                      </div>
                      {batchUsers.length > 1 && (
                        <button
                          type="button"
                          onClick={() => handleRemoveBatchRow(idx)}
                          className="mt-4 p-2 text-rose-500 hover:bg-rose-50 rounded-lg cursor-pointer"
                          title="Remove row"
                        >
                          <Trash2 size={14} />
                        </button>
                      )}
                    </div>
                  </div>
                ))}
              </div>

              <div className="flex items-center justify-between pt-2">
                <button
                  type="button"
                  onClick={handleAddBatchRow}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-slate-700 bg-slate-100 hover:bg-slate-200 border border-slate-300 rounded-lg cursor-pointer"
                >
                  <Plus size={14} />
                  Add Another Row
                </button>

                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={() => setIsBatchModalOpen(false)}
                    className="px-4 py-2 text-slate-600 hover:bg-slate-100 rounded-lg font-semibold"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={savingBatch}
                    className="px-5 py-2 bg-orange-600 hover:bg-orange-700 text-white rounded-lg font-bold shadow-xs disabled:opacity-50"
                  >
                    {savingBatch ? 'Creating Users...' : `Create All ${batchUsers.length} Users`}
                  </button>
                </div>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal 3: Admin Reset Password */}
      {resetModalUser && (
        <div className="fixed inset-0 z-50 bg-black/50 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl shadow-xl border border-slate-200 max-w-md w-full overflow-hidden animate-in zoom-in-95 duration-150">
            <div className="p-5 border-b border-slate-100 flex items-center justify-between bg-slate-50">
              <div className="flex items-center gap-2">
                <KeyRound size={18} className="text-orange-600" />
                <h3 className="font-bold text-slate-900 text-sm">
                  Reset Password for @{resetModalUser.username}
                </h3>
              </div>
              <button onClick={() => setResetModalUser(null)} className="text-slate-400 hover:text-slate-600 cursor-pointer">
                <X size={16} />
              </button>
            </div>

            <form onSubmit={handleResetPassword} className="p-6 space-y-4 text-xs">
              <p className="text-slate-500">
                Setting a new password will immediately renew the user's <span className="font-bold text-slate-800">15-day password timer</span>.
              </p>

              <div>
                <label className="block font-semibold text-slate-700 mb-1">New Password *</label>
                <input
                  type="password"
                  required
                  placeholder="Enter new password (min 4 chars)"
                  value={newPasswordInput}
                  onChange={(e) => setNewPasswordInput(e.target.value)}
                  className="w-full p-2.5 bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500 font-mono text-xs"
                />
              </div>

              <div>
                <label className="block font-semibold text-slate-700 mb-1">Confirm New Password *</label>
                <input
                  type="password"
                  required
                  placeholder="Confirm new password"
                  value={confirmPasswordInput}
                  onChange={(e) => setConfirmPasswordInput(e.target.value)}
                  className="w-full p-2.5 bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500 font-mono text-xs"
                />
              </div>

              <div className="pt-2 flex justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setResetModalUser(null)}
                  className="px-4 py-2 text-slate-600 hover:bg-slate-100 rounded-lg font-semibold"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={savingReset}
                  className="px-5 py-2 bg-orange-600 hover:bg-orange-700 text-white rounded-lg font-bold shadow-xs disabled:opacity-50"
                >
                  {savingReset ? 'Resetting...' : 'Update Password & Renew 15 Days'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
