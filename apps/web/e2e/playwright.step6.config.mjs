import baseConfig from "./playwright.config.mjs";

const step6Config = {
  ...baseConfig,
  testMatch: "step6-dashboard.spec.mjs",
};

export default step6Config;
