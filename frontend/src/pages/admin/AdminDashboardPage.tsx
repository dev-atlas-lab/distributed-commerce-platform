import React from "react";
import { Layers, Boxes, Zap, Activity, ArrowUpRight } from "lucide-react";
import { Link } from "react-router-dom";

export const AdminDashboardPage: React.FC = () => {
  const stats = [
    { title: "Catalog Products", value: "1,248", change: "+12 this week", icon: Layers, color: "text-indigo-600 bg-indigo-50" },
    { title: "Active SKUs", value: "4,892", change: "99.4% in-stock", icon: Boxes, color: "text-emerald-600 bg-emerald-50" },
    { title: "Flash Sale Arena", value: "ACTIVE", change: "Pool #4 (100 units)", icon: Zap, color: "text-rose-600 bg-rose-50" },
    { title: "Outbox / Kafka Lag", value: "0 ms", change: "All 7 brokers green", icon: Activity, color: "text-sky-600 bg-sky-50" },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-bold text-slate-900 tracking-tight">Operations Telemetry</h2>
        <p className="text-xs text-slate-500">
          Cross-service health overview across Java 21, .NET 10, Python AI Worker, and PostgreSQL 17 clusters.
        </p>
      </div>

      {/* Metrics Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {stats.map((s) => {
          const Icon = s.icon;
          return (
            <div
              key={s.title}
              className="bg-white p-5 rounded-2xl border border-slate-200 shadow-xs space-y-3"
            >
              <div className="flex items-center justify-between">
                <span className="text-xs font-semibold text-slate-500 uppercase tracking-wider">
                  {s.title}
                </span>
                <div className={`p-2 rounded-xl ${s.color}`}>
                  <Icon className="w-4 h-4" />
                </div>
              </div>

              <div className="flex items-baseline space-x-2">
                <span className="text-2xl font-extrabold font-mono text-slate-900">{s.value}</span>
                <span className="text-xs font-medium text-slate-500">{s.change}</span>
              </div>
            </div>
          );
        })}
      </div>

      {/* Quick Action Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <Link
          to="/admin/catalog"
          className="group bg-white p-6 rounded-2xl border border-slate-200 shadow-xs hover:border-indigo-300 hover:shadow-md transition-all space-y-2"
        >
          <div className="flex items-center justify-between text-slate-900 font-bold text-base">
            <span>Manage Product Catalog</span>
            <ArrowUpRight className="w-4 h-4 text-slate-400 group-hover:text-indigo-600 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-all" />
          </div>
          <p className="text-xs text-slate-500 leading-relaxed">
            Create SPUs, configure multi-variant SKUs, adjust pricing, and inspect PostgreSQL FTS indexing.
          </p>
        </Link>

        <Link
          to="/admin/flash-sales"
          className="group bg-white p-6 rounded-2xl border border-slate-200 shadow-xs hover:border-rose-300 hover:shadow-md transition-all space-y-2"
        >
          <div className="flex items-center justify-between text-slate-900 font-bold text-base">
            <span>Flash Sale Campaigns</span>
            <ArrowUpRight className="w-4 h-4 text-slate-400 group-hover:text-rose-600 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-all" />
          </div>
          <p className="text-xs text-slate-500 leading-relaxed">
            Schedule flash campaigns, pre-warm Redis Lua quotas, and review asynchronous claim logs.
          </p>
        </Link>

        <Link
          to="/admin/ops"
          className="group bg-white p-6 rounded-2xl border border-slate-200 shadow-xs hover:border-sky-300 hover:shadow-md transition-all space-y-2"
        >
          <div className="flex items-center justify-between text-slate-900 font-bold text-base">
            <span>AI Operations Console</span>
            <ArrowUpRight className="w-4 h-4 text-slate-400 group-hover:text-sky-600 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-all" />
          </div>
          <p className="text-xs text-slate-500 leading-relaxed">
            Review tool execution traces, diagnostic assessments, and human-in-the-loop operational actions.
          </p>
        </Link>
      </div>
    </div>
  );
};
