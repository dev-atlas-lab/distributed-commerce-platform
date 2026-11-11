import React from "react";
import { Clock, ExternalLink } from "lucide-react";
import { formatPrice } from "../../lib/utils";

interface MockOrder {
  id: string;
  orderNumber: string;
  date: string;
  total: number;
  status: "CONFIRMED" | "AWAITING_PAYMENT" | "SHIPPED";
  itemCount: number;
}

const ORDERS: MockOrder[] = [
  {
    id: "ord-101",
    orderNumber: "ORD-2026-89104",
    date: "2026-11-10T14:22:00Z",
    total: 328.98,
    status: "CONFIRMED",
    itemCount: 3,
  },
  {
    id: "ord-102",
    orderNumber: "ORD-2026-89045",
    date: "2026-11-08T09:15:00Z",
    total: 79.99,
    status: "SHIPPED",
    itemCount: 1,
  },
];

export const OrdersPage: React.FC = () => {
  return (
    <div className="space-y-6 max-w-4xl mx-auto">
      <div className="flex items-center justify-between pb-4 border-b border-slate-200">
        <div>
          <h1 className="text-2xl font-bold text-slate-900 tracking-tight">Order History</h1>
          <p className="text-sm text-slate-500">
            Track and view previous orders orchestrated via Saga workflows and Kafka events.
          </p>
        </div>
      </div>

      <div className="space-y-4">
        {ORDERS.map((order) => (
          <div
            key={order.id}
            className="bg-white p-5 rounded-2xl border border-slate-200 shadow-xs flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4"
          >
            <div className="space-y-1">
              <div className="flex items-center space-x-2">
                <span className="font-bold font-mono text-sm text-slate-900">
                  {order.orderNumber}
                </span>
                <span
                  className={`text-[10px] font-bold px-2 py-0.5 rounded-full uppercase tracking-wider ${
                    order.status === "CONFIRMED"
                      ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                      : "bg-indigo-50 text-indigo-700 border border-indigo-200"
                  }`}
                >
                  {order.status}
                </span>
              </div>
              <p className="text-xs text-slate-500 flex items-center space-x-1">
                <Clock className="w-3.5 h-3.5" />
                <span>Placed on {new Date(order.date).toLocaleDateString()}</span>
                <span>•</span>
                <span>{order.itemCount} items</span>
              </p>
            </div>

            <div className="flex items-center space-x-4 self-end sm:self-center">
              <span className="font-bold font-mono tabular-nums text-slate-900 text-base">
                {formatPrice(order.total)}
              </span>
              <button
                type="button"
                className="inline-flex items-center space-x-1 px-3 py-1.5 rounded-lg border border-slate-300 text-xs font-semibold text-slate-700 hover:bg-slate-50 transition-colors"
              >
                <span>View Details</span>
                <ExternalLink className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
