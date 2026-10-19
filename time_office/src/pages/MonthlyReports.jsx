import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { 
  FileSpreadsheet, FileText, Download, RefreshCw, 
  Calendar, Users, Percent, Clock, ChevronDown, CheckCircle2, Building2
} from 'lucide-react';

import { API_BASE } from '../api/client';

const MONTHS = [
  { value: 1, name: "January" }, { value: 2, name: "February" },
  { value: 3, name: "March" }, { value: 4, name: "April" },
  { value: 5, name: "May" }, { value: 6, name: "June" },
  { value: 7, name: "July" }, { value: 8, name: "August" },
  { value: 9, name: "September" }, { value: 10, name: "October" },
  { value: 11, name: "November" }, { value: 12, name: "December" }
];

export default function MonthlyReports() {
  const today = new Date();
  const [year, setYear] = useState(today.getFullYear());
  const [month, setMonth] = useState(today.getMonth() + 1);
  const [department, setDepartment] = useState('All');
  const [departments, setDepartments] = useState([]);
  
  const [matrixData, setMatrixData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [downloadingExcel, setDownloadingExcel] = useState(false);
  const [downloadingPdf, setDownloadingPdf] = useState(false);

  const fetchDepartments = async () => {
    try {
      const res = await axios.get(`${API_BASE}/employees/departments`);
      setDepartments(res.data || []);
    } catch (e) {
      console.error(e);
    }
  };

  const fetchMatrix = async () => {
    setLoading(true);
    try {
      const res = await axios.get(`${API_BASE}/reports/monthly`, {
        params: {
          year,
          month,
          department: department !== 'All' ? department : undefined
        }
      });
      setMatrixData(res.data);
    } catch (err) {
      console.error('Failed to load monthly matrix', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchDepartments();
  }, []);

  useEffect(() => {
    fetchMatrix();
  }, [year, month, department]);

  const handleDownloadExcel = async () => {
    setDownloadingExcel(true);
    try {
      const res = await axios.get(`${API_BASE}/reports/export/excel`, {
        params: { year, month, department: department !== 'All' ? department : undefined },
        responseType: 'blob'
      });
      const url = window.URL.createObjectURL(new Blob([res.data]));
      const link = document.createElement('a');
      link.href = url;
      link.setAttribute('download', `Monthly_Attendance_${year}_${String(month).padStart(2, '0')}.xlsx`);
      document.body.appendChild(link);
      link.click();
      link.remove();
    } catch (err) {
      alert('Failed to download Excel report: ' + err.message);
    } finally {
      setDownloadingExcel(false);
    }
  };

  const handleDownloadPdf = async () => {
    setDownloadingPdf(true);
    try {
      const res = await axios.get(`${API_BASE}/reports/export/pdf`, {
        params: { year, month, department: department !== 'All' ? department : undefined },
        responseType: 'blob'
      });
      const url = window.URL.createObjectURL(new Blob([res.data]));
      const link = document.createElement('a');
      link.href = url;
      link.setAttribute('download', `Monthly_Attendance_${year}_${String(month).padStart(2, '0')}.pdf`);
      document.body.appendChild(link);
      link.click();
      link.remove();
    } catch (err) {
      alert('Failed to download PDF report: ' + err.message);
    } finally {
      setDownloadingPdf(false);
    }
  };

  const daysCount = matrixData?.days_in_month || 31;
  const daysArray = Array.from({ length: daysCount }, (_, i) => i + 1);

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-8">
      {/* Header & Controls */}
      <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4 bg-white p-6 rounded-xl border border-slate-200/80 shadow-sm">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Monthly Attendance & Payroll Matrix</h1>
          <p className="text-slate-500 text-sm mt-0.5">
            Full-calendar visual roster, work hours audit, and executive export generation.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          {/* Month Selector */}
          <select
            value={month}
            onChange={(e) => setMonth(Number(e.target.value))}
            className="px-3 py-2 text-xs font-semibold bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
          >
            {MONTHS.map(m => (
              <option key={m.value} value={m.value}>{m.name}</option>
            ))}
          </select>

          {/* Year Selector */}
          <select
            value={year}
            onChange={(e) => setYear(Number(e.target.value))}
            className="px-3 py-2 text-xs font-semibold bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
          >
            <option value={2025}>2025</option>
            <option value={2026}>2026</option>
            <option value={2027}>2027</option>
          </select>

          {/* Department Filter */}
          <select
            value={department}
            onChange={(e) => setDepartment(e.target.value)}
            className="px-3 py-2 text-xs font-semibold bg-slate-50 border border-slate-300 rounded-lg focus:outline-none focus:border-brand-500"
          >
            <option value="All">All Departments</option>
            {departments.map(d => (
              <option key={d} value={d}>{d}</option>
            ))}
          </select>

          {/* Download Excel */}
          <button
            onClick={handleDownloadExcel}
            disabled={downloadingExcel}
            className="flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold text-emerald-800 bg-emerald-50 hover:bg-emerald-100 border border-emerald-300 rounded-lg transition-colors disabled:opacity-50"
          >
            <FileSpreadsheet size={15} className="text-emerald-600" />
            {downloadingExcel ? 'Exporting Excel...' : 'Export Excel (.xlsx)'}
          </button>

          {/* Download PDF */}
          <button
            onClick={handleDownloadPdf}
            disabled={downloadingPdf}
            className="flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold text-rose-800 bg-rose-50 hover:bg-rose-100 border border-rose-300 rounded-lg transition-colors disabled:opacity-50"
          >
            <FileText size={15} className="text-rose-600" />
            {downloadingPdf ? 'Generating PDF...' : 'Export PDF'}
          </button>
        </div>
      </div>

      {/* Monthly Summary Cards */}
      {matrixData?.summary && (
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
          <div className="bg-white p-5 rounded-xl border border-slate-200 shadow-sm">
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Total Staff</p>
            <p className="text-3xl font-bold text-slate-900 mt-2">{matrixData.summary.total_employees}</p>
          </div>
          <div className="bg-white p-5 rounded-xl border border-slate-200 shadow-sm">
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Avg Attendance %</p>
            <p className="text-3xl font-bold text-brand-600 mt-2">{matrixData.summary.average_attendance}%</p>
          </div>
          <div className="bg-white p-5 rounded-xl border border-slate-200 shadow-sm">
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Total Work Hours</p>
            <p className="text-3xl font-bold text-slate-900 mt-2">{matrixData.summary.total_work_hours} hrs</p>
          </div>
          <div className="bg-white p-5 rounded-xl border border-slate-200 shadow-sm">
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Present Days</p>
            <p className="text-3xl font-bold text-emerald-600 mt-2">{matrixData.summary.present_days}</p>
          </div>
          <div className="bg-white p-5 rounded-xl border border-slate-200 shadow-sm">
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Absent Days</p>
            <p className="text-3xl font-bold text-rose-600 mt-2">{matrixData.summary.absent_days}</p>
          </div>
        </div>
      )}

      {/* Legend */}
      <div className="flex flex-wrap items-center gap-4 text-xs font-medium text-slate-600 bg-white p-3.5 rounded-xl border border-slate-200 shadow-sm">
        <span className="font-bold text-slate-700 uppercase tracking-wider text-[11px]">Legend:</span>
        <span className="inline-flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-emerald-100 border border-emerald-300"></span> <strong>P</strong> (Present)</span>
        <span className="inline-flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-yellow-100 border border-yellow-300"></span> <strong>HD</strong> (Half Day)</span>
        <span className="inline-flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-rose-100 border border-rose-300"></span> <strong>A</strong> (Absent)</span>
        <span className="inline-flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-slate-100 border border-slate-300"></span> <strong>WO</strong> (Weekly Off)</span>
        <span className="inline-flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-amber-50 border border-amber-300"></span> <strong>Late Dot</strong> (&gt;15m)</span>
      </div>

      {/* Full Monthly Matrix Grid */}
      <div className="bg-white rounded-xl border border-slate-200/80 shadow-sm overflow-hidden">
        <div className="p-4 border-b border-slate-200 bg-slate-50/70 flex justify-between items-center">
          <h2 className="text-sm font-bold text-slate-900">
            {matrixData?.month_name} {matrixData?.year} Attendance Heatmap
          </h2>
          <span className="text-xs text-slate-500">
            {matrixData?.employees?.length || 0} employees listed
          </span>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs border-collapse">
            <thead>
              <tr className="bg-slate-100/80 border-b border-slate-200 text-slate-700 font-semibold">
                <th className="p-3 sticky left-0 bg-slate-100/90 z-10 w-44">Employee</th>
                <th className="p-3 w-28">Department</th>
                {daysArray.map(day => (
                  <th key={day} className="p-2 text-center w-8 min-w-[32px] font-mono font-medium">
                    {day}
                  </th>
                ))}
                <th className="p-3 text-center w-20">Total Hrs</th>
                <th className="p-3 text-center w-16">Rate %</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {loading ? (
                <tr>
                  <td colSpan={daysCount + 4} className="p-12 text-center text-slate-400">
                    Loading monthly matrix data...
                  </td>
                </tr>
              ) : !matrixData?.employees || matrixData.employees.length === 0 ? (
                <tr>
                  <td colSpan={daysCount + 4} className="p-12 text-center text-slate-400">
                    No attendance records for this month. Seed demo biometric data or recalculate attendance.
                  </td>
                </tr>
              ) : (
                matrixData.employees.map(emp => (
                  <tr key={emp.id} className="hover:bg-slate-50 transition-colors">
                    {/* Fixed Employee Column */}
                    <td className="p-3 sticky left-0 bg-white group-hover:bg-slate-50 z-10 border-r border-slate-100 shadow-[1px_0_3px_rgba(0,0,0,0.02)]">
                      <div>
                        <span className="font-semibold text-slate-900 block truncate">{emp.name}</span>
                        <span className="font-mono text-[10px] text-slate-400">ID: {emp.id}</span>
                      </div>
                    </td>

                    {/* Department */}
                    <td className="p-3 text-slate-600 truncate max-w-[120px]">{emp.department}</td>

                    {/* Days 1..N */}
                    {daysArray.map(day => {
                      const dInfo = emp.days[String(day)];
                      const st = dInfo?.status || '—';
                      const hrs = dInfo?.hours || 0;
                      const isLate = (dInfo?.late || 0) > 0;

                      let cellStyle = "bg-slate-50/60 text-slate-400";
                      if (st === 'P') cellStyle = "bg-emerald-100/80 text-emerald-800 font-semibold border border-emerald-200";
                      else if (st === 'HD') cellStyle = "bg-yellow-100/80 text-yellow-800 font-semibold border border-yellow-200";
                      else if (st === 'A') cellStyle = "bg-rose-100/80 text-rose-800 font-semibold border border-rose-200";
                      else if (st === 'WO') cellStyle = "bg-slate-100 text-slate-500 font-medium";

                      return (
                        <td key={day} className="p-1 text-center">
                          <div
                            className={`w-7 h-7 mx-auto rounded flex items-center justify-center text-[10px] relative transition-transform hover:scale-110 cursor-help ${cellStyle}`}
                            title={`Day ${day}: ${st} (${hrs} hrs)${isLate ? ` - Late ${dInfo.late}m` : ''}`}
                          >
                            {st}
                            {isLate && (
                              <span className="absolute top-0.5 right-0.5 w-1.5 h-1.5 rounded-full bg-amber-500" />
                            )}
                          </div>
                        </td>
                      );
                    })}

                    {/* Totals */}
                    <td className="p-3 text-center font-mono font-bold text-slate-800 bg-slate-50/40">
                      {emp.totals.total_hours}h
                    </td>
                    <td className="p-3 text-center">
                      <span className={`inline-flex px-1.5 py-0.5 rounded text-[11px] font-bold ${
                        emp.totals.attendance_rate >= 80 ? 'bg-emerald-50 text-emerald-700' : 'bg-amber-50 text-amber-700'
                      }`}>
                        {emp.totals.attendance_rate}%
                      </span>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Monthly Employee Breakdown Table */}
      {matrixData?.employees && matrixData.employees.length > 0 && (
        <div className="bg-white rounded-xl border border-slate-200/80 shadow-sm overflow-hidden">
          <div className="p-4 border-b border-slate-200 bg-slate-50/70">
            <h2 className="text-sm font-bold text-slate-900">Employee Totals & Payroll Summary</h2>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs border-collapse">
              <thead>
                <tr className="bg-slate-100/70 border-b border-slate-200 text-slate-600 font-semibold uppercase tracking-wider">
                  <th className="p-3.5">ID</th>
                  <th className="p-3.5">Name</th>
                  <th className="p-3.5">Department</th>
                  <th className="p-3.5 text-center">Present Days</th>
                  <th className="p-3.5 text-center">Half Days</th>
                  <th className="p-3.5 text-center">Absent Days</th>
                  <th className="p-3.5 text-center">Weekly Offs</th>
                  <th className="p-3.5 text-center">Late Incidents</th>
                  <th className="p-3.5 text-center">Total Work Hours</th>
                  <th className="p-3.5 text-center">Attendance %</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {matrixData.employees.map(emp => (
                  <tr key={emp.id} className="hover:bg-slate-50">
                    <td className="p-3.5 font-mono text-slate-600">{emp.id}</td>
                    <td className="p-3.5 font-semibold text-slate-800">{emp.name}</td>
                    <td className="p-3.5 text-slate-600">{emp.department}</td>
                    <td className="p-3.5 text-center font-semibold text-emerald-600">{emp.totals.present}</td>
                    <td className="p-3.5 text-center font-semibold text-yellow-600">{emp.totals.half_day}</td>
                    <td className="p-3.5 text-center font-semibold text-rose-600">{emp.totals.absent}</td>
                    <td className="p-3.5 text-center text-slate-500">{emp.totals.weekly_off}</td>
                    <td className="p-3.5 text-center font-semibold text-amber-600">{emp.totals.late_count}</td>
                    <td className="p-3.5 text-center font-mono font-bold text-slate-800">{emp.totals.total_hours} hrs</td>
                    <td className="p-3.5 text-center">
                      <span className="font-bold text-slate-800">{emp.totals.attendance_rate}%</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
