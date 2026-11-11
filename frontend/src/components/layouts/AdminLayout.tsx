import React, { useState } from "react";
import { Link, NavLink, Outlet, useLocation } from "react-router-dom";
import {
  LayoutDashboard,
  Layers,
  Boxes,
  Zap,
  Terminal,
  Store,
  ChevronLeft,
  ChevronRight,
  Shield,
  Search,
} from "lucide-react";
import { cn } from "../../lib/utils";

export const AdminLayout: React.FC = () => {
  const [collapsed, setCollapsed] = useState(false);
  const location = useLocation();

  const navItems = [
    { to: "/admin", label: "Dashboard", icon: LayoutDashboard, end: true },
    { to: "/admin/catalog", label: "Catalog & SKUs", icon: Layers },
    { to: "/admin/inventory", label: "Inventory Ledger", icon: Boxes },
    { to: "/admin/flash-sales", label: "Flash Sales", icon: Zap },
    { to: "/admin/ops", label: "AI Ops Console", icon: Terminal },
  ];

  const currentNav = navItems.find((item) =>
    item.end
      ? location.pathname === item.to
      : location.pathname.startsWith(item.to)
  );

  return (
    <div className="min-h-screen flex bg-slate-100 text-slate-900 font-sans">
      {/* Sidebar */}
      <aside
        className={cn(
          "bg-slate-900 text-slate-300 flex flex-col transition-all duration-200 border-r border-slate-800 z-30",
          collapsed ? "w-16" : "w-64"
        )}
      >
        {/* Brand header */}
        <div className="h-16 flex items-center justify-between px-4 border-b border-slate-800">
          {!collapsed && (
            <Link to="/admin" className="flex items-center space-x-2">
              <Shield className="w-6 h-6 text-sky-400" />
              <span className="font-bold text-base text-white tracking-tight">
                Atlas <span className="text-sky-400">Admin</span>
              </span>
            </Link>
          )}
          {collapsed && (
            <div className="mx-auto">
              <Shield className="w-6 h-6 text-sky-400" />
            </div>
          )}
          <button
            type="button"
            onClick={() => setCollapsed(!collapsed)}
            className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition-colors"
            aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          >
            {collapsed ? <ChevronRight className="w-4 h-4" /> : <ChevronLeft className="w-4 h-4" />}
          </button>
        </div>

        {/* Navigation items */}
        <nav className="flex-1 py-4 px-2 space-y-1">
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                className={({ isActive }) =>
                  cn(
                    "flex items-center space-x-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors",
                    isActive
                      ? "bg-sky-600 text-white shadow-sm"
                      : "text-slate-400 hover:text-white hover:bg-slate-800",
                    collapsed && "justify-center px-2"
                  )
                }
                title={collapsed ? item.label : undefined}
              >
                <Icon className="w-5 h-5 flex-shrink-0" />
                {!collapsed && <span>{item.label}</span>}
              </NavLink>
            );
          })}
        </nav>

        {/* Storefront return link in bottom sidebar */}
        <div className="p-3 border-t border-slate-800">
          <Link
            to="/"
            className={cn(
              "flex items-center space-x-3 px-3 py-2 rounded-lg text-xs font-medium text-slate-400 hover:text-white hover:bg-slate-800 transition-colors",
              collapsed && "justify-center px-2"
            )}
            title={collapsed ? "Storefront" : undefined}
          >
            <Store className="w-4 h-4 flex-shrink-0 text-emerald-400" />
            {!collapsed && <span>Storefront</span>}
          </Link>
        </div>
      </aside>

      {/* Main Content Container */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Top Navbar */}
        <header className="h-16 bg-white border-b border-slate-200 flex items-center justify-between px-6 z-20">
          <div className="flex items-center space-x-4">
            <h1 className="text-lg font-bold text-slate-900 tracking-tight">
              {currentNav?.label || "Operations"}
            </h1>
            <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-mono font-medium bg-emerald-50 text-emerald-700 border border-emerald-200">
              M1 Foundation
            </span>
          </div>

          <div className="flex items-center space-x-4">
            {/* Quick search input */}
            <div className="relative hidden md:block w-64">
              <Search className="w-4 h-4 absolute left-3 top-2.5 text-slate-400" />
              <input
                type="text"
                placeholder="Search resources... (Cmd+K)"
                className="w-full pl-9 pr-3 py-1.5 text-xs bg-slate-100 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-500"
              />
            </div>

            {/* View storefront button */}
            <Link
              to="/"
              className="inline-flex items-center space-x-1.5 px-3 py-1.5 text-xs font-medium text-slate-700 bg-slate-100 hover:bg-slate-200 rounded-lg transition-colors"
            >
              <Store className="w-3.5 h-3.5 text-slate-500" />
              <span>Customer Storefront</span>
            </Link>
          </div>
        </header>

        {/* Dynamic Outlet */}
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-7xl mx-auto">
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  );
};
