import React, { useState } from "react";
import { Link, NavLink, Outlet } from "react-router-dom";
import {
  ShoppingBag,
  Zap,
  Search,
  ShoppingCart,
  Sparkles,
  Menu,
  X,
  Package,
} from "lucide-react";
import { cn } from "../../lib/utils";

export const StorefrontLayout: React.FC = () => {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const cartItemCount = 0; // State will be bound to Zustand cart store in M2

  const navLinks = [
    { to: "/", label: "Home" },
    { to: "/catalog", label: "Catalog" },
    {
      to: "/flash-sales",
      label: "Flash Sales",
      badge: "LIVE",
      badgeColor: "bg-rose-500 text-white animate-pulse",
    },
    { to: "/orders", label: "My Orders" },
  ];

  return (
    <div className="min-h-screen flex flex-col bg-slate-50 text-slate-900 font-sans">
      {/* Top Flash Sale Ticker / Announcement Bar */}
      <div className="bg-slate-900 text-white text-xs py-2 px-4 border-b border-slate-800">
        <div className="max-w-7xl mx-auto flex items-center justify-between">
          <div className="flex items-center space-x-2">
            <span className="flex h-2 w-2 relative">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-rose-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2 w-2 bg-rose-500"></span>
            </span>
            <span className="font-medium text-slate-300">
              Midnight Lightning Flash Sale is Live! Up to 70% off limited SKUs.
            </span>
          </div>
          <Link
            to="/flash-sales"
            className="hidden sm:inline-flex items-center space-x-1 text-amber-400 hover:text-amber-300 font-medium transition-colors"
          >
            <span>Enter Live Arena</span>
            <Zap className="w-3.5 h-3.5 fill-current" />
          </Link>
        </div>
      </div>

      {/* Main Storefront Navigation Header */}
      <header className="sticky top-0 z-40 bg-white/95 backdrop-blur border-b border-slate-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16 gap-4">
            {/* Logo */}
            <div className="flex items-center gap-6">
              <Link to="/" className="flex items-center space-x-2.5">
                <div className="w-9 h-9 rounded-xl bg-indigo-600 flex items-center justify-center text-white shadow-sm">
                  <ShoppingBag className="w-5 h-5" />
                </div>
                <span className="font-bold text-lg tracking-tight text-slate-900">
                  DevAtlas <span className="text-indigo-600">Store</span>
                </span>
              </Link>

              {/* Desktop Nav Links */}
              <nav className="hidden md:flex items-center space-x-1">
                {navLinks.map((link) => (
                  <NavLink
                    key={link.to}
                    to={link.to}
                    className={({ isActive }) =>
                      cn(
                        "px-3 py-2 rounded-lg text-sm font-medium transition-colors flex items-center space-x-1.5",
                        isActive
                          ? "bg-indigo-50 text-indigo-700"
                          : "text-slate-600 hover:text-slate-900 hover:bg-slate-100"
                      )
                    }
                  >
                    <span>{link.label}</span>
                    {link.badge && (
                      <span
                        className={cn(
                          "text-[10px] font-bold px-1.5 py-0.5 rounded-full",
                          link.badgeColor
                        )}
                      >
                        {link.badge}
                      </span>
                    )}
                  </NavLink>
                ))}
              </nav>
            </div>

            {/* Search Bar */}
            <div className="hidden lg:flex flex-1 max-w-md mx-4">
              <div className="relative w-full">
                <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-slate-400">
                  <Search className="w-4 h-4" />
                </div>
                <input
                  type="search"
                  placeholder="Search products, brands, categories..."
                  className="w-full pl-9 pr-4 py-1.5 text-sm bg-slate-100 border border-transparent rounded-lg focus:bg-white focus:border-indigo-500 focus:ring-2 focus:ring-indigo-200 outline-none transition-all"
                />
              </div>
            </div>

            {/* Right Action Icons: AI Assistant, Cart, Account, Admin Link */}
            <div className="flex items-center space-x-2 sm:space-x-3">
              {/* AI Assistant Button */}
              <button
                type="button"
                className="inline-flex items-center space-x-1 px-3 py-1.5 rounded-lg text-xs font-medium bg-gradient-to-r from-indigo-500 to-purple-600 text-white shadow-sm hover:from-indigo-600 hover:to-purple-700 transition-all"
                title="Open AI Shopping Assistant"
              >
                <Sparkles className="w-3.5 h-3.5" />
                <span className="hidden sm:inline">AI Assistant</span>
              </button>

              {/* Cart Button */}
              <Link
                to="/cart"
                className="relative p-2 text-slate-600 hover:text-indigo-600 hover:bg-slate-100 rounded-lg transition-colors"
                aria-label={`Shopping cart with ${cartItemCount} items`}
              >
                <ShoppingCart className="w-5 h-5" />
                {cartItemCount > 0 && (
                  <span className="absolute top-1 right-1 flex items-center justify-center w-4 h-4 text-[10px] font-bold text-white bg-indigo-600 rounded-full">
                    {cartItemCount}
                  </span>
                )}
              </Link>

              {/* Admin Portal Shortcut */}
              <Link
                to="/admin"
                className="hidden sm:inline-flex items-center px-2.5 py-1 text-xs font-medium text-slate-600 hover:text-slate-900 border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors"
              >
                Admin
              </Link>

              {/* Mobile menu toggle */}
              <button
                type="button"
                onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
                className="md:hidden p-2 text-slate-600 hover:text-slate-900 rounded-lg"
                aria-label="Toggle mobile menu"
              >
                {mobileMenuOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
              </button>
            </div>
          </div>
        </div>

        {/* Mobile dropdown menu */}
        {mobileMenuOpen && (
          <div className="md:hidden border-t border-slate-200 bg-white px-4 pt-2 pb-4 space-y-1">
            {navLinks.map((link) => (
              <NavLink
                key={link.to}
                to={link.to}
                onClick={() => setMobileMenuOpen(false)}
                className={({ isActive }) =>
                  cn(
                    "block px-3 py-2 rounded-lg text-base font-medium",
                    isActive
                      ? "bg-indigo-50 text-indigo-700"
                      : "text-slate-700 hover:bg-slate-100"
                  )
                }
              >
                <div className="flex items-center justify-between">
                  <span>{link.label}</span>
                  {link.badge && (
                    <span
                      className={cn(
                        "text-[10px] font-bold px-1.5 py-0.5 rounded-full",
                        link.badgeColor
                      )}
                    >
                      {link.badge}
                    </span>
                  )}
                </div>
              </NavLink>
            ))}
            <div className="pt-2 border-t border-slate-100">
              <Link
                to="/admin"
                onClick={() => setMobileMenuOpen(false)}
                className="block px-3 py-2 rounded-lg text-sm font-medium text-slate-600 hover:bg-slate-100"
              >
                Switch to Admin Portal
              </Link>
            </div>
          </div>
        )}
      </header>

      {/* Main Outlet */}
      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <Outlet />
      </main>

      {/* Footer */}
      <footer className="bg-white border-t border-slate-200 mt-16 text-slate-500 text-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="flex items-center space-x-2">
            <Package className="w-4 h-4 text-indigo-600" />
            <span className="font-semibold text-slate-800">Distributed Commerce Platform</span>
            <span className="text-slate-400">|</span>
            <span className="text-xs text-slate-400">Polyglot Architecture (Java, .NET, Python, React)</span>
          </div>
          <div className="flex items-center space-x-6 text-xs text-slate-500">
            <span>RFC 9457 Compliant</span>
            <span>Zero-Trust Security</span>
            <Link to="/admin" className="hover:text-slate-900 transition-colors">
              Staff Portal
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
};
