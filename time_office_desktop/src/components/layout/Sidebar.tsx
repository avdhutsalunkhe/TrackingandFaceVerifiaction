import React, { useState } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import {
  MapPin,
  LayoutDashboard,
  Clock,
  BarChart3,
  Database,
  Settings,
  LogOut,
  ChevronDown,
  Menu,
  Building2
} from 'lucide-react';

interface SubNavItem {
  name: string;
  path: string;
}

interface NavGroup {
  name: string;
  icon: React.ElementType;
  path?: string;
  children?: SubNavItem[];
}

export const Sidebar: React.FC = () => {
  const { logout } = useAuth();
  const location = useLocation();

  // Collapsed state for high-density PC screens
  const [isCollapsed, setIsCollapsed] = useState<boolean>(() => {
    return localStorage.getItem('time_office_sidebar_collapsed') === 'true';
  });

  const toggleCollapse = () => {
    setIsCollapsed((prev) => {
      const next = !prev;
      localStorage.setItem('time_office_sidebar_collapsed', String(next));
      return next;
    });
  };

  // Track expanded accordion sections
  const [openSections, setOpenSections] = useState<Record<string, boolean>>({
    Attendance: true,
    Reports: false,
    MasterData: false,
    Settings: false,
  });

  const toggleSection = (name: string) => {
    if (isCollapsed) {
      setIsCollapsed(false);
      localStorage.setItem('time_office_sidebar_collapsed', 'false');
    }
    setOpenSections((prev) => ({ ...prev, [name]: !prev[name] }));
  };

  const navGroups: NavGroup[] = [
    {
      name: 'Travel Route Map',
      icon: MapPin,
      path: '/travel-map',
    },
    {
      name: 'Dashboard',
      icon: LayoutDashboard,
      path: '/',
    },
    {
      name: 'Attendance',
      icon: Clock,
      children: [
        { name: "Today's Attendance", path: '/attendance' },
        { name: 'Present', path: '/present' },
        { name: 'Late', path: '/late' },
        { name: 'Not Marked', path: '/not-marked' },
      ],
    },
    {
      name: 'Reports',
      icon: BarChart3,
      children: [
        { name: 'Daily Roll-Up Attendance', path: '/reports?type=roll_up' },
        { name: 'Shift-Wise Attendance Summary', path: '/reports?type=shift_summary' },
        { name: 'Daily Attendance Register', path: '/reports?type=daily' },
        { name: 'Present Employees', path: '/reports?type=present' },
        { name: 'Present Report – 1st Punch', path: '/reports?type=present_first_punch' },
        { name: 'Absent Report – 1st Punch', path: '/reports?type=absent_first_punch' },
        { name: 'Full-Day Absent – Dept-wise', path: '/reports?type=full_day_absent' },
        { name: 'Late Report – 1st Punch', path: '/reports?type=late' },
        { name: 'Not Marked / Absenteeism Risk', path: '/reports?type=not_marked' },
        { name: 'Shift Monitoring & Period Progress', path: '/reports?type=shift_monitoring' },
        { name: 'Employee-wise Monthly Summary', path: '/reports?type=monthly_summary' },
        { name: 'Holiday / Weekly-Off', path: '/reports?type=holiday_weekly_off' },
        { name: 'Extra Work', path: '/reports?type=extra_work' },
        { name: 'Multi-Location Punch', path: '/reports?type=multi_location' },
        { name: 'Biometric Verification Attempts', path: '/reports?type=biometric_attempts' },
        { name: 'Attendance Exceptions & Requests', path: '/reports?type=requests' },
        { name: 'System Audit Log', path: '/reports?type=audit_log' },
        { name: 'Employee Master Directory', path: '/reports?type=employee_directory' },
      ],
    },
    {
      name: 'Master Data',
      icon: Database,
      children: [
        { name: 'Shift Rules', path: '/shift-rules' },
        { name: 'Departments', path: '/departments' },
        { name: 'Roles & Access Control', path: '/roles' },
      ],
    },
    {
      name: 'Settings',
      icon: Settings,
      children: [
        { name: 'System Settings', path: '/settings' },
      ],
    },
  ];

  return (
    <aside
      className={`${
        isCollapsed ? 'w-20' : 'w-64'
      } bg-[#111622] text-slate-300 border-r border-[#1e2638] flex flex-col justify-between shrink-0 select-none shadow-lg transition-all duration-300 ease-in-out z-20`}
    >
      {/* Top Branding Section */}
      <div>
        <div className="h-16 px-4 flex items-center justify-between border-b border-[#1e2638]">
          <div className="flex items-center gap-3 overflow-hidden">
            {/* Orange Logo Icon */}
            <div className="w-9 h-9 shrink-0 rounded-xl bg-gradient-to-br from-[#f95700] to-[#ea4e00] flex items-center justify-center text-white shadow-md shadow-orange-500/20">
              <Building2 className="w-5 h-5 stroke-[2.5]" />
            </div>
            {!isCollapsed && (
              <div className="transition-opacity duration-200">
                <div className="text-sm font-bold text-white leading-tight tracking-tight">
                  FieldStaff
                </div>
                <div className="text-[11px] text-slate-400 font-medium leading-none mt-0.5">
                  Time Office
                </div>
              </div>
            )}
          </div>
          <button 
            onClick={toggleCollapse}
            className="p-1.5 text-slate-400 hover:text-white hover:bg-slate-800/60 rounded-lg transition-colors"
            title={isCollapsed ? 'Expand Sidebar' : 'Collapse Sidebar'}
          >
            <Menu className="w-4 h-4" />
          </button>
        </div>

        {/* Navigation Items */}
        <div className="p-3 space-y-1.5 overflow-y-auto max-h-[calc(100vh-130px)]">
          {navGroups.map((group) => {
            const Icon = group.icon;
            const hasChildren = Boolean(group.children && group.children.length > 0);

            // Check if group is currently active
            const isGroupActive = hasChildren
              ? group.children?.some(
                  (child) =>
                    location.pathname + location.search === child.path ||
                    (child.path.includes('/reports') && location.pathname === '/reports' && (
                      (child.path.includes('present_first_punch') && location.search.includes('present_first_punch')) ||
                      (child.path.includes('absent_first_punch') && location.search.includes('absent_first_punch')) ||
                      (child.path.includes('daily') && (location.search === '' || location.search.includes('daily')))
                    ))
                )
              : location.pathname === group.path;

            const isOpen = openSections[group.name] ?? false;

            if (!hasChildren && group.path) {
              return (
                <NavLink
                  key={group.name}
                  to={group.path}
                  title={isCollapsed ? group.name : undefined}
                  className={({ isActive }) =>
                    `flex items-center ${
                      isCollapsed ? 'justify-center px-2' : 'gap-3 px-3'
                    } py-2.5 rounded-lg text-xs font-semibold transition-all ${
                      isActive
                        ? 'bg-[#f95700] text-white shadow-md shadow-orange-500/20'
                        : 'text-slate-300 hover:bg-slate-800/60 hover:text-white'
                    }`
                  }
                >
                  <Icon className="w-4 h-4 shrink-0" />
                  {!isCollapsed && <span className="truncate">{group.name}</span>}
                </NavLink>
              );
            }

            return (
              <div key={group.name} className="space-y-1 group/accordion relative">
                {/* Accordion Parent Item */}
                <button
                  onClick={() => toggleSection(group.name)}
                  title={isCollapsed ? group.name : undefined}
                  className={`w-full flex items-center ${
                    isCollapsed ? 'justify-center px-2' : 'justify-between px-3'
                  } py-2.5 rounded-lg text-xs font-semibold transition-all ${
                    isGroupActive
                      ? 'bg-[#f95700] text-white shadow-md shadow-orange-500/20'
                      : 'text-slate-300 hover:bg-slate-800/60 hover:text-white'
                  }`}
                >
                  <div className="flex items-center gap-3 overflow-hidden">
                    <Icon className="w-4 h-4 shrink-0" />
                    {!isCollapsed && <span className="truncate">{group.name}</span>}
                  </div>
                  {!isCollapsed && (
                    <ChevronDown
                      className={`w-3.5 h-3.5 transition-transform duration-200 shrink-0 ${
                        isOpen ? 'rotate-180' : ''
                      }`}
                    />
                  )}
                </button>

                {/* Sub Items List (Expanded) */}
                {!isCollapsed && isOpen && group.children && (
                  <div className="pl-4 pr-1 py-1 space-y-0.5 relative before:absolute before:left-5 before:top-2 before:bottom-2 before:w-[1px] before:bg-slate-800">
                    {group.children.map((child) => {
                      const isSubActive =
                        location.pathname + location.search === child.path ||
                        (child.path.includes('present_first_punch') && location.search.includes('present_first_punch')) ||
                        (child.path.includes('absent_first_punch') && location.search.includes('absent_first_punch')) ||
                        (child.path.includes('type=daily') && location.pathname === '/reports' && (location.search === '' || location.search.includes('daily')));

                      return (
                        <NavLink
                          key={child.name}
                          to={child.path}
                          className={`flex items-center gap-2.5 px-3 py-2 rounded-md text-xs transition-colors relative ${
                            isSubActive
                              ? 'text-[#f95700] font-semibold bg-orange-500/10'
                              : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/40 font-normal'
                          }`}
                        >
                          <span
                            className={`w-1.5 h-1.5 rounded-full shrink-0 ${
                              isSubActive ? 'bg-[#f95700]' : 'bg-slate-600'
                            }`}
                          />
                          <span className="truncate">{child.name}</span>
                        </NavLink>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* Bottom Logout Button */}
      <div className="p-3 border-t border-[#1e2638] bg-[#0c1018]">
        <button
          onClick={logout}
          title={isCollapsed ? 'Sign Out' : undefined}
          className={`w-full flex items-center ${
            isCollapsed ? 'justify-center px-2' : 'gap-2.5 px-3'
          } py-2 rounded-lg text-xs font-semibold text-rose-400 hover:bg-rose-500/10 hover:text-rose-300 transition-colors`}
        >
          <LogOut className="w-4 h-4 shrink-0" />
          {!isCollapsed && <span>Sign Out</span>}
        </button>
      </div>
    </aside>
  );
};

