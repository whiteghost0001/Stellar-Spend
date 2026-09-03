import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock DB client before importing the service
vi.mock("../db/client", () => ({
  db: {
    query: vi.fn(),
  },
  pool: {
    query: vi.fn(),
  },
}));

// Set dummy env var
process.env.DATABASE_URL = "postgres://localhost:5432/dummy";

import {
  calculateRiskScore,
  calculateInsurancePremium,
} from "../services/insurance.service";

describe("Insurance Service Logic", () => {
  it("should calculate risk score correctly", () => {
    // Low value stablecoin = low risk
    expect(calculateRiskScore(50, "USDC")).toBe(55); // 50 (base) + 10 (low amount) - 5 (stable)

    // High value = lower risk (preferred customer)
    expect(calculateRiskScore(20000, "USDC")).toBe(35); // 50 (base) - 10 (high value) - 5 (stable)

    // Medium value volatile = base risk
    expect(calculateRiskScore(500, "NGN")).toBe(50);
  });

  it("should calculate premium correctly", async () => {
    const quote = await calculateInsurancePremium(1000, "USDC");

    expect(quote.provider).toBe("premium");
    expect(quote.coverage).toBe(1100); // 1.1x
    expect(quote.premium).toBeGreaterThan(0);
    expect(quote.riskScore).toBe(45); // 50 (base) - 5 (stable)
  });

  it("should apply bulk discount for high value", async () => {
    const quote = await calculateInsurancePremium(20000, "USDC");
    expect(quote.provider).toBe("enterprise");
    // Base rate for high value is 0.003
    // Risk score is 35 -> multiplier is 1 + (35-50)/500 = 1 - 0.03 = 0.97
    // Expected premium: 20000 * 0.003 * 0.97 = 58.2
    expect(quote.premium).toBe(58.2);
  });
});
