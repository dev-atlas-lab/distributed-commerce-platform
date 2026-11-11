import React from "react";
import { Zap, Play, CheckCircle2 } from "lucide-react";

export const AdminFlashSalePage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between pb-4 border-b border-slate-200">
        <div>
          <h2 className="text-xl font-bold text-slate-900 tracking-tight">Flash Sale Campaign Scheduler</h2>
          <p className="text-xs text-slate-500">
            Lifecycle state machine (`DRAFT` → `APPROVED` → `WARMED` → `ACTIVE` → `ENDED` → `RECONCILED`).
          </p>
        </div>
        <button
          type="button"
          className="inline-flex items-center space-x-1.5 px-3.5 py-1.5 rounded-lg bg-rose-600 hover:bg-rose-700 text-white text-xs font-semibold shadow-xs transition-colors"
        >
          <Play className="w-3.5 h-3.5 fill-current" />
          <span>Schedule Campaign</span>
        </button>
      </div>

      <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-xs space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-3">
            <div className="p-2.5 rounded-xl bg-rose-50 text-rose-600">
              <Zap className="w-5 h-5 fill-current" />
            </div>
            <div>
              <h3 className="text-sm font-bold text-slate-900">Campaign #FS-2026-11-POOL4 (Active)</h3>
              <p className="text-xs text-slate-500 font-mono">
                Target SKU: ATLAS-KB-FLASH-01 • Redis Lua Engine Gate: ENGAGED
              </p>
            </div>
          </div>
          <span className="px-2.5 py-0.5 rounded-full text-xs font-bold uppercase tracking-wider bg-rose-50 text-rose-700 border border-rose-200 animate-pulse">
            Active Now
          </span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 pt-4 border-t border-slate-100 text-xs">
          <div>
            <span className="text-slate-500">Allocated Quota:</span>
            <p className="font-mono font-bold text-slate-900 text-sm">100 units</p>
          </div>
          <div>
            <span className="text-slate-500">Pre-warmed Cache:</span>
            <p className="font-mono font-bold text-emerald-600 text-sm flex items-center space-x-1">
              <CheckCircle2 className="w-3.5 h-3.5" />
              <span>WARMED (Redis 7.4)</span>
            </p>
          </div>
          <div>
            <span className="text-slate-500">Reconciliation Status:</span>
            <p className="font-mono font-bold text-slate-900 text-sm">PENDING_END</p>
          </div>
        </div>
      </div>
    </div>
  );
};
