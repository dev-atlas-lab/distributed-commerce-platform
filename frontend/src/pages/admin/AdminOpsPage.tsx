import React from "react";
import { ShieldAlert, Cpu, CheckCircle } from "lucide-react";

export const AdminOpsPage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between pb-4 border-b border-slate-200">
        <div>
          <h2 className="text-xl font-bold text-slate-900 tracking-tight">AI Operations & Triage Console</h2>
          <p className="text-xs text-slate-500">
            Human-in-the-Loop approval workflows, diagnostic traces, and AI guardrail logs.
          </p>
        </div>
      </div>

      {/* Human-in-the-loop Pending Approval Banner */}
      <div className="p-5 rounded-2xl bg-amber-50 border border-amber-200 text-amber-900 space-y-3">
        <div className="flex items-center space-x-2.5">
          <ShieldAlert className="w-5 h-5 text-amber-600 flex-shrink-0" />
          <h3 className="text-sm font-bold text-amber-900">
            Pending Action Approval: Adjust Inventory Safety Threshold
          </h3>
        </div>
        <p className="text-xs text-amber-800 leading-relaxed">
          The Operations AI Assistant detected an anomalous cancellation spike on SKU <code>ATLAS-MS-02</code>.
          Proposal: Increment safety stock reservation by 10 units. Requires human administrator confirmation.
        </p>
        <div className="flex items-center space-x-3 pt-1">
          <button
            type="button"
            className="px-3.5 py-1.5 rounded-lg bg-amber-600 hover:bg-amber-700 text-white text-xs font-semibold shadow-xs transition-colors"
          >
            Approve Action
          </button>
          <button
            type="button"
            className="px-3.5 py-1.5 rounded-lg bg-white border border-amber-300 text-amber-800 text-xs font-semibold hover:bg-amber-100 transition-colors"
          >
            Dismiss
          </button>
        </div>
      </div>

      {/* Security Boundary Status */}
      <div className="bg-white p-6 rounded-2xl border border-slate-200 space-y-4">
        <div className="flex items-center space-x-3">
          <Cpu className="w-5 h-5 text-sky-600" />
          <h3 className="text-sm font-bold text-slate-900">
            AI Agent Security Boundary Enforcement (Rule #6)
          </h3>
        </div>

        <div className="text-xs text-slate-600 space-y-2 leading-relaxed">
          <p>
            The Python AI Agent (<code>services/python/ai-agent-service</code>) connects exclusively via authenticated, policy-checked API Gateway endpoints with JWT propagation.
          </p>
          <div className="flex items-center space-x-2 text-emerald-700 font-semibold pt-1">
            <CheckCircle className="w-4 h-4 text-emerald-600" />
            <span>Zero direct connections to PostgreSQL business databases or Redis caches verified.</span>
          </div>
        </div>
      </div>
    </div>
  );
};
