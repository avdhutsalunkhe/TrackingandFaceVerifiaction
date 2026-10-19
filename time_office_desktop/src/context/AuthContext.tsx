import React, { createContext, useContext, useState, useEffect } from 'react';
import { User } from '../types';
import { api } from '../services/api';

interface AuthContextType {
  user: User | null;
  token: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
  login: (employeeId: string, password: string) => Promise<boolean>;
  logout: () => void;
  clearError: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [token, setToken] = useState<string | null>(localStorage.getItem('time_office_token'));
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const initializeAuth = async () => {
      const storedToken = localStorage.getItem('time_office_token');
      if (storedToken) {
        try {
          const profile = await api.getMe();
          if (profile.role === 'TIME_OFFICE' || profile.role === 'ADMIN') {
            setUser(profile);
            setToken(storedToken);
          } else {
            console.warn('[Auth] Non-authorized role attempted access:', profile.role);
            logout();
            setError('Access Denied: Time Office or Administrator role required.');
          }
        } catch (err: any) {
          console.error('[Auth] Token verification failed:', err);
          logout();
        }
      }
      setIsLoading(false);
    };

    initializeAuth();
  }, []);

  const login = async (employeeId: string, password: string): Promise<boolean> => {
    setIsLoading(true);
    setError(null);
    try {
      const res = await api.login(employeeId.trim(), password);
      if (!res.access_token) {
        setError('Login failed: Token not received from server');
        setIsLoading(false);
        return false;
      }

      const receivedToken = res.access_token;
      localStorage.setItem('time_office_token', receivedToken);
      setToken(receivedToken);

      // Verify user permissions
      const profile = await api.getMe();
      if (profile.role !== 'TIME_OFFICE' && profile.role !== 'ADMIN') {
        logout();
        setError(`Access Denied: Account '${profile.employee_id}' has role '${profile.role}'. Only TIME_OFFICE or ADMIN roles may access this console.`);
        setIsLoading(false);
        return false;
      }

      if (!profile.is_active) {
        logout();
        setError('Account is deactivated. Please contact system administrator.');
        setIsLoading(false);
        return false;
      }

      setUser(profile);
      setIsLoading(false);
      return true;
    } catch (err: any) {
      console.error('[Auth] Login error:', err);
      const detail = err.response?.data?.detail || err.message || 'Login failed. Please check backend connection.';
      setError(detail);
      setIsLoading(false);
      return false;
    }
  };

  const logout = () => {
    localStorage.removeItem('time_office_token');
    setToken(null);
    setUser(null);
  };

  const clearError = () => setError(null);

  return (
    <AuthContext.Provider
      value={{
        user,
        token,
        isAuthenticated: !!user && !!token,
        isLoading,
        error,
        login,
        logout,
        clearError,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
