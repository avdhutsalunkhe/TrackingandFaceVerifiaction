import React, { useState, useEffect } from 'react';
import { useTimeOffice } from '../context/TimeOfficeContext';
import { api } from '../services/api';
import { ShiftMonitoringItem } from '../types';
import { ExportButtons } from '../components/common/ExportButtons';
import { 
  Layers, 
  Clock, 
  Timer
} from 'lucide-react';

export const ShiftMonitoringScreen: React.FC = () => {
  const { selectedDate, refreshKey } = useTimeOffice();
  const [shifts, setShifts] = useState<ShiftMonitoringItem[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [serverTime, setServerTime] = useState<string>('--:--:--');

  const dateToUse = selectedDate || new Date().toISOString().slice(0, 10);

  useEffect(() => {
    let isMounted = true;
    setLoading(true);

    api.getShiftMonitoring(dateToUse)
      .then((res) => {
        if (isMounted) {
          const shiftList = Array.isArray(res?.shifts) ? res.shifts : (Array.isArray(res) ? res : []);
          setShifts(shiftList);
          setServerTime(res.server_time || '--:--:--');
          setLoading(false);
        }
      })
      .catch((err) => {
        console.error('[ShiftMonitoring] Fetch error:', err);
        if (isMounted) setLoading(false);
      });

    return () => {
      isMounted = false;
    };
  }, [dateToUse, refreshKey]);

  return (
    <div className="p-6 space-y-5 bg-[#090d16] min-h-screen text-slate-200">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-[#111622] p-5 rounded-2xl border border-[#1e2638] shadow-lg">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2.5 tracking-tight">
            <Layers className="w-6 h-6 text-[#f95700]" />
            <span>Dynamic Shift Monitoring & Verification Window Status</span>
          </h2>
          <p className="text-xs text-slate-400 mt-1">
            Loaded dynamically from database shift rules for date ({dateToUse})
          </p>
        </div>

        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-[#0c1018] border border-[#242f48] text-xs font-mono text-white">
            <Timer className="w-4 h-4 text-[#f95700]" />
            <span>Server Clock: {serverTime}</span>
          </div>

          <ExportButtons
            data={shifts.flatMap((s) =>
              s.punch_periods.map((p) => ({
                'Shift Code': s.shift_code,
                'Shift Name': s.shift_name,
                'Total Employees': s.total_employees,
                'Punch No': p.punch_no,
                'Period Name': p.period_name,
                'Window Start': p.start_time,
                'Window End': p.end_time,
                'Window State': p.state,
                'Completed Count': p.completed_count,
                'Remaining Count': p.remaining_count,
                'Completion Rate (%)': `${p.completion_rate}%`
              }))
            )}
            fileName={`Shift_Monitoring_${selectedDate}`}
          />
        </div>
      </div>

      {loading ? (
        <div className="p-16 text-center text-xs font-mono text-slate-400 bg-[#111622] border border-[#1e2638] rounded-2xl">
          <div className="w-7 h-7 border-2 border-[#f95700] border-t-transparent rounded-full animate-spin mx-auto mb-3" />
          Loading dynamic shift configurations...
        </div>
      ) : shifts.length === 0 ? (
        <div className="p-12 text-center text-sm font-semibold text-slate-300 bg-[#111622] border border-[#1e2638] rounded-2xl shadow-md">
          No active shifts or employee assignments defined in the database for this date.
        </div>
      ) : (
        <div className="space-y-4">
          {shifts.map((shift) => (
            <div
              key={shift.shift_id}
              className="bg-[#111622] border border-[#1e2638] rounded-2xl overflow-hidden shadow-lg"
            >
              {/* Shift Banner */}
              <div className="px-5 py-4 bg-[#0c1018] border-b border-[#1e2638] flex items-center justify-between">
                <div className="flex items-center gap-3.5">
                  <div className="w-9 h-9 rounded-xl bg-[#f95700]/10 border border-[#f95700]/30 flex items-center justify-center text-[#f95700] font-bold font-mono text-xs">
                    {shift.shift_code}
                  </div>
                  <div>
                    <h3 className="text-sm font-bold text-white">{shift.shift_name}</h3>
                    <div className="text-xs text-slate-400 font-mono mt-0.5">
                      Shift Code: <span className="text-slate-200 font-semibold">{shift.shift_code}</span> | Active Employees: <strong className="text-[#f95700]">{shift.total_employees}</strong>
                    </div>
                  </div>
                </div>

                <div className="text-right">
                  <span className="text-xs font-mono text-slate-400">
                    Defined Periods: <strong className="text-white">{shift.punch_periods.length}</strong>
                  </span>
                </div>
              </div>

              {/* Punch Periods Grid */}
              <div className="p-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
                {shift.punch_periods.map((period) => {
                  const isActiveNow = period.state === 'ACTIVE_NOW';
                  const isClosed = period.state === 'CLOSED';

                  return (
                    <div
                      key={period.punch_no}
                      className={`border rounded-xl p-4 flex flex-col justify-between transition-all ${
                        isActiveNow
                          ? 'bg-blue-500/10 border-blue-500/40 shadow-md ring-1 ring-blue-500/30'
                          : isClosed
                          ? 'bg-[#0c1018] border-slate-800/80'
                          : 'bg-[#0c1018] border-slate-800'
                      }`}
                    >
                      <div>
                        <div className="flex items-center justify-between mb-2">
                          <span className="text-xs font-bold text-white flex items-center gap-1.5">
                            <span>Punch #{period.punch_no}</span>
                            <span className="text-[10px] text-slate-400 font-normal">({period.period_name})</span>
                          </span>

                          <span
                            className={`text-[10px] px-2.5 py-0.5 rounded-full font-mono font-bold uppercase ${
                              isActiveNow
                                ? 'bg-blue-500/20 text-blue-300 border border-blue-500/40 animate-pulse'
                                : isClosed
                                ? 'bg-slate-800 text-slate-400 border border-slate-700'
                                : 'bg-amber-500/15 text-amber-300 border border-amber-500/30'
                            }`}
                          >
                            {isActiveNow ? 'ACTIVE NOW' : period.state}
                          </span>
                        </div>

                        <div className="text-xs text-slate-300 font-mono mb-3 flex items-center gap-1.5">
                          <Clock className="w-3.5 h-3.5 text-[#f95700]" />
                          <span>{period.start_time} — {period.end_time}</span>
                        </div>

                        {/* Progress Bar */}
                        <div className="w-full bg-slate-800 h-2 rounded-full overflow-hidden mb-3">
                          <div
                            className={`h-full rounded-full transition-all duration-300 ${
                              isActiveNow ? 'bg-[#f95700]' : isClosed ? 'bg-emerald-500' : 'bg-slate-600'
                            }`}
                            style={{ width: `${Math.min(100, period.completion_rate)}%` }}
                          />
                        </div>
                      </div>

                      <div className="flex items-center justify-between text-[11px] font-mono pt-2 border-t border-slate-800/80">
                        <span className="text-slate-400">
                          Completed: <strong className="text-emerald-400">{period.completed_count}</strong> / {shift.total_employees}
                        </span>
                        <span className="text-[#f95700] font-bold">{period.completion_rate}%</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default ShiftMonitoringScreen;
