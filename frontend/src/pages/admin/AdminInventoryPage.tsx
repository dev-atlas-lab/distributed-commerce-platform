import React from "react";
import { Boxes, RefreshCw } from "lucide-react";

export const AdminInventoryPage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between pb-4 border-b border-slate-200">
        <div>
          <h2 className="text-xl font-bold text-slate-900 tracking-tight">Inventory Ledger</h2>
          <p className="text-xs text-slate-500">
            Real-time stock item ledger, active reservations, and conditional atomic SQL quotas.
          </p>
        </div>
        <button
          type="button"
          className="inline-flex items-center space-x-1.5 px-3 py-1.5 rounded-lg border border-slate-300 text-xs font-semibold text-slate-700 hover:bg-slate-50 transition-colors"
        >
          <RefreshCw className="w-3.5 h-3.5 text-slate-500" />
          <span>Sync Ledger</span>
        </button>
      </div>

      <div className="bg-white p-8 rounded-2xl border border-slate-200 text-center space-y-4">
        <div className="w-12 h-12 rounded-full bg-sky-50 text-sky-600 flex items-center justify-center mx-auto">
          <Boxes className="w-6 h-6" />
        </div>
        <div className="max-w-md mx-auto space-y-1">
          <h3 className="text-base font-bold text-slate-900">Inventory Service Stock Ledger Ready</h3>
          <p className="text-xs text-slate-500">
            Connects to Java 21 Inventory Service (`src/services/inventory`) with conditional reservation assertions (`available_quantity &gt;= :requested`).
          </p>
        </div>
      </div>
    </div>
  );
};
