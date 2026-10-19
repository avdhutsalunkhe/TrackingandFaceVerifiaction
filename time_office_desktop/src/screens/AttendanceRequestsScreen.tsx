import React, { useState, useEffect } from 'react';
import { useTimeOffice } from '../context/TimeOfficeContext';
import { api } from '../services/api';
import { AttendanceRequestItem } from '../types';
import { StatusBadge } from '../components/common/Badge';
import { Modal } from '../components/common/Modal';
import { ExportButtons } from '../components/common/ExportButtons';
import { 
  FileClock, 
  Search, 
  CheckCircle2, 
  XCircle, 
  Image, 
  ChevronLeft, 
  ChevronRight
} from 'lucide-react';

export const AttendanceRequestsScreen: React.FC = () => {
  const { selectedDate, refreshKey, triggerRefresh } = useTimeOffice();
  const [requests, setRequests] = useState<AttendanceRequestItem[]>([]);
  const [total, setTotal] = useState<number>(0);
  const [loading, setLoading] = useState<boolean>(true);
  const [statusFilter, setStatusFilter] = useState<string>('PENDING');
  const [search, setSearch] = useState<string>('');
  const [page, setPage] = useState<number>(1);
  const pageSize = 50;

  // Selected request for image preview or review action
  const [previewRequest, setPreviewRequest] = useState<AttendanceRequestItem | null>(null);
  const [reviewAction, setReviewAction] = useState<{ req: AttendanceRequestItem; type: 'APPROVE' | 'REJECT' } | null>(null);
  const [reviewNotes, setReviewNotes] = useState<string>('');
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);

  useEffect(() => {
    let isMounted = true;
    setLoading(true);

    api.getRequests({
      date: selectedDate,
      status_filter: statusFilter || undefined,
      search: search.trim() || undefined,
      page,
      page_size: pageSize,
    })
      .then((res) => {
        if (isMounted) {
          setRequests(res.records || []);
          setTotal(res.total || 0);
          setLoading(false);
        }
      })
      .catch((err) => {
        console.error('[Requests] Error:', err);
        if (isMounted) setLoading(false);
      });

    return () => {
      isMounted = false;
    };
  }, [selectedDate, statusFilter, search, page, refreshKey]);

  const handleReviewSubmit = async () => {
    if (!reviewAction) return;
    setIsSubmitting(true);
    try {
      if (reviewAction.type === 'APPROVE') {
        await api.approveRequest(reviewAction.req.id, reviewNotes);
      } else {
        await api.rejectRequest(reviewAction.req.id, reviewNotes);
      }
      setReviewAction(null);
      setReviewNotes('');
      triggerRefresh();
    } catch (err: any) {
      alert(`Action failed: ${err.response?.data?.detail || err.message}`);
    } finally {
      setIsSubmitting(false);
    }
  };

  const totalPages = Math.ceil(total / pageSize) || 1;

  return (
    <div className="p-6 space-y-5 bg-[#090d16] min-h-screen text-slate-200">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-[#111622] p-5 rounded-2xl border border-[#1e2638] shadow-lg">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2.5 tracking-tight">
            <FileClock className="w-6 h-6 text-blue-400" />
            <span>Attendance Requests & Fallback Verification Review</span>
          </h2>
          <p className="text-xs text-slate-400 mt-1">
            Audit fallback selfie requests, verify GPS bounding and approve/reject with controlled operator logs
          </p>
        </div>

        <ExportButtons
          data={requests.map((r) => ({
            'Request ID': r.id,
            'Employee ID': r.employee_id,
            'Employee Name': r.full_name,
            'Date': r.request_date,
            'Punch #': r.verification_no,
            'Server Timestamp': r.server_timestamp,
            'Status': r.status,
            'Trigger Reason': r.rejection_trigger || '--',
            'Location': r.location_name,
            'Distance (m)': r.distance_meters,
            'Admin Notes': r.admin_notes || '--',
            'Reviewed By': r.reviewed_by || '--',
            'Reviewed At': r.reviewed_at || '--'
          }))}
          fileName={`Attendance_Requests_${selectedDate}`}
        />
      </div>

      {/* Filter Bar */}
      <div className="flex flex-wrap items-center justify-between gap-3 bg-[#111622] p-4 rounded-xl border border-[#1e2638] text-xs shadow-md">
        <div className="flex flex-wrap items-center gap-3 flex-1 min-w-[280px]">
          {/* Search box */}
          <div className="relative flex-1 max-w-sm">
            <Search className="w-4 h-4 text-slate-500 absolute left-3 top-2.5" />
            <input
              type="text"
              placeholder="Search by Employee ID or Name..."
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setPage(1);
              }}
              className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl pl-9 pr-3 py-2 text-xs font-medium text-white placeholder-slate-500 focus:outline-none focus:border-[#f95700]"
            />
          </div>

          {/* Status filter */}
          <select
            value={statusFilter}
            onChange={(e) => {
              setStatusFilter(e.target.value);
              setPage(1);
            }}
            className="bg-[#0c1018] border border-[#242f48] rounded-xl px-3 py-2 text-xs font-medium text-white focus:outline-none focus:border-[#f95700]"
          >
            <option value="">All Statuses</option>
            <option value="PENDING">PENDING REVIEW</option>
            <option value="APPROVED">APPROVED</option>
            <option value="REJECTED">REJECTED</option>
          </select>
        </div>

        {/* Counter & Pagination controls */}
        <div className="flex items-center gap-3">
          <span className="text-slate-400 font-mono text-xs">
            Requests: <strong className="text-white">{total}</strong>
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
                <th>Req ID</th>
                <th>Emp ID</th>
                <th>Employee Name</th>
                <th>Date</th>
                <th>Punch #</th>
                <th>Server Timestamp</th>
                <th>Trigger Reason</th>
                <th>Distance</th>
                <th>Status</th>
                <th>Evidence Image</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={11} className="text-center py-16 text-slate-400 text-xs font-mono">
                    <div className="w-7 h-7 border-2 border-[#f95700] border-t-transparent rounded-full animate-spin mx-auto mb-3" />
                    Loading attendance requests...
                  </td>
                </tr>
              ) : requests.length === 0 ? (
                <tr>
                  <td colSpan={11} className="text-center py-16 text-slate-400 text-xs">
                    No attendance fallback requests found matching filters.
                  </td>
                </tr>
              ) : (
                requests.map((req) => (
                  <tr key={req.id}>
                    <td className="font-mono text-slate-400">#{req.id}</td>
                    <td className="font-mono font-bold text-[#f95700]">{req.employee_id}</td>
                    <td className="font-semibold text-white">{req.full_name}</td>
                    <td className="font-mono text-slate-300">{req.request_date}</td>
                    <td className="font-mono text-slate-400 text-center">#{req.verification_no}</td>
                    <td className="font-mono text-slate-400">{req.server_timestamp}</td>
                    <td className="font-mono text-rose-400 text-[11px]">{req.rejection_trigger || 'FALLBACK_PUNCH'}</td>
                    <td className="font-mono text-slate-300">{req.distance_meters !== undefined && req.distance_meters !== null ? `${req.distance_meters}m` : '--'}</td>
                    <td>
                      <StatusBadge status={req.status} />
                    </td>
                    <td>
                      {req.has_image ? (
                        <button
                          onClick={() => setPreviewRequest(req)}
                          className="px-2.5 py-1 text-xs rounded-lg bg-blue-500/15 text-blue-400 border border-blue-500/30 flex items-center gap-1.5 font-semibold transition-colors"
                        >
                          <Image className="w-3.5 h-3.5" />
                          View Image
                        </button>
                      ) : (
                        <span className="text-slate-500 text-xs font-mono">No Image</span>
                      )}
                    </td>
                    <td>
                      {req.status === 'PENDING' ? (
                        <div className="flex items-center gap-2">
                          <button
                            onClick={() => setReviewAction({ req, type: 'APPROVE' })}
                            className="px-2.5 py-1 text-xs rounded-lg bg-emerald-500/15 hover:bg-emerald-500/25 text-emerald-400 border border-emerald-500/30 flex items-center gap-1 font-bold transition-colors"
                          >
                            <CheckCircle2 className="w-3.5 h-3.5" />
                            Approve
                          </button>
                          <button
                            onClick={() => setReviewAction({ req, type: 'REJECT' })}
                            className="px-2.5 py-1 text-xs rounded-lg bg-rose-500/15 hover:bg-rose-500/25 text-rose-400 border border-rose-500/30 flex items-center gap-1 font-bold transition-colors"
                          >
                            <XCircle className="w-3.5 h-3.5" />
                            Reject
                          </button>
                        </div>
                      ) : (
                        <span className="text-slate-400 text-xs font-mono">{req.reviewed_by ? `By ${req.reviewed_by}` : 'Processed'}</span>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Image Preview Modal */}
      {previewRequest && (
        <Modal
          isOpen={!!previewRequest}
          onClose={() => setPreviewRequest(null)}
          title={`Evidence Selfie: ${previewRequest.full_name} (${previewRequest.employee_id})`}
        >
          <div className="space-y-4">
            <div className="rounded-xl overflow-hidden border border-[#242f48] bg-[#0c1018] flex items-center justify-center p-2 min-h-[280px]">
              <img
                src={api.getRequestImageUrl(previewRequest.id)}
                alt="Request Verification Selfie"
                className="max-h-[380px] object-contain rounded-lg shadow-md"
                onError={(e) => {
                  (e.target as HTMLElement).style.display = 'none';
                }}
              />
            </div>
            <div className="text-xs font-mono text-slate-300 space-y-1 bg-[#0c1018] p-3 rounded-xl border border-slate-800">
              <div>Request ID: <span className="text-white font-bold">#{previewRequest.id}</span></div>
              <div>Punch Window: <span className="text-white font-bold">#{previewRequest.verification_no}</span></div>
              <div>Server Timestamp: <span className="text-slate-400">{previewRequest.server_timestamp}</span></div>
            </div>
          </div>
        </Modal>
      )}

      {/* Review Confirmation Modal */}
      {reviewAction && (
        <Modal
          isOpen={!!reviewAction}
          onClose={() => setReviewAction(null)}
          title={`${reviewAction.type === 'APPROVE' ? 'Approve' : 'Reject'} Attendance Request #${reviewAction.req.id}`}
        >
          <div className="space-y-4">
            <p className="text-xs text-slate-300">
              Are you sure you want to <strong className={reviewAction.type === 'APPROVE' ? 'text-emerald-400' : 'text-rose-400'}>{reviewAction.type.toLowerCase()}</strong> the fallback attendance request for employee <strong className="text-white">{reviewAction.req.full_name}</strong> ({reviewAction.req.employee_id})?
            </p>

            <div>
              <label className="block text-xs font-semibold text-slate-300 mb-1">
                Admin Review Notes (Optional)
              </label>
              <textarea
                rows={3}
                placeholder="e.g. Verified selfie against identity card / approved by supervisor"
                value={reviewNotes}
                onChange={(e) => setReviewNotes(e.target.value)}
                className="w-full bg-[#0c1018] border border-[#242f48] rounded-xl p-3 text-xs text-white placeholder-slate-500 focus:border-[#f95700] focus:outline-none"
              />
            </div>

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                onClick={() => setReviewAction(null)}
                className="px-4 py-2 bg-slate-800 text-slate-300 text-xs font-semibold rounded-xl"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleReviewSubmit}
                disabled={isSubmitting}
                className={`px-4 py-2 text-xs font-bold text-white rounded-xl shadow-md transition-all ${
                  reviewAction.type === 'APPROVE' ? 'bg-emerald-600 hover:bg-emerald-500' : 'bg-rose-600 hover:bg-rose-500'
                }`}
              >
                {isSubmitting ? 'Submitting...' : `Confirm ${reviewAction.type}`}
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default AttendanceRequestsScreen;
