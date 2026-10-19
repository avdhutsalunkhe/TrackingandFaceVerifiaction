import axios from 'axios';

// Public/Default Backend address specified by user
export const DEFAULT_HOST = '182.66.233.66';
export const DEFAULT_PORT = '8073';
export const DEFAULT_BACKEND_URL = `http://${DEFAULT_HOST}:${DEFAULT_PORT}`;

// Load user override if customized in desktop or localStorage
const getSavedBackendUrl = () => {
  if (typeof window !== 'undefined' && window.localStorage) {
    const saved = localStorage.getItem('report_backend_url') || localStorage.getItem('hrreport_backend_url');
    if (saved && saved.trim()) return saved.trim();
  }
  return import.meta.env.VITE_BACKEND_URL || DEFAULT_BACKEND_URL;
};

export let BACKEND_URL = getSavedBackendUrl();
export let API_BASE = `${BACKEND_URL}/api`;

export function setBackendUrl(newUrl) {
  if (!newUrl) return;
  const cleaned = newUrl.replace(/\/+$/, '');
  BACKEND_URL = cleaned;
  API_BASE = `${cleaned}/api`;
  if (typeof window !== 'undefined' && window.localStorage) {
    localStorage.setItem('report_backend_url', cleaned);
  }
  apiClient.defaults.baseURL = API_BASE;
}

export const apiClient = axios.create({
  baseURL: API_BASE,
  timeout: 15000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Update apiClient baseURL if BACKEND_URL changes
apiClient.interceptors.request.use((config) => {
  if (!config.baseURL || config.baseURL.startsWith('/')) {
    config.baseURL = API_BASE;
  }
  return config;
});

/**
 * Robust ping that attempts connection to the configured backend.
 * If 182.66.233.66 is not reachable from the local machine (due to lack of NAT loopback on router),
 * it tests local interfaces (127.0.0.1:8073, 192.168.1.93:8073) and offers seamless fallback.
 */
export async function pingBackend() {
  const currentUrl = BACKEND_URL;

  // 1. First attempt: configured URL (default 182.66.233.66:8073)
  try {
    const res = await axios.get(`${currentUrl}/api/health`, { timeout: 3500 });
    return { ok: true, url: currentUrl, data: res.data };
  } catch (err1) {
    // 2. If running locally and router doesn't route public IP back to local machine, try local loopback
    const localCandidates = [
      `http://127.0.0.1:${DEFAULT_PORT}`,
      `http://localhost:${DEFAULT_PORT}`,
      `http://192.168.1.93:${DEFAULT_PORT}`
    ];

    for (const altUrl of localCandidates) {
      if (altUrl === currentUrl) continue;
      try {
        const altRes = await axios.get(`${altUrl}/api/health`, { timeout: 1500 });
        if (altRes.data && altRes.data.status === 'operational') {
          // Local fallback succeeded!
          return {
            ok: true,
            url: altUrl,
            fallbackNotice: `Connected via local route (${altUrl}). Public IP (${currentUrl}) may require NAT loopback or external network.`,
            data: altRes.data
          };
        }
      } catch (altErr) {
        // continue
      }
    }

    return {
      ok: false,
      url: currentUrl,
      error: err1.message || 'Server unreachable'
    };
  }
}

export default apiClient;
