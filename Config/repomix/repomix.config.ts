import { defineConfig } from "repomix";

const now = new Date();
const timestamp = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}--${String(now.getHours()).padStart(2, "0")}h-${String(now.getMinutes()).padStart(2, "0")}m`;

export default defineConfig({
   output: {
      filePath: `.repomix/${timestamp}.xml`,
      style: "xml",
      removeComments: true,
      compress: false,
      fileSummary: true,
      directoryStructure: true,
      files: true,
      removeEmptyLines: true,
      showLineNumbers: false,
      truncateBase64: true,
      copyToClipboard: false,
      topFilesLength: 10,
      // includeFullDirectoryStructure: true,
   },
   ignore: {
      customPatterns: [
         "**/dist/**",
         "**/.repomix/**",
         "**/.next/**",
         "**/drizzle/**",
         "**/.turbo/**",
         "**/*.json",
         "**/*.md",
      ],
      useGitignore: true,
      useDefaultPatterns: true,
   },
   include: ["apps/api", "packages/zod", "packages/db"],
   security: {
      enableSecurityCheck: true,
   },
});
