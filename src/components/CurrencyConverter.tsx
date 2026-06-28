"use client";

import { useMemo } from "react";
import { cn } from "@/lib/cn";
import { useCurrencyConverter } from "@/hooks/useCurrencyConverter";

export default function CurrencyConverter({ className }: { className?: string }) {
  const {
    fromAmount, toAmount, fromCurrency, toCurrency,
    rate, fees, loading, currencies, copied,
    quoteSecondsLeft, isStale, rateUpdated,
    handleFromAmountChange, handleToAmountChange,
    setFromCurrency, setToCurrency,
    swapCurrencies, copyResult,
  } = useCurrencyConverter();

  const currencyOptions = useMemo(
    () => currencies.map((curr) => <option key={curr} value={curr}>{curr}</option>),
    [currencies],
  );

  return (
    <div
      className={cn(
        "rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-900",
        className,
      )}
    >
      <h2 className="mb-4 text-lg font-semibold">Currency Converter</h2>

      {/* From Amount */}
      <div className="mb-4">
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">From</label>
        <div className="mt-2 flex gap-2">
          <input
            type="number"
            value={fromAmount}
            onChange={(e) => handleFromAmountChange(e.target.value)}
            placeholder="0.00"
            className="flex-1 rounded border border-gray-300 px-3 py-2 dark:border-gray-600 dark:bg-gray-800"
          />
          <select
            value={fromCurrency}
            onChange={(e) => setFromCurrency(e.target.value)}
            className="rounded border border-gray-300 px-3 py-2 dark:border-gray-600 dark:bg-gray-800"
          >
            <option>USDC</option>
            <option>USDT</option>
          </select>
        </div>
      </div>

      {/* Swap Button */}
      <div className="mb-4 flex justify-center">
        <button
          onClick={swapCurrencies}
          className="rounded-full bg-blue-500 p-2 text-white hover:bg-blue-600"
          aria-label="Swap currencies"
        >
          ⇅
        </button>
      </div>

      {/* To Amount */}
      <div className="mb-4">
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">To</label>
        <div className="mt-2 flex gap-2">
          <input
            type="number"
            value={toAmount}
            onChange={(e) => handleToAmountChange(e.target.value)}
            placeholder="0.00"
            className="flex-1 rounded border border-gray-300 px-3 py-2 dark:border-gray-600 dark:bg-gray-800"
          />
          <select
            value={toCurrency}
            onChange={(e) => setToCurrency(e.target.value)}
            className="rounded border border-gray-300 px-3 py-2 dark:border-gray-600 dark:bg-gray-800"
          >
            {currencyOptions}
          </select>
        </div>
      </div>

      {/* Rate Info with countdown */}
      {rate && (
        <div className="mb-4 rounded bg-gray-50 p-3 text-sm dark:bg-gray-800">
          <div className="flex items-center justify-between gap-2">
            <p className="text-gray-600 dark:text-gray-400">
              1 {fromCurrency} = {rate.toFixed(2)} {toCurrency}
            </p>
            <span
              className={cn(
                "shrink-0 text-xs tabular-nums transition-colors",
                rateUpdated ? "font-medium text-green-500"
                  : isStale ? "text-amber-500"
                  : "text-gray-400 dark:text-gray-500",
              )}
              aria-live="polite"
            >
              {rateUpdated ? "Rate updated" : isStale ? "Rate expired" : `Refreshes in ${quoteSecondsLeft}s`}
            </span>
          </div>
        </div>
      )}

      {isStale && !loading && (
        <div
          role="alert"
          className="mb-4 rounded border border-amber-500/40 bg-amber-500/10 p-3 text-xs text-amber-600 dark:text-amber-400"
        >
          The displayed rate has expired. A fresh rate will load automatically — wait a moment before submitting.
        </div>
      )}

      {/* Fees Breakdown */}
      <div className="mb-4 space-y-2 rounded bg-gray-50 p-3 text-sm dark:bg-gray-800">
        <p className="font-medium text-gray-700 dark:text-gray-300">Fees</p>
        <div className="flex justify-between text-gray-600 dark:text-gray-400">
          <span>Bridge Fee:</span><span>{fees.bridge}%</span>
        </div>
        <div className="flex justify-between text-gray-600 dark:text-gray-400">
          <span>Payout Fee:</span><span>{fees.payout}%</span>
        </div>
      </div>

      <button
        onClick={copyResult}
        disabled={isStale || !toAmount}
        title={isStale ? "Wait for the rate to refresh before copying" : undefined}
        className={cn(
          "w-full rounded px-4 py-2 font-medium transition-colors",
          copied ? "bg-green-500 text-white"
            : isStale ? "cursor-not-allowed bg-gray-300 text-gray-500 dark:bg-gray-700 dark:text-gray-400"
            : "bg-blue-500 text-white hover:bg-blue-600",
        )}
      >
        {copied ? "Copied!" : "Copy Result"}
      </button>

      {loading && (
        <p className="mt-2 text-center text-sm text-gray-500">Updating rates...</p>
      )}
    </div>
  );
}
