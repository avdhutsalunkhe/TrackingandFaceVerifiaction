import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { 
  Search, Plus, Upload, Filter, MoreHorizontal, User, RefreshCw, 
  X, Edit, Trash2, Download, History, Calendar, CheckCircle2, ShieldAlert,
  CalendarDays
} from 'lucide-react';

import { API_BASE } from '../api/client';
import MonthlyShiftModal from '../components/MonthlyShiftModal';


export default function Employees() {
  const [employees, setEmployees] = useState([]);
  const [summary, setSummary] = useState({ total: 0, active: 0, inactive: 0, missing_info: 0 });
  const [departments, setDepartments] = useState([]);
  const [loading, setLoading] = useState(true);

  // Filters
  const [searchTerm, setSearchTerm] = useState('');
  const [deptFilter, setDeptFilter] = useState('All');
  const [statusFilter, setStatusFilter] = useState('All');

  // Modals & State
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [editEmployee, setEditEmployee] = useState(null);
  const [historyEmployee, setHistoryEmployee] = useState(null);
  const [employeeHistory, setEmployeeHistory] = useState([]);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [importing, setImporting] = useState(false);
  const [shiftModalEmployee, setShiftModalEmployee] = useState(null);
  
  const [formData, setFormData] = useState({

    id: '', name: '', department: '', designation: '', email: '', phone: '', status: 'Active'
  });
  const [error, setError] = useState('');

  const fetchEmployees = async () => {
    setLoading(true);
    try {
      let url = `${API_BASE}/employees/?size=100`;
      if (searchTerm) url += `&search=${searchTerm}`;
      if (deptFilter !== 'All') url += `&department=${deptFilter}`;
      if (statusFilter !== 'All') url += `&status=${statusFilter}`;

      const [empRes, sumRes, deptRes] = await Promise.all([
        axios.get(url),
        axios.get(`${API_BASE}/employees/summary`),
        axios.get(`${API_BASE}/employees/departments`)
      ]);
      setEmployees(empRes.data.items || []);
      setSummary(sumRes.data);
      setDepartments(deptRes.data || []);
    } catch (err) {
      console.error('Failed to fetch employees', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchEmployees();
  }, [searchTerm, deptFilter, statusFilter]);

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData({ ...formData, [name]: value });
  };

  const handleAddSubmit = async (e) => {
    e.preventDefault();
    setError('');
    try {
      await axios.post(`${API_BASE}/employees/`, formData);
      setIsAddModalOpen(false);
      setFormData({ id: '', name: '', department: '', designation: '', email: '', phone: '', status: 'Active' });
      fetchEmployees();
    } catch (err) {
      setError(err.response?.data?.detail || 'An error occurred while saving.');
    }
  };

  const handleEditSubmit = async (e) => {
    e.preventDefault();
    if (!editEmployee) return;
    try {
      const payload = {
        name: editEmployee.name,
        department: editEmployee.department || null,
        designation: editEmployee.designation || null,
        email: editEmployee.email || null,
        phone: editEmployee.phone || null,
        status: editEmployee.status || 'Active'
      };
      await axios.put(`${API_BASE}/employees/${editEmployee.id}`, payload);
      setEditEmployee(null);
      fetchEmployees();
    } catch (err) {
      alert('Failed to update employee: ' + (err.response?.data?.detail || err.message));
    }
  };

  const handleDelete = async (empId) => {
    if (!window.confirm(`Delete employee record ${empId}? This will remove attendance history for this employee.`)) return;
    try {
      await axios.delete(`${API_BASE}/employees/${empId}`);
      fetchEmployees();
    } catch (err) {
      alert('Failed to delete employee: ' + (err.response?.data?.detail || err.message));
    }
  };

  const toggleStatus = async (empId, currentStatus) => {
    const newStatus = currentStatus === 'Active' ? 'Inactive' : 'Active';
    try {
      await axios.patch(`${API_BASE}/employees/${empId}/status`, { status: newStatus });
      fetchEmployees();
    } catch (err) {
      console.error('Failed to update status', err);
    }
  };

  const openHistory = async (emp) => {
    setHistoryEmployee(emp);
    setLoadingHistory(true);
    try {
      const res = await axios.get(`${API_BASE}/employees/${emp.id}/attendance?limit=20`);
      setEmployeeHistory(res.data || []);
    } catch (err) {
      console.error('Failed to load employee history', err);
    } finally {
      setLoadingHistory(false);
    }
  };

  const handleImport = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    const fd = new FormData();
    fd.append('file', file);
    
    setImporting(true);
    try {
      const res = await axios.post(`${API_BASE}/employees/import`, fd, {
        headers: { 'Content-Type': 'multipart/form-data' }
      });
      alert(res.data.message);
      fetchEmployees();
    } catch (err) {
      alert('Import failed: ' + (err.response?.data?.detail || err.message));
    } finally {
      setImporting(false);
      e.target.value = '';
    }
  };

  const exportEmployeesCsv = () => {
    if (employees.length === 0) return;
    const headers = ["Employee ID", "Name", "Department", "Designation", "Email", "Phone", "Status"];
    const rows = employees.map(e => [
      e.id,
      `"${e.name}"`,
      `"${e.department || ''}"`,
      `"${e.designation || ''}"`,
      `"${e.email || ''}"`,
      `"${e.phone || ''}"`,
      e.status
    ]);
    const csvContent = "data:text/csv;charset=utf-8," + [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement("a");
    link.setAttribute("href", encodedUri);
    link.setAttribute("download", `employees_roster.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-8">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Employees Directory</h1>
          <p className="text-slate-500 text-sm mt-1">Manage employee records, organizational departments, and biometric identities.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2.5">
          <button
            onClick={exportEmployeesCsv}
            className="flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-slate-700 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors"
          >
            <Download size={14} /> Export CSV
          </button>
          <label className="flex items-center gap-1.5 px-3 py-2 bg-white border border-slate-300 text-slate-700 text-xs font-semibold rounded-lg hover:bg-slate-50 transition-colors cursor-pointer">
            <Upload size={14} /> {importing ? 'Importing...' : 'Import Excel'}
            <input type="file" className="hidden" accept=".xlsx,.xls,.csv" onChange={handleImport} disabled={importing} />
          </label>
          <button 
            onClick={() => setIsAddModalOpen(true)}
            className="flex items-center gap-1.5 px-3.5 py-2 bg-brand-600 text-white text-xs font-semibold rounded-lg hover:bg-brand-700 transition-colors shadow-sm">
            <Plus size={15} /> Add Employee
          </button>
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm">
          <p className="text-xs font-medium text-slate-500">Total Staff</p>
          <p className="text-2xl font-bold text-slate-900 mt-1">{summary.total}</p>
        </div>
        <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm">
          <p className="text-xs font-medium text-emerald-600">Active</p>
          <p className="text-2xl font-bold text-emerald-600 mt-1">{summary.active}</p>
        </div>
        <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm">
          <p className="text-xs font-medium text-rose-600">Inactive</p>
          <p className="text-2xl font-bold text-rose-600 mt-1">{summary.inactive}</p>
        </div>
        <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm">
          <p className="text-xs font-medium text-amber-600">Missing Info</p>
          <p className="text-2xl font-bold text-amber-600 mt-1">{summary.missing_info}</p>
        </div>
      </div>

      {/* Main Table Container */}
      <div className="bg-white rounded-xl border border-slate-200/80 shadow-sm overflow-hidden">
        {/* Toolbar */}
        <div className="p-4 border-b border-slate-200 bg-slate-50/70 flex flex-wrap gap-3 items-center justify-between">
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative w-64">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={15} />
              <input 
                type="text" 
                placeholder="Search name, ID, or title..." 
                className="w-full pl-9 pr-3 py-1.5 text-xs bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
              />
            </div>

            {/* Department Filter */}
            <select
              value={deptFilter}
              onChange={(e) => setDeptFilter(e.target.value)}
              className="px-3 py-1.5 text-xs bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium text-slate-700"
            >
              <option value="All">All Departments</option>
              {departments.map(d => (
                <option key={d} value={d}>{d}</option>
              ))}
            </select>

            {/* Status Filter */}
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="px-3 py-1.5 text-xs bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium text-slate-700"
            >
              <option value="All">All Statuses</option>
              <option value="Active">Active</option>
              <option value="Inactive">Inactive</option>
            </select>

            {(searchTerm || deptFilter !== 'All' || statusFilter !== 'All') && (
              <button 
                onClick={() => { setSearchTerm(''); setDeptFilter('All'); setStatusFilter('All'); }}
                className="text-xs text-brand-600 hover:underline font-medium"
              >
                Reset
              </button>
            )}
          </div>

          <button onClick={fetchEmployees} className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-slate-700 bg-white border border-slate-200 rounded-lg hover:bg-slate-50 transition-colors">
            <RefreshCw size={14} /> Refresh
          </button>
        </div>

        {/* Table */}
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs border-collapse">
            <thead>
              <tr className="bg-slate-100/70 border-b border-slate-200 text-slate-600 font-semibold uppercase tracking-wider">
                <th className="p-3.5">ID</th>
                <th className="p-3.5">Employee Name</th>
                <th className="p-3.5">Department</th>
                <th className="p-3.5">Designation</th>
                <th className="p-3.5">Shift</th>
                <th className="p-3.5">Status</th>
                <th className="p-3.5 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {loading ? (
                <tr><td colSpan="7" className="p-8 text-center text-slate-400">Loading employees...</td></tr>
              ) : employees.length === 0 ? (
                <tr><td colSpan="7" className="p-8 text-center text-slate-400">No employees match criteria.</td></tr>
              ) : (
                employees.map(emp => (
                  <tr key={emp.id} className="hover:bg-slate-50 transition-colors">
                    <td className="p-3.5 font-mono font-medium text-slate-600">{emp.id}</td>
                    <td className="p-3.5">
                      <div className="flex items-center gap-2.5">
                        <div className="w-7 h-7 rounded-full bg-brand-100 text-brand-700 flex items-center justify-center font-bold text-xs shrink-0">
                          {emp.name.charAt(0)}
                        </div>
                        <button
                          onClick={() => openHistory(emp)}
                          className="font-semibold text-slate-900 hover:text-brand-600 text-left transition-colors"
                        >
                          {emp.name}
                        </button>
                      </div>
                    </td>
                    <td className="p-3.5 text-slate-700 font-medium">{emp.department || '—'}</td>
                    <td className="p-3.5 text-slate-600">{emp.designation || '—'}</td>
                    <td className="p-3.5">
                      {emp.current_shift ? (
                        <span className={`inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold border ${
                          emp.current_shift_code === 'OFF'
                            ? 'bg-slate-100 text-slate-600 border-slate-200'
                            : 'bg-emerald-50 text-emerald-800 border-emerald-200'
                        }`}>
                          {emp.current_shift}
                        </span>
                      ) : (
                        <span className="text-slate-400 text-xs italic">—</span>
                      )}
                    </td>
                    <td className="p-3.5">
                      <button
                        onClick={() => toggleStatus(emp.id, emp.status)}
                        className={`inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold cursor-pointer ${
                          emp.status === 'Active' ? 'bg-emerald-100 text-emerald-800' : 'bg-rose-100 text-rose-800'
                        }`}
                        title="Click to toggle status"
                      >
                        {emp.status}
                      </button>
                    </td>
                    <td className="p-3.5 text-right">
                      <div className="inline-flex items-center gap-2">
                        <button 
                          onClick={() => setShiftModalEmployee(emp)}
                          className="p-1 text-brand-600 hover:text-brand-700 hover:bg-brand-50 rounded transition-colors"
                          title="Manage Monthly Shifts"
                        >
                          <CalendarDays size={16} />
                        </button>
                        <button 
                          onClick={() => openHistory(emp)}
                          className="p-1 text-slate-400 hover:text-brand-600 hover:bg-brand-50 rounded transition-colors"
                          title="View Attendance History"
                        >
                          <History size={15} />
                        </button>
                        <button 
                          onClick={() => setEditEmployee({ ...emp })}
                          className="p-1 text-slate-400 hover:text-slate-800 hover:bg-slate-100 rounded transition-colors"
                          title="Edit Profile"
                        >
                          <Edit size={15} />
                        </button>
                        <button 
                          onClick={() => handleDelete(emp.id)}
                          className="p-1 text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded transition-colors"
                          title="Delete Employee"
                        >
                          <Trash2 size={15} />
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


      {/* Add Employee Modal */}
      {isAddModalOpen && (
        <div className="fixed inset-0 bg-slate-900/50 backdrop-blur-xs flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl shadow-2xl max-w-md w-full overflow-hidden">
            <div className="flex justify-between items-center p-5 border-b border-slate-100 bg-slate-50">
              <h2 className="text-base font-bold text-slate-900">Add Employee Record</h2>
              <button onClick={() => setIsAddModalOpen(false)} className="text-slate-400 hover:text-slate-600">
                <X size={18} />
              </button>
            </div>
            <form onSubmit={handleAddSubmit} className="p-5 space-y-3.5 text-xs">
              {error && <div className="p-2.5 bg-rose-50 text-rose-600 rounded border border-rose-200">{error}</div>}
              <div>
                <label className="block font-semibold text-slate-700 mb-1">Employee ID *</label>
                <input 
                  type="text" name="id" required placeholder="e.g. EMP115" value={formData.id} onChange={handleInputChange}
                  className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono"
                />
              </div>
              <div>
                <label className="block font-semibold text-slate-700 mb-1">Full Name *</label>
                <input 
                  type="text" name="name" required placeholder="e.g. John Doe" value={formData.name} onChange={handleInputChange}
                  className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Department</label>
                  <input 
                    type="text" name="department" placeholder="Engineering" value={formData.department} onChange={handleInputChange}
                    className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
                  />
                </div>
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Designation</label>
                  <input 
                    type="text" name="designation" placeholder="Specialist" value={formData.designation} onChange={handleInputChange}
                    className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Email</label>
                  <input 
                    type="email" name="email" placeholder="john@company.com" value={formData.email} onChange={handleInputChange}
                    className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
                  />
                </div>
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Phone</label>
                  <input 
                    type="text" name="phone" placeholder="+91 99999..." value={formData.phone} onChange={handleInputChange}
                    className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-mono"
                  />
                </div>
              </div>
              <div className="mt-5 flex gap-2 justify-end pt-2">
                <button type="button" onClick={() => setIsAddModalOpen(false)} className="px-4 py-2 text-slate-600 hover:bg-slate-100 rounded-lg font-semibold">
                  Cancel
                </button>
                <button type="submit" className="px-4 py-2 bg-brand-600 text-white rounded-lg hover:bg-brand-700 font-semibold shadow-sm">
                  Save Employee
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Edit Employee Modal */}
      {editEmployee && (
        <div className="fixed inset-0 bg-slate-900/50 backdrop-blur-xs flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl shadow-2xl max-w-md w-full overflow-hidden">
            <div className="flex justify-between items-center p-5 border-b border-slate-100 bg-slate-50">
              <h2 className="text-base font-bold text-slate-900">Edit Employee: {editEmployee.id}</h2>
              <button onClick={() => setEditEmployee(null)} className="text-slate-400 hover:text-slate-600">
                <X size={18} />
              </button>
            </div>
            <form onSubmit={handleEditSubmit} className="p-5 space-y-3.5 text-xs">
              <div>
                <label className="block font-semibold text-slate-700 mb-1">Full Name</label>
                <input 
                  type="text" required value={editEmployee.name} 
                  onChange={(e) => setEditEmployee({ ...editEmployee, name: e.target.value })}
                  className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Department</label>
                  <input 
                    type="text" value={editEmployee.department || ''} 
                    onChange={(e) => setEditEmployee({ ...editEmployee, department: e.target.value })}
                    className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
                  />
                </div>
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Designation</label>
                  <input 
                    type="text" value={editEmployee.designation || ''} 
                    onChange={(e) => setEditEmployee({ ...editEmployee, designation: e.target.value })}
                    className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Email</label>
                  <input 
                    type="email" value={editEmployee.email || ''} 
                    onChange={(e) => setEditEmployee({ ...editEmployee, email: e.target.value })}
                    className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
                  />
                </div>
                <div>
                  <label className="block font-semibold text-slate-700 mb-1">Status</label>
                  <select
                    value={editEmployee.status}
                    onChange={(e) => setEditEmployee({ ...editEmployee, status: e.target.value })}
                    className="w-full p-2 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-semibold"
                  >
                    <option value="Active">Active</option>
                    <option value="Inactive">Inactive</option>
                  </select>
                </div>
              </div>
              <div className="mt-5 flex gap-2 justify-end pt-2">
                <button type="button" onClick={() => setEditEmployee(null)} className="px-4 py-2 text-slate-600 hover:bg-slate-100 rounded-lg font-semibold">
                  Cancel
                </button>
                <button type="submit" className="px-4 py-2 bg-brand-600 text-white rounded-lg hover:bg-brand-700 font-semibold shadow-sm">
                  Update Changes
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Employee Attendance History Drawer / Modal */}
      {historyEmployee && (
        <div className="fixed inset-0 bg-slate-900/50 backdrop-blur-xs flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl shadow-2xl max-w-2xl w-full max-h-[85vh] flex flex-col overflow-hidden">
            <div className="flex justify-between items-center p-5 border-b border-slate-100 bg-slate-50">
              <div>
                <h2 className="text-base font-bold text-slate-900">{historyEmployee.name}</h2>
                <p className="text-xs text-slate-500">{historyEmployee.department} • ID: {historyEmployee.id}</p>
              </div>
              <button onClick={() => setHistoryEmployee(null)} className="text-slate-400 hover:text-slate-600">
                <X size={18} />
              </button>
            </div>

            <div className="p-5 overflow-y-auto flex-1">
              <h3 className="text-xs font-bold uppercase tracking-wider text-slate-500 mb-3">Recent 30-Day Attendance Logs</h3>
              {loadingHistory ? (
                <div className="p-8 text-center text-slate-400 text-xs">Loading records...</div>
              ) : employeeHistory.length === 0 ? (
                <div className="p-8 text-center text-slate-400 text-xs">No daily attendance recorded for this employee.</div>
              ) : (
                <div className="divide-y divide-slate-100 text-xs">
                  {employeeHistory.map((item, idx) => (
                    <div key={idx} className="py-2.5 flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <span className="font-semibold text-slate-800 w-24">{item.date}</span>
                        <span className={`inline-flex px-2 py-0.5 rounded text-[10px] font-bold ${
                          item.status === 'P' ? 'bg-emerald-100 text-emerald-800' :
                          item.status === 'HD' ? 'bg-yellow-100 text-yellow-800' :
                          item.status === 'A' ? 'bg-rose-100 text-rose-800' : 'bg-slate-100 text-slate-700'
                        }`}>
                          {item.status}
                        </span>
                      </div>
                      <div className="flex items-center gap-4 text-slate-600 font-mono text-[11px]">
                        <span>In: {item.in_time}</span>
                        <span>Out: {item.out_time}</span>
                        <span className="font-bold text-slate-800">{item.work_hours} hrs</span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Monthly Shift Assignment Modal */}
      {shiftModalEmployee && (
        <MonthlyShiftModal
          employee={shiftModalEmployee}
          onClose={() => setShiftModalEmployee(null)}
          onSaved={fetchEmployees}
        />
      )}
    </div>
  );
}


