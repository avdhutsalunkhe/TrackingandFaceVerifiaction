import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { 
  Upload, FileText, CheckCircle2, AlertCircle, RefreshCw, 
  Search, Download, Sparkles, Filter, Database, Calendar
} from 'lucide-react';

import { API_BASE } from '../api/client';

export default function Imports() {
  const [punches, setPunches] = useState([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [importResult, setImportResult] = useState(null);
  const [error, setError] = useState('');

  // Filters
  const [searchEmp, setSearchEmp] = useState('');
  const [dateFilter, setDateFilter] = useState('');
  const [dirFilter, setDirFilter] = useState('All');
  const [page, setPage] = useState(1);

  const fetchPunches = async () => {
    setLoading(true);
    try {
      let url = `${API_BASE}/attendance/punches?page=${page}&size=50`;
      if (searchEmp) url += `&employee_id=${searchEmp}`;
      if (dateFilter) url += `&date=${dateFilter}`;
      if (dirFilter && dirFilter !== 'All') url += `&direction=${dirFilter}`;

      const res = await axios.get(url);
      setPunches(res.data.items || []);
      setTotal(res.data.total || 0);
    } catch (err) {
      console.error('Failed to fetch punches:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchPunches();
  }, [page, searchEmp, dateFilter, dirFilter]);

  const handleFileUpload = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const formData = new FormData();
    formData.append('file', file);

    setUploading(true);
    setError('');
    setImportResult(null);

    try {
      const res = await axios.post(`${API_BASE}/attendance/import`, formData, {
        headers: { 'Content-Type': 'multipart/form-data' }
      });
      setImportResult(res.data);
      fetchPunches();
    } catch (err) {
      setError(err.response?.data?.detail || 'Import failed. Check file structure.');
    } finally {
      setUploading(false);
      e.target.value = '';
    }
  };

  const handleSeedDemo = async () => {
    setUploading(true);
    setError('');
    setImportResult(null);
    try {
      const res = await axios.post(`${API_BASE}/settings/seed-demo`);
      setImportResult({
        status: 'success',
        message: res.data.message,
        data: {
          new_punches: res.data.total_punches_created,
          dates_processed: [`${res.data.days_seeded} days of biometric logs`]
        }
      });
      fetchPunches();
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to seed sample biometric data');
    } finally {
      setUploading(false);
    }
  };

  const downloadSampleCsv = () => {
    const csvContent = "data:text/csv;charset=utf-8," + 
      "Employee ID,Timestamp,Direction\n" +
      "EMP101,2026-10-09 08:55:00,IN\n" +
      "EMP101,2026-10-09 18:05:00,OUT\n" +
      "EMP102,2026-10-09 09:12:00,IN\n" +
      "EMP102,2026-10-09 18:15:00,OUT\n" +
      "EMP103,2026-10-09 09:30:00,IN\n" +
      "EMP103,2026-10-09 18:00:00,OUT";
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement("a");
    link.setAttribute("href", encodedUri);
    link.setAttribute("download", "sample_attendance_punches.csv");
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const downloadSampleDat = () => {
    const datContent = "data:text/plain;charset=utf-8," + 
      "EMP101\t2026-10-09 08:55:00\t0\t1\n" +
      "EMP101\t2026-10-09 18:05:00\t1\t1\n" +
      "EMP102\t2026-10-09 09:12:00\t0\t1\n" +
      "EMP102\t2026-10-09 18:15:00\t1\t1";
    const encodedUri = encodeURI(datContent);
    const link = document.createElement("a");
    link.setAttribute("href", encodedUri);
    link.setAttribute("download", "sample_biometric_device.dat");
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-8">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Biometric Data Imports</h1>
          <p className="text-slate-500 text-sm mt-1">
            Import biometric punch logs from Excel (.xlsx), CSV, or machine log files (.dat). Automatically updates daily attendance.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={downloadSampleCsv}
            className="flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-slate-700 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors"
          >
            <Download size={14} /> Sample CSV
          </button>
          <button
            onClick={downloadSampleDat}
            className="flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-slate-700 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors"
          >
            <Download size={14} /> Sample .DAT
          </button>
          <button
            onClick={handleSeedDemo}
            disabled={uploading}
            className="flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold text-brand-700 bg-brand-50 border border-brand-200 rounded-lg hover:bg-brand-100 transition-colors disabled:opacity-50"
          >
            <Sparkles size={14} /> Seed Demo Biometric Logs
          </button>
        </div>
      </div>

      {/* Upload Zone */}
      <div className="bg-white border-2 border-dashed border-slate-300 hover:border-brand-500 rounded-xl p-8 text-center transition-all bg-gradient-to-b from-slate-50/50 to-white">
        <div className="max-w-md mx-auto flex flex-col items-center">
          <div className="w-14 h-14 rounded-full bg-brand-50 text-brand-600 flex items-center justify-center mb-4">
            <Upload size={28} />
          </div>
          <h2 className="text-base font-bold text-slate-900">Upload Biometric Machine Logs</h2>
          <p className="text-xs text-slate-500 mt-1 mb-5">
            Supported formats: <span className="font-semibold text-slate-700">.xlsx, .xls, .csv, .dat, .txt</span> (ZKTeco, eSSL, Realtime Biometrics)
          </p>

          <label className="inline-flex items-center gap-2 px-5 py-2.5 bg-brand-600 hover:bg-brand-700 text-white text-sm font-semibold rounded-lg shadow-sm cursor-pointer transition-colors">
            {uploading ? (
              <>
                <RefreshCw size={16} className="animate-spin" />
                Processing Biometric Records...
              </>
            ) : (
              <>
                <FileText size={16} />
                Select File to Import
              </>
            )}
            <input
              type="file"
              className="hidden"
              accept=".xlsx,.xls,.csv,.dat,.txt"
              onChange={handleFileUpload}
              disabled={uploading}
            />
          </label>
        </div>
      </div>

      {/* Import Feedback Banner */}
      {importResult && (
        <div className="bg-emerald-50 border border-emerald-200 rounded-xl p-4 flex items-start gap-3 text-emerald-900">
          <CheckCircle2 size={20} className="text-emerald-600 mt-0.5 shrink-0" />
          <div className="text-xs">
            <p className="font-bold text-sm text-emerald-800">{importResult.message}</p>
            {importResult.data && (
              <p className="mt-1 text-emerald-700">
                Punches Stored: <span className="font-semibold">{importResult.data.new_punches}</span> • 
                Duplicates Skipped: <span className="font-semibold">{importResult.data.duplicates || 0}</span> • 
                Dates Recalculated: <span className="font-semibold">{importResult.data.dates_processed?.length || 0}</span>
              </p>
            )}
          </div>
        </div>
      )}

      {error && (
        <div className="bg-rose-50 border border-rose-200 rounded-xl p-4 flex items-start gap-3 text-rose-900">
          <AlertCircle size={20} className="text-rose-600 mt-0.5 shrink-0" />
          <div className="text-xs">
            <p className="font-bold text-sm text-rose-800">Import Failed</p>
            <p className="mt-0.5 text-rose-700">{error}</p>
          </div>
        </div>
      )}

      {/* Punch Log Viewer Section */}
      <div className="bg-white rounded-xl border border-slate-200/80 shadow-sm overflow-hidden">
        {/* Table Toolbar */}
        <div className="p-4 border-b border-slate-200 bg-slate-50/70 flex flex-wrap gap-3 items-center justify-between">
          <div className="flex flex-wrap items-center gap-3">
            {/* Search */}
            <div className="relative w-56">
              <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
              <input
                type="text"
                placeholder="Search Employee ID..."
                value={searchEmp}
                onChange={(e) => setSearchEmp(e.target.value)}
                className="w-full pl-9 pr-3 py-1.5 text-xs bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
              />
            </div>

            {/* Date filter */}
            <div className="relative">
              <input
                type="date"
                value={dateFilter}
                onChange={(e) => setDateFilter(e.target.value)}
                className="px-3 py-1.5 text-xs bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
              />
            </div>

            {/* Direction Filter */}
            <select
              value={dirFilter}
              onChange={(e) => setDirFilter(e.target.value)}
              className="px-3 py-1.5 text-xs bg-white border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500 font-medium text-slate-700"
            >
              <option value="All">All Directions</option>
              <option value="IN">IN Only</option>
              <option value="OUT">OUT Only</option>
              <option value="AUTO">AUTO</option>
            </select>

            {(searchEmp || dateFilter || dirFilter !== 'All') && (
              <button
                onClick={() => { setSearchEmp(''); setDateFilter(''); setDirFilter('All'); }}
                className="text-xs text-brand-600 hover:underline font-medium"
              >
                Clear Filters
              </button>
            )}
          </div>

          <div className="flex items-center gap-3">
            <span className="text-xs text-slate-500">
              Showing <span className="font-semibold text-slate-800">{punches.length}</span> of <span className="font-semibold text-slate-800">{total}</span> punches
            </span>
            <button
              onClick={fetchPunches}
              className="p-1.5 text-slate-500 hover:text-slate-800 hover:bg-slate-200/50 rounded-lg transition-colors"
              title="Refresh"
            >
              <RefreshCw size={16} />
            </button>
          </div>
        </div>

        {/* Table */}
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs border-collapse">
            <thead>
              <tr className="bg-slate-100/70 border-b border-slate-200 text-slate-600 font-semibold uppercase tracking-wider">
                <th className="p-3.5">ID</th>
                <th className="p-3.5">Employee</th>
                <th className="p-3.5">Department</th>
                <th className="p-3.5">Punch Date</th>
                <th className="p-3.5">Time</th>
                <th className="p-3.5">Direction</th>
                <th className="p-3.5">Terminal / Source</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {loading ? (
                <tr>
                  <td colSpan="7" className="p-8 text-center text-slate-400">Loading punch logs...</td>
                </tr>
              ) : punches.length === 0 ? (
                <tr>
                  <td colSpan="7" className="p-8 text-center text-slate-400">
                    No punch records found. Upload a file above or click "Seed Demo Biometric Logs".
                  </td>
                </tr>
              ) : (
                punches.map((p) => (
                  <tr key={p.id} className="hover:bg-slate-50 transition-colors">
                    <td className="p-3.5 font-mono text-slate-500">{p.id}</td>
                    <td className="p-3.5 font-medium text-slate-800">
                      <div>
                        <span>{p.employee_name}</span>
                        <span className="block font-mono text-[11px] text-slate-400">ID: {p.employee_id}</span>
                      </div>
                    </td>
                    <td className="p-3.5 text-slate-600">{p.department}</td>
                    <td className="p-3.5 text-slate-700">{p.date_str}</td>
                    <td className="p-3.5 font-mono font-semibold text-slate-800">{p.time_str}</td>
                    <td className="p-3.5">
                      <span className={`inline-flex px-2 py-0.5 rounded text-[11px] font-semibold ${
                        p.source_direction === 'IN'
                          ? 'bg-emerald-100 text-emerald-800'
                          : p.source_direction === 'OUT'
                          ? 'bg-blue-100 text-blue-800'
                          : 'bg-slate-100 text-slate-700'
                      }`}>
                        {p.source_direction || 'AUTO'}
                      </span>
                    </td>
                    <td className="p-3.5 text-slate-500 font-mono text-[11px]">{p.source_id || 'Terminal'}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {/* Pagination Footer */}
        {total > 50 && (
          <div className="p-3.5 border-t border-slate-200 bg-slate-50 flex items-center justify-between text-xs text-slate-600">
            <span>Page {page} of {Math.ceil(total / 50)}</span>
            <div className="flex gap-2">
              <button
                disabled={page <= 1}
                onClick={() => setPage(page - 1)}
                className="px-3 py-1 bg-white border border-slate-300 rounded hover:bg-slate-100 disabled:opacity-40"
              >
                Previous
              </button>
              <button
                disabled={page >= Math.ceil(total / 50)}
                onClick={() => setPage(page + 1)}
                className="px-3 py-1 bg-white border border-slate-300 rounded hover:bg-slate-100 disabled:opacity-40"
              >
                Next
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
