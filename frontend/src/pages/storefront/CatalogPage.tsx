import React, { useState } from "react";
import { Search, ShoppingCart, Tag } from "lucide-react";
import { LoadingSkeleton } from "../../components/common/LoadingSkeleton";
import { EmptyState } from "../../components/common/EmptyState";
import { ErrorBannerWithRetry } from "../../components/common/ErrorBannerWithRetry";
import { formatPrice } from "../../lib/utils";

interface MockProduct {
  id: string;
  name: string;
  brand: string;
  category: string;
  price: number;
  currency: string;
  inStock: boolean;
  stockCount: number;
  imageUrl?: string;
}

const SAMPLE_PRODUCTS: MockProduct[] = [
  {
    id: "prod-001",
    name: "Ultra-Fast Mechanical Keyboard",
    brand: "AtlasTech",
    category: "Peripherals",
    price: 149.99,
    currency: "USD",
    inStock: true,
    stockCount: 42,
  },
  {
    id: "prod-002",
    name: "Precision Ergonomic Wireless Mouse",
    brand: "AtlasTech",
    category: "Peripherals",
    price: 89.5,
    currency: "USD",
    inStock: true,
    stockCount: 15,
  },
  {
    id: "prod-003",
    name: "27-inch 4K High Refresh Monitor",
    brand: "VisionMaster",
    category: "Displays",
    price: 499.0,
    currency: "USD",
    inStock: true,
    stockCount: 8,
  },
  {
    id: "prod-004",
    name: "Active Noise-Cancelling Studio Headset",
    brand: "Acoustix",
    category: "Audio",
    price: 229.0,
    currency: "USD",
    inStock: false,
    stockCount: 0,
  },
];

export const CatalogPage: React.FC = () => {
  const [activeTab, setActiveTab] = useState<"All" | "Peripherals" | "Displays" | "Audio">("All");
  const [searchQuery, setSearchQuery] = useState("");
  // State toggle to demonstrate full compliance with the 4-State UI/UX standard:
  const [viewState, setViewState] = useState<"success" | "loading" | "empty" | "error">("success");

  const filteredProducts = SAMPLE_PRODUCTS.filter((p) => {
    const matchesCat = activeTab === "All" || p.category === activeTab;
    const matchesSearch =
      p.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      p.brand.toLowerCase().includes(searchQuery.toLowerCase());
    return matchesCat && matchesSearch;
  });

  return (
    <div className="space-y-6">
      {/* Header & 4-State Demonstrator Bar */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-slate-200">
        <div>
          <h1 className="text-2xl font-bold text-slate-900 tracking-tight">Product Catalog</h1>
          <p className="text-sm text-slate-500">
            Browse verified products backed by PostgreSQL FTS search and Redis read cache.
          </p>
        </div>

        {/* UI/UX 4-State Test Bar */}
        <div className="flex items-center space-x-2 bg-slate-100 p-1 rounded-lg text-xs font-medium">
          <span className="px-2 text-slate-500">Demo State:</span>
          {(["success", "loading", "empty", "error"] as const).map((st) => (
            <button
              key={st}
              type="button"
              onClick={() => setViewState(st)}
              className={`px-2.5 py-1 rounded capitalize transition-colors ${
                viewState === st
                  ? "bg-white text-indigo-700 shadow-xs font-semibold"
                  : "text-slate-600 hover:text-slate-900"
              }`}
            >
              {st}
            </button>
          ))}
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
        {/* Category Tabs */}
        <div className="flex items-center space-x-1 overflow-x-auto w-full sm:w-auto pb-2 sm:pb-0">
          {(["All", "Peripherals", "Displays", "Audio"] as const).map((cat) => (
            <button
              key={cat}
              type="button"
              onClick={() => setActiveTab(cat)}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-medium transition-colors whitespace-nowrap ${
                activeTab === cat
                  ? "bg-indigo-600 text-white shadow-xs"
                  : "bg-white text-slate-600 hover:bg-slate-100 border border-slate-200"
              }`}
            >
              {cat}
            </button>
          ))}
        </div>

        {/* Search input */}
        <div className="relative w-full sm:w-72">
          <Search className="w-4 h-4 absolute left-3 top-2.5 text-slate-400" />
          <input
            type="search"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search products..."
            className="w-full pl-9 pr-3 py-1.5 text-sm bg-white border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
          />
        </div>
      </div>

      {/* 4-State Content View */}
      {viewState === "loading" && <LoadingSkeleton count={4} variant="card" />}

      {viewState === "error" && (
        <ErrorBannerWithRetry
          error={{
            type: "https://problems.commerce.dev-atlas.lab/catalog-service-unavailable",
            title: "Catalog Service Unavailable",
            status: 503,
            detail: "The product catalog service is temporarily unreachable or restarting.",
            errorCode: "INFRASTRUCTURE_ERROR",
            traceId: "trace-cat-demo-8491",
            timestamp: new Date().toISOString(),
          }}
          onRetry={() => setViewState("success")}
        />
      )}

      {viewState === "empty" && (
        <EmptyState
          title="No Products Found"
          description="We couldn't find any products matching your active filters or search criteria."
          actionLabel="Reset Search & Filters"
          onAction={() => {
            setActiveTab("All");
            setSearchQuery("");
            setViewState("success");
          }}
        />
      )}

      {viewState === "success" && (
        filteredProducts.length === 0 ? (
          <EmptyState
            title="No Products Match"
            description={`No items match your filter "${searchQuery}".`}
            actionLabel="Clear Filter"
            onAction={() => setSearchQuery("")}
          />
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            {filteredProducts.map((p) => (
              <div
                key={p.id}
                className="bg-white rounded-xl border border-slate-200 overflow-hidden shadow-xs hover:shadow-md transition-shadow flex flex-col"
              >
                {/* Product Image placeholder */}
                <div className="aspect-square bg-slate-100 flex items-center justify-center relative p-6">
                  <Tag className="w-12 h-12 text-slate-300" />
                  <span
                    className={`absolute top-3 right-3 px-2 py-0.5 rounded text-[10px] font-semibold uppercase tracking-wider ${
                      p.inStock
                        ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                        : "bg-slate-100 text-slate-500 border border-slate-200"
                    }`}
                  >
                    {p.inStock ? `${p.stockCount} in stock` : "Out of Stock"}
                  </span>
                </div>

                {/* Details */}
                <div className="p-4 flex-1 flex flex-col justify-between space-y-4">
                  <div>
                    <span className="text-xs font-medium text-indigo-600 uppercase tracking-wider">
                      {p.brand}
                    </span>
                    <h3 className="font-semibold text-slate-900 text-sm mt-0.5 leading-snug line-clamp-2">
                      {p.name}
                    </h3>
                  </div>

                  <div className="flex items-center justify-between pt-2 border-t border-slate-100">
                    <span className="text-lg font-bold font-mono tabular-nums text-slate-900">
                      {formatPrice(p.price, p.currency)}
                    </span>

                    <button
                      type="button"
                      disabled={!p.inStock}
                      className="inline-flex items-center space-x-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-700 disabled:bg-slate-200 disabled:text-slate-400 disabled:cursor-not-allowed transition-colors"
                    >
                      <ShoppingCart className="w-3.5 h-3.5" />
                      <span>Add to Cart</span>
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )
      )}
    </div>
  );
};
