import React from "react";
import { AlertCircle, RefreshCw } from "lucide-react";
import { ApiClientError } from "../../lib/api-client";
import type { ProblemDetails } from "../../types/api";
import { cn } from "../../lib/utils";

interface ErrorBannerProps {
  error: Error | ApiClientError | ProblemDetails | string | null;
  onRetry?: () => void;
  className?: string;
}

export const ErrorBannerWithRetry: React.FC<ErrorBannerProps> = ({
  error,
  onRetry,
  className,
}) => {
  if (!error) return null;

  let title = "An unexpected error occurred";
  let detail = "Please check your network connection and try again.";
  let errorCode: string | undefined;
  let traceId: string | undefined;

  if (error instanceof ApiClientError) {
    title = error.problem.title || `Error (${error.status})`;
    detail = error.problem.detail || error.message;
    errorCode = error.problem.errorCode;
    traceId = error.problem.traceId || error.problem.correlationId;
  } else if (typeof error === "object" && "errorCode" in error) {
    const prob = error as ProblemDetails;
    title = prob.title || "Request Failed";
    detail = prob.detail;
    errorCode = prob.errorCode;
    traceId = prob.traceId || prob.correlationId;
  } else if (error instanceof Error) {
    detail = error.message;
  } else if (typeof error === "string") {
    detail = error;
  }

  return (
    <div
      role="alert"
      aria-live="assertive"
      className={cn(
        "rounded-xl border border-red-200 bg-red-50 p-4 sm:p-5 text-red-900 shadow-sm",
        className
      )}
    >
      <div className="flex items-start">
        <div className="flex-shrink-0 text-red-600 mt-0.5">
          <AlertCircle className="h-5 w-5" aria-hidden="true" />
        </div>
        <div className="ml-3 flex-1 min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="text-sm font-semibold text-red-800">{title}</h3>
            {errorCode && (
              <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-mono font-medium bg-red-100 text-red-800 border border-red-200">
                {errorCode}
              </span>
            )}
          </div>
          <p className="mt-1 text-sm text-red-700 leading-relaxed">{detail}</p>
          {traceId && (
            <p className="mt-2 text-xs font-mono text-red-500">
              Trace: <span className="select-all">{traceId}</span>
            </p>
          )}
        </div>
        {onRetry && (
          <div className="ml-4 flex-shrink-0">
            <button
              type="button"
              onClick={onRetry}
              className="inline-flex items-center px-3 py-1.5 border border-red-300 text-xs font-medium rounded-lg text-red-800 bg-white hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500 shadow-sm transition-colors"
            >
              <RefreshCw className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" />
              Retry
            </button>
          </div>
        )}
      </div>
    </div>
  );
};
