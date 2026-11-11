import React, { useState, useEffect } from "react";
import { Zap, ShieldCheck, Flame, CheckCircle2, AlertTriangle } from "lucide-react";
import { FlashCountdown } from "../../components/common/FlashCountdown";
import { formatPrice } from "../../lib/utils";

export const FlashSaleArenaPage: React.FC = () => {
  // Campaign ends 45 minutes from now
  const [endTime] = useState(() => new Date(Date.now() + 45 * 60 * 1000));

  // Mock campaign states:
  const [stockRemaining, setStockRemaining] = useState(14); // Critical stock (< 20% of 100)
  const totalStock = 100;
  const stockPercentage = Math.round((stockRemaining / totalStock) * 100);

  // Claim button state machine:
  type ClaimState = "idle" | "reserving" | "claimed" | "sold_out";
  const [claimState, setClaimState] = useState<ClaimState>("idle");
  const [reservationTimer, setReservationTimer] = useState<number>(600); // 10 minutes in seconds

  useEffect(() => {
    if (claimState !== "claimed") return;
    const interval = setInterval(() => {
      setReservationTimer((prev) => Math.max(0, prev - 1));
    }, 1000);
    return () => clearInterval(interval);
  }, [claimState]);

  const handleClaim = () => {
    setClaimState("reserving");
    // Simulate high-concurrency Redis Lua atomic gate call
    setTimeout(() => {
      if (stockRemaining > 0) {
        setStockRemaining((prev) => Math.max(0, prev - 1));
        setClaimState("claimed");
      } else {
        setClaimState("sold_out");
      }
    }, 750);
  };

  return (
    <div className="space-y-8">
      {/* 10-Minute Reservation Sticky Top Alert (active after claiming) */}
      {claimState === "claimed" && (
        <div
          role="alert"
          aria-live="assertive"
          className="sticky top-20 z-30 p-4 bg-emerald-600 text-white rounded-2xl shadow-lg flex flex-col sm:flex-row items-center justify-between gap-3 animate-in fade-in slide-in-from-top duration-300"
        >
          <div className="flex items-center space-x-3">
            <CheckCircle2 className="w-6 h-6 text-emerald-200 flex-shrink-0" />
            <div>
              <p className="font-bold text-sm">Quota Claim Reserved via Atomic Lua Engine!</p>
              <p className="text-xs text-emerald-100">
                Item held for you. Complete payment within 10 minutes before stock auto-releases back to the pool.
              </p>
            </div>
          </div>
          <div className="flex items-center space-x-3">
            <span className="font-mono text-sm font-bold bg-emerald-700 px-3 py-1 rounded-lg">
              {Math.floor(reservationTimer / 60)}:{(reservationTimer % 60).toString().padStart(2, "0")}
            </span>
            <button
              type="button"
              className="px-4 py-1.5 rounded-lg bg-white text-emerald-800 text-xs font-bold hover:bg-emerald-50 transition-colors shadow-sm"
            >
              Pay Now
            </button>
          </div>
        </div>
      )}

      {/* Hero Banner for Flash Arena */}
      <div className="bg-slate-900 rounded-3xl p-6 sm:p-10 text-white flex flex-col md:flex-row items-start md:items-center justify-between gap-6 border border-slate-800 shadow-xl">
        <div className="space-y-3 max-w-xl">
          <div className="inline-flex items-center space-x-2 px-3 py-1 rounded-full bg-rose-500/20 text-rose-400 border border-rose-500/30 text-xs font-semibold">
            <Flame className="w-3.5 h-3.5 fill-current" />
            <span>High-Throughput Campaign Engine</span>
          </div>
          <h1 className="text-3xl sm:text-4xl font-extrabold tracking-tight">
            Flash Sale Live Arena
          </h1>
          <p className="text-slate-300 text-sm leading-relaxed">
            Directly connected to the Promotion Redis cluster. Pre-warmed stock quotas, single-flight stampede defense, and sub-15ms claim response latency.
          </p>
        </div>

        {/* Global Synchronized Countdown */}
        <div className="w-full md:w-auto">
          <FlashCountdown targetDate={endTime} />
        </div>
      </div>

      {/* Featured Flash SKU Card */}
      <div className="bg-white rounded-3xl border border-slate-200 overflow-hidden shadow-sm grid grid-cols-1 md:grid-cols-2 gap-8 p-6 sm:p-10">
        {/* Product Visual Showcase */}
        <div className="flex flex-col items-center justify-center p-8 bg-slate-50 rounded-2xl border border-slate-100 relative">
          <div className="absolute top-4 left-4 bg-rose-600 text-white text-xs font-extrabold px-3 py-1 rounded-full uppercase tracking-wider flex items-center space-x-1 shadow-sm">
            <Zap className="w-3 h-3 fill-current" />
            <span>-60% OFF</span>
          </div>

          <div className="w-48 h-48 rounded-full bg-gradient-to-tr from-rose-100 to-indigo-100 flex items-center justify-center my-6">
            <Flame className="w-24 h-24 text-rose-500" />
          </div>

          <div className="text-center space-y-1">
            <span className="text-xs font-bold text-indigo-600 tracking-wider uppercase font-mono">
              SKU: ATLAS-KB-FLASH-01
            </span>
            <p className="text-xs text-slate-500">Atomic Reservation Pool #4</p>
          </div>
        </div>

        {/* Campaign Mechanics & Live Stock Gauge */}
        <div className="flex flex-col justify-between space-y-6">
          <div className="space-y-3">
            <div className="flex items-center space-x-2">
              <span className="px-2.5 py-0.5 rounded text-xs font-semibold bg-rose-100 text-rose-800">
                Lightning Deal
              </span>
              <span className="text-xs text-slate-500 font-mono">Limit 1 per customer</span>
            </div>

            <h2 className="text-2xl font-bold text-slate-900 tracking-tight">
              Atlas Pro Optical-Mechanical RGB Gaming Keyboard
            </h2>

            <p className="text-sm text-slate-600 leading-relaxed">
              Featuring 0.2ms optical switches, aluminum chassis, and PBT double-shot keycaps. Special promotional allocation for today&apos;s flash drop.
            </p>

            {/* Price section */}
            <div className="flex items-baseline space-x-3 pt-2">
              <span className="text-3xl font-extrabold font-mono tabular-nums text-rose-600">
                {formatPrice(79.99)}
              </span>
              <span className="text-lg font-mono line-through text-slate-400">
                {formatPrice(199.99)}
              </span>
              <span className="text-xs font-bold text-emerald-600 bg-emerald-50 px-2 py-0.5 rounded">
                Save $120.00
              </span>
            </div>
          </div>

          {/* Real-time Stock Gauge (Mandatory UI/UX Standard Section 4.2) */}
          <div className="space-y-2 p-4 bg-slate-50 rounded-2xl border border-slate-200">
            <div className="flex justify-between items-center text-xs font-semibold">
              <span className="flex items-center space-x-1 text-slate-700">
                <Flame className="w-3.5 h-3.5 text-rose-500" />
                <span>Available Quota:</span>
              </span>
              <span
                className={`font-mono tabular-nums ${
                  stockRemaining <= 20 ? "text-rose-600 font-bold" : "text-slate-800"
                }`}
              >
                {stockRemaining} / {totalStock} units left ({stockPercentage}%)
              </span>
            </div>

            {/* Progress bar with urgency thresholds */}
            <div className="w-full h-3 bg-slate-200 rounded-full overflow-hidden">
              <div
                className={`h-full transition-all duration-500 ${
                  stockRemaining === 0
                    ? "bg-slate-400"
                    : stockRemaining <= 20
                    ? "bg-rose-600 animate-pulse"
                    : stockRemaining <= 50
                    ? "bg-amber-500"
                    : "bg-emerald-500"
                }`}
                style={{ width: `${stockPercentage}%` }}
              />
            </div>

            {stockRemaining <= 20 && stockRemaining > 0 && (
              <p className="text-[11px] font-semibold text-rose-600 flex items-center space-x-1">
                <AlertTriangle className="w-3 h-3 flex-shrink-0" />
                <span>Almost gone! High concurrency claim queue active.</span>
              </p>
            )}
          </div>

          {/* Claim Button State Machine */}
          <div className="pt-2">
            {claimState === "idle" && (
              <button
                type="button"
                onClick={handleClaim}
                disabled={stockRemaining === 0}
                className="w-full py-4 px-6 rounded-2xl bg-rose-600 hover:bg-rose-500 disabled:bg-slate-200 disabled:text-slate-400 font-bold text-white text-base shadow-lg shadow-rose-600/30 transition-all transform active:scale-98 flex items-center justify-center space-x-2"
              >
                <Zap className="w-5 h-5 fill-current" />
                <span>Claim Flash Deal Now</span>
              </button>
            )}

            {claimState === "reserving" && (
              <button
                type="button"
                disabled
                className="w-full py-4 px-6 rounded-2xl bg-slate-800 text-white font-bold text-base flex items-center justify-center space-x-2 cursor-wait"
              >
                <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                <span>Reserving in Redis Lua Engine...</span>
              </button>
            )}

            {claimState === "claimed" && (
              <div className="flex items-center space-x-3">
                <button
                  type="button"
                  className="flex-1 py-4 px-6 rounded-2xl bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-base shadow-lg shadow-emerald-600/30 transition-colors"
                >
                  Proceed to Checkout ($79.99)
                </button>
                <button
                  type="button"
                  onClick={() => setClaimState("idle")}
                  className="py-4 px-4 rounded-2xl border border-slate-300 text-slate-700 hover:bg-slate-50 text-xs font-semibold"
                >
                  Reset
                </button>
              </div>
            )}

            {claimState === "sold_out" && (
              <button
                type="button"
                disabled
                className="w-full py-4 px-6 rounded-2xl bg-slate-200 text-slate-500 font-bold text-base cursor-not-allowed"
              >
                Sold Out
              </button>
            )}

            <div className="mt-3 flex items-center justify-center space-x-2 text-xs text-slate-400">
              <ShieldCheck className="w-3.5 h-3.5 text-emerald-500" />
              <span>Idempotency-Key & Rate-Limiting Protection Active</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
