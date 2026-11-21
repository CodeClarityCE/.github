import { expect, test } from "@playwright/test";
import { greet } from "../src/greet.js";

// Renders greet's output in a real browser, proving the Playwright image runs.
test("shows the greeting in a page", async ({ page }) => {
  await page.setContent(`<h1>${greet("world")}</h1>`);
  await expect(page.getByRole("heading")).toHaveText("Hello, world!");
});
