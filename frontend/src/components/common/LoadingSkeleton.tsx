import React from "react";
import { cn } from "../../lib/utils";

interface LoadingSkeletonProps extends React.HTMLAttributes<HTMLDivElement> {
  variant?: "card" | "table-row" | "text" | "banner";
  count?: number;
}

export const LoadingSkeleton: React.FC<LoadingSkeletonProps> = ({
  variant = "card",
  count = 1,
  className,
  ...props
}) => {
  const items = Array.from({ length: count });

  if (variant === "table-row") {
    return (
      <div className={cn("space-y-3", className)} role="status" aria-label="Loading content" {...props}>
        {items.map((_, i) => (
          <div
            key={i}
            className="flex items-center space-x-4 p-4 bg-white rounded-lg border border-slate-100 animate-pulse"
          >
            <div className="h-4 bg-slate-200 rounded w-1/4"></div>
            <div className="h-4 bg-slate-200 rounded w-1/3"></div>
            <div className="h-4 bg-slate-200 rounded w-1/6"></div>
            <div className="h-4 bg-slate-200 rounded w-1/6"></div>
          </div>
        ))}
      </div>
    );
  }

  if (variant === "banner") {
    return (
      <div
        className={cn("w-full h-32 bg-slate-200 rounded-xl animate-pulse", className)}
        role="status"
        aria-label="Loading banner"
        {...props}
      />
    );
  }

  if (variant === "text") {
    return (
      <div className={cn("space-y-2", className)} role="status" aria-label="Loading text" {...props}>
        {items.map((_, i) => (
          <div
            key={i}
            className={cn("h-4 bg-slate-200 rounded animate-pulse", i === items.length - 1 ? "w-2/3" : "w-full")}
          />
        ))}
      </div>
    );
  }

  // Default: product card skeleton
  return (
    <div
      className={cn("grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6", className)}
      role="status"
      aria-label="Loading products"
      {...props}
    >
      {items.map((_, i) => (
        <div
          key={i}
          className="bg-white rounded-xl border border-slate-200 p-4 space-y-4 animate-pulse"
        >
          <div className="w-full aspect-square bg-slate-200 rounded-lg" />
          <div className="space-y-2">
            <div className="h-4 bg-slate-200 rounded w-3/4" />
            <div className="h-3 bg-slate-200 rounded w-1/2" />
          </div>
          <div className="flex justify-between items-center pt-2">
            <div className="h-5 bg-slate-200 rounded w-1/3" />
            <div className="h-8 bg-slate-200 rounded w-20" />
          </div>
        </div>
      ))}
    </div>
  );
};
