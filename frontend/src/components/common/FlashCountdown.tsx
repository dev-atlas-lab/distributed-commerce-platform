import React, { useEffect, useState, useCallback } from "react";
import { Clock, Flame } from "lucide-react";
import { cn } from "../../lib/utils";

interface FlashCountdownProps {
  targetDate: string | Date;
  onExpire?: () => void;
  className?: string;
  compact?: boolean;
}

interface TimeRemaining {
  totalMs: number;
  hours: number;
  minutes: number;
  seconds: number;
}

function calculateRemaining(target: Date): TimeRemaining {
  const totalMs = Math.max(0, target.getTime() - Date.now());
  const seconds = Math.floor((totalMs / 1000) % 60);
  const minutes = Math.floor((totalMs / (1000 * 60)) % 60);
  const hours = Math.floor(totalMs / (1000 * 60 * 60));

  return { totalMs, hours, minutes, seconds };
}

export const FlashCountdown: React.FC<FlashCountdownProps> = ({
  targetDate,
  onExpire,
  className,
  compact = false,
}) => {
  const target = new Date(targetDate);
  const [remaining, setRemaining] = useState<TimeRemaining>(() =>
    calculateRemaining(target)
  );

  const handleExpire = useCallback(() => {
    if (onExpire) {
      onExpire();
    }
  }, [onExpire]);

  useEffect(() => {
    const timer = setInterval(() => {
      const rem = calculateRemaining(target);
      setRemaining(rem);

      if (rem.totalMs <= 0) {
        clearInterval(timer);
        handleExpire();
      }
    }, 1000);

    return () => clearInterval(timer);
  }, [targetDate, handleExpire]);

  const isExpired = remaining.totalMs <= 0;
  const isUrgent = remaining.totalMs > 0 && remaining.totalMs < 10 * 60 * 1000; // < 10 mins
  const isCritical = remaining.totalMs > 0 && remaining.totalMs < 60 * 1000; // < 60 secs

  const pad = (n: number) => String(n).padStart(2, "0");

  if (isExpired) {
    return (
      <div
        className={cn(
          "inline-flex items-center px-3 py-1 rounded-full text-xs font-semibold bg-slate-200 text-slate-700",
          className
        )}
      >
        <span>Sale Ended</span>
      </div>
    );
  }

  if (compact) {
    return (
      <div
        className={cn(
          "inline-flex items-center space-x-1.5 font-mono tabular-nums text-xs font-semibold px-2.5 py-1 rounded-md",
          isCritical
            ? "bg-rose-100 text-rose-800 animate-pulse border border-rose-300"
            : isUrgent
            ? "bg-amber-100 text-amber-900 border border-amber-300"
            : "bg-slate-900 text-white",
          className
        )}
      >
        <Flame className={cn("w-3.5 h-3.5", isCritical ? "text-rose-600" : isUrgent ? "text-amber-600" : "text-amber-400")} />
        <span>
          {pad(remaining.hours)}:{pad(remaining.minutes)}:{pad(remaining.seconds)}
        </span>
      </div>
    );
  }

  return (
    <div
      role="timer"
      aria-live="polite"
      className={cn(
        "flex items-center space-x-3 p-3 rounded-xl border font-mono tabular-nums transition-colors",
        isCritical
          ? "bg-rose-50 border-rose-300 text-rose-900 shadow-sm"
          : isUrgent
          ? "bg-amber-50 border-amber-300 text-amber-900 shadow-sm"
          : "bg-slate-900 border-slate-800 text-white",
        className
      )}
    >
      <div className="flex items-center space-x-2 text-xs font-sans font-medium uppercase tracking-wider text-slate-400">
        <Clock className="w-4 h-4 text-amber-400" />
        <span>Ends in:</span>
      </div>

      <div className="flex items-center space-x-1 text-base font-bold">
        <div className="px-2 py-1 rounded bg-black/30 min-w-[2rem] text-center">
          {pad(remaining.hours)}
        </div>
        <span className="text-slate-500">:</span>
        <div className="px-2 py-1 rounded bg-black/30 min-w-[2rem] text-center">
          {pad(remaining.minutes)}
        </div>
        <span className="text-slate-500">:</span>
        <div
          className={cn(
            "px-2 py-1 rounded min-w-[2rem] text-center",
            isCritical ? "bg-rose-600 text-white animate-pulse" : "bg-black/30"
          )}
        >
          {pad(remaining.seconds)}
        </div>
      </div>
    </div>
  );
};
