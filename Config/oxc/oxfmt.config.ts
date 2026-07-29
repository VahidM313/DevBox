import { defineConfig } from "oxfmt";

export default defineConfig({
   ignorePatterns: [
      "**/dist/**",
      "**/.next/**",
      "**/build/**",
      "**/coverage/**",
      "**/node_modules/**",
      "**/.turbo/**",
   ],
   sortImports: {
      groups: [
         "type-import",
         ["value-builtin", "value-external"],
         "type-internal",
         "value-internal",
         ["type-parent", "type-sibling", "type-index"],
         ["value-parent", "value-sibling", "value-index"],
         "unknown",
      ],
   },
   sortTailwindcss: {
      stylesheet: "packages/ui/src/styles/globals.css",
      functions: ["clsx", "cn"],
      preserveWhitespace: true,
   },
   tabWidth: 3,
   useTabs: false,
});
