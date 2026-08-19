/// <reference types="vite/client" />

/**
 * Typed build-time configuration.
 *
 * Vite replaces `import.meta.env.*` at build time. Declaring the shape here means a typo in an
 * env var name is a compile error rather than an `undefined` that silently falls through to a
 * default at runtime.
 */
interface ImportMetaEnv {
  /**
   * WalletConnect project id. Public by design: it is a client-side identifier shipped in every
   * dapp bundle, authorises nothing and holds no funds. Set it to use your own on a fork.
   */
  readonly VITE_WALLETCONNECT_PROJECT_ID?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
