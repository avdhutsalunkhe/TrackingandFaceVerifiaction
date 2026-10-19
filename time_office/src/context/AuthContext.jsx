import React, { createContext, useContext, useState, useEffect } from 'react';
import axios from 'axios';
import { API_BASE } from '../api/client';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [currentUser, setCurrentUser] = useState(() => {
    try {
      const saved = localStorage.getItem('report_auth_user') || localStorage.getItem('hrreport_auth_user');
      return saved ? JSON.parse(saved) : null;
    } catch {
      return null;
    }
  });
  const [token, setToken] = useState(() => {
    return localStorage.getItem('report_auth_token') || localStorage.getItem('hrreport_auth_token') || null;
  });

  const login = async (username, password) => {
    try {
      const res = await axios.post(`${API_BASE}/auth/login`, {
        username: username.trim(),
        password: password.trim()
      });

      if (res.data && res.data.success) {
        const user = res.data.user;
        const tok = res.data.token;
        setCurrentUser(user);
        setToken(tok);
        localStorage.setItem('report_auth_user', JSON.stringify(user));
        localStorage.setItem('report_auth_token', tok);
        return { 
          success: true, 
          user,
          password_expired: res.data.password_expired,
          days_until_expiration: res.data.days_until_expiration,
          must_reset_password: res.data.must_reset_password
        };
      }
      return { success: false, error: 'Login failed' };
    } catch (err) {
      const msg = err.response?.data?.detail || err.message || 'Authentication failed';
      return { success: false, error: msg };
    }
  };

  const updateCurrentUser = (updatedUser) => {
    setCurrentUser(updatedUser);
    localStorage.setItem('report_auth_user', JSON.stringify(updatedUser));
  };

  const logout = () => {
    setCurrentUser(null);
    setToken(null);
    localStorage.removeItem('report_auth_user');
    localStorage.removeItem('report_auth_token');
    localStorage.removeItem('hrreport_auth_user');
    localStorage.removeItem('hrreport_auth_token');
  };

  const isAdmin = currentUser?.role === 'admin';
  const isClerk = currentUser?.role === 'clerk';

  return (
    <AuthContext.Provider
      value={{
        currentUser,
        token,
        login,
        logout,
        updateCurrentUser,
        isAuthenticated: !!currentUser,
        isAdmin,
        isClerk
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}


export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
