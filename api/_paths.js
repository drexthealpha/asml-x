/**
 * Every OKX path these functions use, with its METHOD, verified against the live API.
 *
 * WHY THIS FILE EXISTS. The serverless functions were written by transcribing the CLI's behaviour
 * from memory. Three paths were wrong:
 *
 *   market/price        called as GET; it is POST with a JSON body
 *   market/price-info   called as GET; it is POST with a JSON body
 *   index-price         invented entirely; the real path is /api/v6/dex/index/current-price
 *
 * None of them errored. The signed helper returned null, every price became null, and the deployed
 * site rendered "no price" for eighteen tokens that all have one. It read as a dead market rather
 * than a broken client, which is the worst way for a bug to present.
 *
 * That is the same failure as the invented contract selectors, one layer up: a call that silently
 * returns nothing is indistinguishable from an honest absence.
 *
 * THE RULE NOW: no path appears here until `scripts/232-verify-rest-paths.sh` has printed it
 * beside real data, and no function calls a path that is not in this file.
 *
 * Verified 2026-08-19, output in evidence/phase20/rest-paths.txt.
 */

export const PATHS = {
  /** GET. The chain's own token listing. 22 rows on chain 196. */
  allTokens: (chain) => ({
    method: "GET",
    path: `/api/v6/dex/aggregator/all-tokens?chainIndex=${chain}`,
  }),

  /** POST. Batch price. Takes an array of {chainIndex, tokenContractAddress}. */
  price: () => ({ method: "POST", path: "/api/v6/dex/market/price" }),

  /** POST. Market cap, liquidity, 24h change, holders. Same body shape as price. */
  priceInfo: () => ({ method: "POST", path: "/api/v6/dex/market/price-info" }),

  /**
   * POST. The aggregated index price, the INDEPENDENT second source.
   *
   * This is the one that matters most, and the one I had most wrong. Without it the RWA divergence
   * check compares a price to itself, which is always zero and therefore always passes.
   */
  indexPrice: () => ({ method: "POST", path: "/api/v6/dex/index/current-price" }),

  /** GET. An executable route, with venues and price impact. */
  quote: (chain, from, to, amount) => ({
    method: "GET",
    path:
      `/api/v6/dex/aggregator/quote?chainIndex=${chain}&amount=${amount}` +
      `&fromTokenAddress=${from}&toTokenAddress=${to}`,
  }),

  /**
   * POST. DeFi products. The prefix is `defi`, not `dex`, and the method is POST: GET returns 405.
   * Body: {chainIndex, productGroup, tokenKeywords[]}. Returns 10 products on chain 196, where the
   * narrower path this replaced returned 2.
   */
  defiSearch: () => ({ method: "POST", path: "/api/v6/defi/product/search" }),

  /**
   * GET. Token search, across a far larger universe than all-tokens covers.
   *
   * THE PARAMETERS ARE `chains` AND `search`. Not chainIndex, not keyword, not query. Four other
   * spellings returned code 50014 with an empty list, which reads as "nothing on this chain"
   * rather than "you named the parameter wrong". This is the endpoint that carries the eighteen
   * tokenized equities `all-tokens` does not list, and searching it wrongly is how they were
   * reported as absent from X Layer twice.
   */
  tokenSearch: (chain, query, limit = 50) => ({
    method: "GET",
    path:
      `/api/v6/dex/market/token/search?chains=${chain}` +
      `&search=${encodeURIComponent(query)}&limit=${limit}`,
  }),

  /** GET. Top pools for one token. */
  tokenLiquidity: (chain, address) => ({
    method: "GET",
    path: `/api/v6/dex/market/token-liquidity?chainIndex=${chain}&tokenContractAddress=${address}`,
  }),
};

/** The batch body both POST endpoints take. */
export const batch = (chain, addresses) =>
  addresses.map((a) => ({ chainIndex: chain, tokenContractAddress: a }));
