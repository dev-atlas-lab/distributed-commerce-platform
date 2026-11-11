import React from "react";
import { PackageOpen, LucideIcon } from "lucide-react";
import { cn } from "../../lib/utils";

interface EmptyStateProps {
  icon?: LucideIcon;
  title: string;
  description: string;
  actionLabel?: string;
  onAction?: () => void;
  className?: string;
}

export const EmptyState: React.FC<EmptyStateProps> = ({
  icon: Icon = PackageOpen,
  title,
  description,
  actionLabel,
  onAction,
  className,
}) => {
  return (
    <div
      className={cn(
        "flex flex-col items-center justify-center text-center p-8 sm:p-12 bg-white rounded-xl border border-slate-200 shadow-sm",
        className
      )}
      role="region"
      aria-label={title}
    >
      <div className="flex items-center justify-center w-16 h-16 rounded-full bg-slate-100 text-slate-500 mb-4">
        <Icon className="w-8 h-8" aria-hidden="true" />
      </div>
      <h3 className="text-lg font-semibold text-slate-900 mb-1">{title}</h3>
      <p className="text-sm text-slate-500 max-w-sm mb-6">{description}</p>
      {actionLabel && onAction && (
        <button
          type="button"
          onClick={onAction}
          className="inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-lg shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors"
        >
          {actionLabel}
        </button>
      )}
    </div>
  );
};
