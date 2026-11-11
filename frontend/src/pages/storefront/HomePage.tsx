import React from "react";
import { Link } from "react-router-dom";
import { Zap, Sparkles, ShieldCheck, ArrowRight, Layers, Cpu } from "lucide-react";
import { FlashCountdown } from "../../components/common/FlashCountdown";

export const HomePage: React.FC = () => {
  // Mock target date 2 hours into the future for demonstration
  const saleEndsAt = new Date(Date.now() + 2 * 60 * 60 * 1000 + 45 * 60 * 1000);

  return (
    <div className="space-y-12">
      {/* Hero Section */}
      <section className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-slate-900 via-indigo-950 to-slate-900 text-white p-8 sm:p-12 shadow-xl">
        <div className="relative z-10 max-w-2xl space-y-6">
          <div className="inline-flex items-center space-x-2 px-3 py-1 rounded-full bg-white/10 backdrop-blur border border-white/20 text-xs font-semibold text-amber-300">
            <Zap className="w-3.5 h-3.5 fill-current" />
            <span>High-Concurrency Flash Sale Arena</span>
          </div>

          <h1 className="text-4xl sm:text-5xl font-extrabold tracking-tight leading-tight">
            Distributed Commerce & Instant Flash Sales
          </h1>

          <p className="text-slate-300 text-base sm:text-lg leading-relaxed">
            Engineered for extreme traffic spikes with Java 21, .NET 10, Python AI, and React 19.
            Sub-millisecond inventory protection, zero oversell guarantees, and instant AI shopping triage.
          </p>

          <div className="pt-2 flex flex-wrap items-center gap-4">
            <Link
              to="/flash-sales"
              className="inline-flex items-center space-x-2 px-6 py-3 rounded-xl bg-rose-600 hover:bg-rose-500 font-semibold text-white shadow-lg shadow-rose-600/30 transition-all transform hover:-translate-y-0.5"
            >
              <span>Enter Flash Sale Arena</span>
              <ArrowRight className="w-4 h-4" />
            </Link>

            <Link
              to="/catalog"
              className="inline-flex items-center space-x-2 px-6 py-3 rounded-xl bg-white/10 hover:bg-white/20 font-semibold text-white border border-white/20 transition-colors"
            >
              <Layers className="w-4 h-4" />
              <span>Browse Catalog</span>
            </Link>
          </div>
        </div>

        {/* Decorative countdown preview card in hero */}
        <div className="mt-8 lg:mt-0 lg:absolute lg:right-12 lg:top-1/2 lg:-translate-y-1/2 w-full lg:w-80 bg-white/10 backdrop-blur-md border border-white/20 rounded-2xl p-6 space-y-4">
          <div className="flex items-center justify-between text-xs font-semibold uppercase tracking-wider text-slate-300">
            <span>Next Flash Drop</span>
            <span className="px-2 py-0.5 rounded bg-rose-500/80 text-white font-mono">LIVE</span>
          </div>

          <FlashCountdown targetDate={saleEndsAt} />

          <p className="text-xs text-slate-300 leading-relaxed">
            Guaranteed atomic reservation via Redis Lua engine with automated Kafka materialization.
          </p>
        </div>
      </section>

      {/* Feature Highlights Grid */}
      <section className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="bg-white rounded-2xl border border-slate-200 p-6 space-y-3 shadow-sm hover:shadow-md transition-shadow">
          <div className="w-10 h-10 rounded-xl bg-indigo-50 text-indigo-600 flex items-center justify-center">
            <Cpu className="w-5 h-5" />
          </div>
          <h2 className="text-lg font-bold text-slate-900">Polyglot Architecture</h2>
          <p className="text-sm text-slate-600 leading-relaxed">
            Java 21 Spring Boot core domain, .NET 10 edge gateway & promotions, and Python FastAPI AI worker with shared contract governance.
          </p>
        </div>

        <div className="bg-white rounded-2xl border border-slate-200 p-6 space-y-3 shadow-sm hover:shadow-md transition-shadow">
          <div className="w-10 h-10 rounded-xl bg-rose-50 text-rose-600 flex items-center justify-center">
            <Zap className="w-5 h-5" />
          </div>
          <h2 className="text-lg font-bold text-slate-900">Zero Oversell Invariant</h2>
          <p className="text-sm text-slate-600 leading-relaxed">
            Single-flight stampede protection, atomic quota claims, and PostgreSQL outbox relay with idempotency inbox tables.
          </p>
        </div>

        <div className="bg-white rounded-2xl border border-slate-200 p-6 space-y-3 shadow-sm hover:shadow-md transition-shadow">
          <div className="w-10 h-10 rounded-xl bg-purple-50 text-purple-600 flex items-center justify-center">
            <Sparkles className="w-5 h-5" />
          </div>
          <h2 className="text-lg font-bold text-slate-900">Agentic AI Assistants</h2>
          <p className="text-sm text-slate-600 leading-relaxed">
            Tool-calling shopping and operations assistants with zero-trust API gateway boundaries and human-in-the-loop approvals.
          </p>
        </div>
      </section>

      {/* Architecture Compliance Banner */}
      <section className="bg-slate-900 text-slate-300 rounded-2xl p-6 flex flex-col sm:flex-row items-center justify-between gap-4">
        <div className="flex items-center space-x-3">
          <ShieldCheck className="w-6 h-6 text-emerald-400 flex-shrink-0" />
          <div className="text-sm">
            <span className="font-semibold text-white">RFC 9457 & WCAG 2.2 AA Certified UI:</span> Every view strictly follows the 4-State component rule (Loading, Empty, Error, Success).
          </div>
        </div>
        <Link
          to="/admin"
          className="text-xs font-semibold px-4 py-2 rounded-lg bg-slate-800 hover:bg-slate-700 text-white border border-slate-700 transition-colors whitespace-nowrap"
        >
          Inspect Admin Telemetry
        </Link>
      </section>
    </div>
  );
};
