import React, { useState } from "react";
import { Plus, Search, Filter, MoreHorizontal, ChevronLeft, ChevronRight } from "lucide-react";
import { formatPrice } from "../../lib/utils";

interface AdminProductRow {
  id: string;
  name: string;
  brand: string;
  category: string;
  status: "ACTIVE" | "DRAFT" | "ARCHIVED";
  variantCount: number;
  basePrice: number;
  version: number;
}

const PRODUCTS_DATA: AdminProductRow[] = [
  {
    id: "prod-001",
    name: "Ultra-Fast Mechanical Keyboard",
    brand: "AtlasTech",
    category: "Peripherals",
    status: "ACTIVE",
    variantCount: 3,
    basePrice: 149.99,
    version: 4,
  },
  {
    id: "prod-002",
    name: "Precision Ergonomic Wireless Mouse",
    brand: "AtlasTech",
    category: "Peripherals",
    status: "ACTIVE",
    variantCount: 2,
    basePrice: 89.5,
    version: 2,
  },
  {
    id: "prod-003",
    name: "27-inch 4K High Refresh Monitor",
    brand: "VisionMaster",
    category: "Displays",
    status: "DRAFT",
    variantCount: 1,
    basePrice: 499.0,
    version: 1,
  },
  {
    id: "prod-004",
    name: "Active Noise-Cancelling Studio Headset",
    brand: "Acoustix",
    category: "Audio",
    status: "ARCHIVED",
    variantCount: 4,
    basePrice: 229.0,
    version: 7,
  },
];

export const AdminCatalogPage: React.FC = () => {
  const [page, setPage] = useState(1);
  const totalPages = 3;
  const totalElements = 12;

  return (
    <div className="space-y-6">
      {/* Action Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-slate-200">
        <div>
          <h2 className="text-xl font-bold text-slate-900 tracking-tight">Catalog Management</h2>
          <p className="text-xs text-slate-500">
            Manage SPUs, multi-variant SKUs, currency uniformity, and aggregate versions.
          </p>
        </div>

        <div className="flex items-center space-x-3">
          <button
            type="button"
            className="inline-flex items-center space-x-1.5 px-3 py-1.5 rounded-lg border border-slate-300 text-xs font-semibold text-slate-700 hover:bg-slate-50 transition-colors"
          >
            <Filter className="w-3.5 h-3.5 text-slate-500" />
            <span>Filters</span>
          </button>

          <button
            type="button"
            className="inline-flex items-center space-x-1.5 px-3.5 py-1.5 rounded-lg bg-sky-600 hover:bg-sky-700 text-white text-xs font-semibold shadow-xs transition-colors"
          >
            <Plus className="w-4 h-4" />
            <span>New Product SPU</span>
          </button>
        </div>
      </div>

      {/* Dense Table Card */}
      <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden shadow-xs">
        <div className="p-4 border-b border-slate-100 flex items-center justify-between gap-4">
          <div className="relative w-72">
            <Search className="w-4 h-4 absolute left-3 top-2.5 text-slate-400" />
            <input
              type="search"
              placeholder="Filter by title, brand, or SKU..."
              className="w-full pl-9 pr-3 py-1.5 text-xs bg-slate-50 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
          </div>

          <span className="text-xs text-slate-500 font-mono">
            Showing {PRODUCTS_DATA.length} of {totalElements} products
          </span>
        </div>

        {/* Data Table */}
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs text-slate-600">
            <thead className="bg-slate-50 text-slate-700 font-bold uppercase tracking-wider text-[10px] border-b border-slate-200">
              <tr>
                <th className="py-3 px-4">Product Name</th>
                <th className="py-3 px-4">Brand</th>
                <th className="py-3 px-4">Category</th>
                <th className="py-3 px-4">Base Price</th>
                <th className="py-3 px-4">Variants</th>
                <th className="py-3 px-4">Status</th>
                <th className="py-3 px-4">Version</th>
                <th className="py-3 px-4 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {PRODUCTS_DATA.map((p) => (
                <tr key={p.id} className="hover:bg-slate-50 transition-colors">
                  <td className="py-3.5 px-4 font-semibold text-slate-900">{p.name}</td>
                  <td className="py-3.5 px-4">{p.brand}</td>
                  <td className="py-3.5 px-4">{p.category}</td>
                  <td className="py-3.5 px-4 font-mono font-medium text-slate-900">
                    {formatPrice(p.basePrice)}
                  </td>
                  <td className="py-3.5 px-4 font-mono">{p.variantCount} SKUs</td>
                  <td className="py-3.5 px-4">
                    <span
                      className={`inline-flex items-center px-2 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider ${
                        p.status === "ACTIVE"
                          ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                          : p.status === "DRAFT"
                          ? "bg-amber-50 text-amber-700 border border-amber-200"
                          : "bg-slate-100 text-slate-600 border border-slate-200"
                      }`}
                    >
                      {p.status}
                    </span>
                  </td>
                  <td className="py-3.5 px-4 font-mono text-slate-400">v{p.version}</td>
                  <td className="py-3.5 px-4 text-right">
                    <button
                      type="button"
                      className="p-1 rounded text-slate-400 hover:text-slate-600 transition-colors"
                      aria-label="Actions"
                    >
                      <MoreHorizontal className="w-4 h-4" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Standard Pagination Bar */}
        <div className="p-4 border-t border-slate-100 flex items-center justify-between text-xs text-slate-500">
          <span>Page {page} of {totalPages}</span>

          <div className="flex items-center space-x-1">
            <button
              type="button"
              disabled={page <= 1}
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              className="p-1.5 rounded border border-slate-200 disabled:opacity-40 hover:bg-slate-50"
              aria-label="Previous page"
            >
              <ChevronLeft className="w-3.5 h-3.5" />
            </button>
            <button
              type="button"
              disabled={page >= totalPages}
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              className="p-1.5 rounded border border-slate-200 disabled:opacity-40 hover:bg-slate-50"
              aria-label="Next page"
            >
              <ChevronRight className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
