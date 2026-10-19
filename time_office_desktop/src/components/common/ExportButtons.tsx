import React from 'react';
import * as XLSX from 'xlsx';
import { FileSpreadsheet, FileText, ChevronDown } from 'lucide-react';

interface ExportButtonsProps {
  data: any[];
  headers?: string[];
  fileName?: string;
  className?: string;
}

export const ExportButtons: React.FC<ExportButtonsProps> = ({
  data,
  headers,
  fileName = 'TimeOffice_Export',
  className = '',
}) => {
  const getWorksheet = () => {
    if ((!data || data.length === 0) && headers && headers.length > 0) {
      return XLSX.utils.json_to_sheet([], { header: headers });
    }
    if (!data || data.length === 0) {
      return null;
    }
    return XLSX.utils.json_to_sheet(data);
  };

  const exportToExcel = () => {
    const worksheet = getWorksheet();
    if (!worksheet) {
      alert('No data to export.');
      return;
    }
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Attendance');
    XLSX.writeFile(workbook, `${fileName}.xlsx`);
  };

  const exportToCSV = () => {
    const worksheet = getWorksheet();
    if (!worksheet) {
      alert('No data to export.');
      return;
    }
    const csvOutput = XLSX.utils.sheet_to_csv(worksheet);
    const blob = new Blob([csvOutput], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${fileName}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className={`inline-flex items-center gap-2.5 ${className}`}>
      {/* Green Excel Button matching screenshot */}
      <button
        onClick={exportToExcel}
        title="Export to Excel (.xlsx)"
        className="px-3.5 py-1.5 text-xs font-bold text-emerald-700 bg-white hover:bg-emerald-50 border border-emerald-500/80 rounded-lg inline-flex items-center gap-1.5 shadow-sm transition-colors cursor-pointer"
      >
        <FileSpreadsheet className="w-4 h-4 text-emerald-600 shrink-0" />
        <span>Export Excel</span>
        <ChevronDown className="w-3.5 h-3.5 text-emerald-600 ml-0.5" />
      </button>

      {/* Blue CSV Button matching screenshot */}
      <button
        onClick={exportToCSV}
        title="Export to CSV"
        className="px-3.5 py-1.5 text-xs font-bold text-blue-700 bg-white hover:bg-blue-50 border border-blue-500/80 rounded-lg inline-flex items-center gap-1.5 shadow-sm transition-colors cursor-pointer"
      >
        <FileText className="w-4 h-4 text-blue-600 shrink-0" />
        <span>Export CSV</span>
        <ChevronDown className="w-3.5 h-3.5 text-blue-600 ml-0.5" />
      </button>
    </div>
  );
};

