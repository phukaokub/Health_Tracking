import { access, readdir, readFile } from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const ignoredDirectories = new Set([".git", ".next", "node_modules"]);
const errors = [];

async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    if (entry.isDirectory() && ignoredDirectories.has(entry.name)) {
      continue;
    }

    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await walk(absolute)));
    } else if (entry.isFile() && entry.name.endsWith(".md")) {
      files.push(absolute);
    }
  }

  return files;
}

function relative(file) {
  return path.relative(root, file).replaceAll(path.sep, "/");
}

function normalizeLinkTarget(rawTarget) {
  let target = rawTarget.trim();

  if (target.startsWith("<") && target.includes(">")) {
    target = target.slice(1, target.indexOf(">"));
  } else {
    target = target.split(/\s+["']/u, 1)[0];
  }

  return target;
}

const credentialPatterns = [
  ["Google OAuth client secret", /\bGOCSPX-[A-Za-z0-9_-]{10,}\b/gu],
  ["Supabase secret key", /\bsb_secret_[A-Za-z0-9_-]{16,}\b/gu],
  ["Supabase publishable key literal", /\bsb_publishable_[A-Za-z0-9_-]{16,}\b/gu],
  ["GitHub token", /\bgh[oprsu]_[A-Za-z0-9_]{20,}\b/gu],
  ["JWT", /\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\b/gu],
];

const markdownFiles = await walk(root);

for (const file of markdownFiles) {
  const content = await readFile(file, "utf8");

  if (!content.endsWith("\n")) {
    errors.push(`${relative(file)}: missing final newline`);
  }

  for (const [label, pattern] of credentialPatterns) {
    if (pattern.test(content)) {
      errors.push(`${relative(file)}: contains a value matching ${label}`);
    }
    pattern.lastIndex = 0;
  }

  const linkPattern = /!?\[[^\]]*\]\(([^)]+)\)/gu;
  for (const match of content.matchAll(linkPattern)) {
    const target = normalizeLinkTarget(match[1]);
    if (!target || /^(?:https?:\/\/|mailto:|#)/u.test(target)) {
      continue;
    }

    const pathOnly = target.split("#", 1)[0];
    if (!pathOnly) {
      continue;
    }

    let decoded;
    try {
      decoded = decodeURIComponent(pathOnly);
    } catch {
      errors.push(`${relative(file)}: invalid encoded link ${target}`);
      continue;
    }

    const resolved = path.resolve(path.dirname(file), decoded);
    try {
      await access(resolved);
    } catch {
      errors.push(`${relative(file)}: broken local link ${target}`);
    }
  }
}

if (errors.length > 0) {
  console.error("Documentation checks failed:");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exitCode = 1;
} else {
  console.log(`Documentation checks passed for ${markdownFiles.length} Markdown files.`);
}
