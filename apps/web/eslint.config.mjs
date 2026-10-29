// The template's JavaScript (api/, app/) with ESLint's recommended rules, and
// this port's TypeScript with the workspace's shared config.
import js from "@eslint/js";
import globals from "globals";
import shared from "@app/eslint-config";
import react from "eslint-plugin-react";

export default [
  ...shared,
  {
    files: ["**/*.js", "**/*.jsx"],
    ...js.configs.recommended,
    plugins: { react },
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      parserOptions: { ecmaFeatures: { jsx: true } },
      globals: { ...globals.browser, ...globals.node, ...globals.serviceworker },
    },
    rules: {
      ...js.configs.recommended.rules,
      // A component used only in JSX is used: core no-unused-vars cannot see
      // JSX, eslint-plugin-react's rule tells it.
      "react/jsx-uses-vars": "error",
      // Upstream's handlers keep their full parameter lists (`request`,
      // `context`) as React Router's docs write them, and name the errors
      // they catch and log nothing of.
      "no-unused-vars": ["error", { args: "none", caughtErrors: "none" }],
    },
  },
  { ignores: ["build/**", ".react-router/**", ".wrangler/**", "node_modules/**"] },
];
