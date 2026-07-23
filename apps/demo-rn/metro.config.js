const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('@react-native/metro-config').MetroConfig}
 */
const projectRoot = __dirname;
// Yarn workspaces monorepo root (apps/demo-rn/../..) — needed so Metro can
// see the hoisted root node_modules (react-native itself, @babel/runtime,
// etc.) and the sea-react-native workspace package it symlinks in.
const workspaceRoot = path.resolve(projectRoot, '../..');

const config = {
  watchFolders: [workspaceRoot],
  resolver: {
    nodeModulesPaths: [
      path.resolve(projectRoot, 'node_modules'),
      path.resolve(workspaceRoot, 'node_modules'),
    ],
    // sea-react-native's package.json exports a "sea-react-native-source"
    // condition pointing at src/index.tsx (create-react-native-library's
    // dev-mode convention) — this resolves straight to TS source instead
    // of the built lib/ output, so no `bob build` step is needed in dev.
    unstable_enablePackageExports: true,
    unstable_conditionNames: ['require', 'react-native', 'sea-react-native-source'],
  },
};

module.exports = mergeConfig(getDefaultConfig(projectRoot), config);
