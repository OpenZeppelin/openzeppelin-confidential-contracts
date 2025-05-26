const proc = require("child_process");
const read = (cmd) => proc.execSync(cmd, { encoding: "utf8" }).trim();
const run = (cmd) => {
  proc.execSync(cmd, { stdio: "inherit" });
};
const tryRead = (cmd) => {
  try {
    return read(cmd);
  } catch {
    return undefined;
  }
};

// For the time being, the confidential contracts repo will undergo rapid development. We will want docs to update live.
// The master branch is used for development, and the docs are updated from there.
// Use /^release-v(?<version>(?<major>\d+)\.(?<minor>\d+)(?:\.(?<patch>\d+))?)$/ for a release branch
const masterBranch = /^master$/;

const currentBranch = read("git rev-parse --abbrev-ref HEAD");
const match = currentBranch.match(masterBranch);

if (!match) {
  console.error("Not currently on master branch");
  process.exit(1);
}

const pkgVersion = require("../package.json").version;

if (pkgVersion.includes("-") && !pkgVersion.includes(".0.0-")) {
  console.error("Refusing to update docs: non-major prerelease detected");
  process.exit(0);
}

const current = match.groups;
const major = current?.major ?? pkgVersion.split(".")[0];
const minor = current?.minor ?? pkgVersion.split(".")[1];
const docsBranch = `docs-v${major}.x`;

// Fetch remotes and find the docs branch if it exists
run("git fetch --all --no-tags");
const matchingDocsBranches = tryRead(`git rev-parse --glob='*/${docsBranch}'`);

if (!matchingDocsBranches) {
  // Create the branch
  run(`git checkout --orphan ${docsBranch}`);
} else {
  const [publishedRef, ...others] = new Set(matchingDocsBranches.split("\n"));
  if (others.length > 0) {
    console.error(
      `Found conflicting ${docsBranch} branches.\n` +
        "Either local branch is outdated or there are multiple matching remote branches.",
    );
    process.exit(1);
  }
  const publishedVersion = JSON.parse(read(`git show ${publishedRef}:package.json`)).version;
  const publishedMinor = publishedVersion.match(/\d+\.(?<minor>\d+)\.\d+/).groups.minor;
  if (minor < publishedMinor) {
    console.error("Refusing to update docs: newer version is published");
    process.exit(0);
  }

  run("git checkout --quiet --detach");
  run(`git reset --soft ${publishedRef}`);
  run(`git checkout ${docsBranch}`);
}

run("npm run prepare-docs");
run("git add -f docs"); // --force needed because generated docs files are gitignored
run('git commit --no-verify -m "Update docs"');
run(`git checkout ${currentBranch}`);
