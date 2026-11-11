import React, { useState } from "react";
import { Link } from "react-router-dom";
import { ShoppingCart, Trash2, ArrowRight } from "lucide-react";
import { EmptyState } from "../../components/common/EmptyState";
import { formatPrice } from "../../lib/utils";

export const CartPage: React.FC = () => {
  const [items, setItems] = useState([
    {
      id: "item-1",
      name: "Ultra-Fast Mechanical Keyboard",
      sku: "ATLAS-KB-01",
      price: 149.99,
      quantity: 1,
    },
    {
      id: "item-2",
      name: "Precision Ergonomic Wireless Mouse",
      sku: "ATLAS-MS-02",
      price: 89.5,
      quantity: 2,
    },
  ]);

  const subtotal = items.reduce((acc, item) => acc + item.price * item.quantity, 0);

  const removeItem = (id: string) => {
    setItems((prev) => prev.filter((i) => i.id !== id));
  };

  if (items.length === 0) {
    return (
      <div className="py-12">
        <EmptyState
          icon={ShoppingCart}
          title="Your Shopping Cart is Empty"
          description="Explore our catalog and find high-performance gear or check out the ongoing Flash Sale Arena."
          actionLabel="Explore Catalog"
          onAction={() => {
            window.location.href = "/catalog";
          }}
        />
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-4xl mx-auto">
      <div className="flex items-center justify-between pb-4 border-b border-slate-200">
        <h1 className="text-2xl font-bold text-slate-900 tracking-tight">Shopping Cart</h1>
        <span className="text-sm font-semibold text-slate-500 font-mono">
          {items.length} unique items
        </span>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Items List */}
        <div className="lg:col-span-2 space-y-4">
          {items.map((item) => (
            <div
              key={item.id}
              className="bg-white p-4 rounded-xl border border-slate-200 shadow-xs flex items-center justify-between gap-4"
            >
              <div className="space-y-1">
                <h3 className="font-semibold text-slate-900 text-sm">{item.name}</h3>
                <p className="text-xs text-slate-500 font-mono">SKU: {item.sku}</p>
                <p className="text-xs text-slate-600 font-mono">
                  {formatPrice(item.price)} x {item.quantity}
                </p>
              </div>

              <div className="flex items-center space-x-4">
                <span className="font-bold font-mono tabular-nums text-slate-900">
                  {formatPrice(item.price * item.quantity)}
                </span>
                <button
                  type="button"
                  onClick={() => removeItem(item.id)}
                  className="p-1.5 text-slate-400 hover:text-red-600 rounded-lg transition-colors"
                  aria-label={`Remove ${item.name}`}
                >
                  <Trash2 className="w-4 h-4" />
                </button>
              </div>
            </div>
          ))}

          <button
            type="button"
            onClick={() => setItems([])}
            className="text-xs text-slate-500 hover:text-red-600 font-medium transition-colors"
          >
            Clear Entire Cart (Test Empty State)
          </button>
        </div>

        {/* Summary Card */}
        <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-xs space-y-4 h-fit">
          <h2 className="font-bold text-base text-slate-900">Order Summary</h2>

          <div className="space-y-2 text-sm text-slate-600 border-b border-slate-100 pb-4">
            <div className="flex justify-between">
              <span>Subtotal</span>
              <span className="font-mono tabular-nums">{formatPrice(subtotal)}</span>
            </div>
            <div className="flex justify-between">
              <span>Estimated Shipping</span>
              <span className="font-mono tabular-nums text-emerald-600">FREE</span>
            </div>
            <div className="flex justify-between">
              <span>Estimated Tax</span>
              <span className="font-mono tabular-nums">{formatPrice(subtotal * 0.08)}</span>
            </div>
          </div>

          <div className="flex justify-between items-baseline font-bold text-slate-900 text-base">
            <span>Total</span>
            <span className="text-xl font-mono tabular-nums text-indigo-600">
              {formatPrice(subtotal * 1.08)}
            </span>
          </div>

          <Link
            to="/orders"
            className="w-full py-3 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-700 font-bold text-white text-sm shadow-md shadow-indigo-600/20 flex items-center justify-center space-x-2 transition-colors"
          >
            <span>Proceed to Checkout</span>
            <ArrowRight className="w-4 h-4" />
          </Link>
        </div>
      </div>
    </div>
  );
};
