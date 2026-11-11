import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { LoadingSkeleton } from "../components/common/LoadingSkeleton";
import { EmptyState } from "../components/common/EmptyState";
import { ErrorBannerWithRetry } from "../components/common/ErrorBannerWithRetry";
import { FlashCountdown } from "../components/common/FlashCountdown";
import { ApiClientError } from "../lib/api-client";
import type { ProblemDetails } from "../types/api";

describe("UI/UX Foundation Components", () => {
  it("LoadingSkeleton renders with accessible role and pulse elements", () => {
    render(<LoadingSkeleton count={3} variant="card" />);
    const region = screen.getByRole("status");
    expect(region).toBeInTheDocument();
    expect(region).toHaveAttribute("aria-label", "Loading products");
  });

  it("EmptyState renders title, description, and handles CTA action", () => {
    const handleAction = vi.fn();
    render(
      <EmptyState
        title="No Items Found"
        description="Try searching with a different term."
        actionLabel="Clear Filters"
        onAction={handleAction}
      />
    );

    expect(screen.getByText("No Items Found")).toBeInTheDocument();
    expect(screen.getByText("Try searching with a different term.")).toBeInTheDocument();

    const button = screen.getByRole("button", { name: "Clear Filters" });
    fireEvent.click(button);
    expect(handleAction).toHaveBeenCalledTimes(1);
  });

  it("ErrorBannerWithRetry displays RFC 9457 error code chip and triggers retry", () => {
    const handleRetry = vi.fn();
    const problem: ProblemDetails = {
      type: "https://problems.commerce.dev-atlas.lab/product-archived",
      title: "Archived Product",
      status: 409,
      detail: "Archived products cannot be modified.",
      errorCode: "PRODUCT_ARCHIVED",
      traceId: "trace-xyz-987",
      timestamp: "2026-11-11T12:00:00Z",
    };
    const error = new ApiClientError(409, problem);

    render(<ErrorBannerWithRetry error={error} onRetry={handleRetry} />);

    expect(screen.getByRole("alert")).toBeInTheDocument();
    expect(screen.getByText("Archived Product")).toBeInTheDocument();
    expect(screen.getByText("Archived products cannot be modified.")).toBeInTheDocument();
    expect(screen.getByText("PRODUCT_ARCHIVED")).toBeInTheDocument();
    expect(screen.getByText("trace-xyz-987")).toBeInTheDocument();

    const retryBtn = screen.getByRole("button", { name: /retry/i });
    fireEvent.click(retryBtn);
    expect(handleRetry).toHaveBeenCalledTimes(1);
  });

  it("FlashCountdown renders live timer with tabular numbers", () => {
    const targetDate = new Date(Date.now() + 3600 * 1000); // 1 hour ahead
    render(<FlashCountdown targetDate={targetDate} />);

    const timer = screen.getByRole("timer");
    expect(timer).toBeInTheDocument();
    expect(timer).toHaveAttribute("aria-live", "polite");
    expect(screen.getByText("Ends in:")).toBeInTheDocument();
  });
});
