import { defineConfig } from "oxlint";

export default defineConfig({
   categories: {
      correctness: "warn",
   },
   options: {
      typeAware: true,
      typeCheck: true,
   },
   rules: {
      "eslint/no-unused-vars": "error",
      "import/no-cycle": "error",
   },
   plugins: ["eslint", "typescript", "unicorn", "oxc", "import", "nextjs", "react", "react-perf"],
   // categories: {
   //    correctness: "error",
   // suspicious: "warn",
   // pedantic: "off",
   // perf: "warn",
   // style: "warn",
   // },
   ignorePatterns: [
      "**/dist/**",
      "**/.next/**",
      "**/build/**",
      "**/coverage/**",
      "**/node_modules/**",
      "**/.turbo/**",
      "apps/web",
      "apps/admin",
      "packages/ui",
   ],
   settings: {
      next: {
         rootDir: ["apps/web", "apps/admin", "packages/ui"],
      },
   },
});
