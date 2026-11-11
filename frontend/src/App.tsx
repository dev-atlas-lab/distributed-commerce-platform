import React from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { StorefrontLayout } from "./components/layouts/StorefrontLayout";
import { AdminLayout } from "./components/layouts/AdminLayout";
import { HomePage } from "./pages/storefront/HomePage";
import { CatalogPage } from "./pages/storefront/CatalogPage";
import { FlashSaleArenaPage } from "./pages/storefront/FlashSaleArenaPage";
import { CartPage } from "./pages/storefront/CartPage";
import { OrdersPage } from "./pages/storefront/OrdersPage";
import { AdminDashboardPage } from "./pages/admin/AdminDashboardPage";
import { AdminCatalogPage } from "./pages/admin/AdminCatalogPage";
import { AdminInventoryPage } from "./pages/admin/AdminInventoryPage";
import { AdminFlashSalePage } from "./pages/admin/AdminFlashSalePage";
import { AdminOpsPage } from "./pages/admin/AdminOpsPage";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 2,
      staleTime: 1000 * 30, // 30 seconds
      refetchOnWindowFocus: false,
    },
  },
});

export const App: React.FC = () => {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Routes>
          {/* Customer Storefront Routes */}
          <Route path="/" element={<StorefrontLayout />}>
            <Route index element={<HomePage />} />
            <Route path="catalog" element={<CatalogPage />} />
            <Route path="flash-sales" element={<FlashSaleArenaPage />} />
            <Route path="cart" element={<CartPage />} />
            <Route path="orders" element={<OrdersPage />} />
          </Route>

          {/* Admin Operations Portal Routes */}
          <Route path="/admin" element={<AdminLayout />}>
            <Route index element={<AdminDashboardPage />} />
            <Route path="catalog" element={<AdminCatalogPage />} />
            <Route path="inventory" element={<AdminInventoryPage />} />
            <Route path="flash-sales" element={<AdminFlashSalePage />} />
            <Route path="ops" element={<AdminOpsPage />} />
          </Route>

          {/* Catch-all fallback */}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
};

export default App;
