// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IERC20Min {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/// @title OrderBookVenue
/// @notice A minimal escrowed limit order book. Self-deployed stand-in for the
///         Exchange OS venue primitives, which have no testnet surface. See
///         docs/decisions/ADR-001-venue-strategy.md.
///
/// What is genuinely real here, and therefore not fakeable:
/// - Makers escrow the asset they are selling at post time. The contract holds it.
/// - Takers transfer the opposite asset in the same transaction they receive.
/// - Every fill emits an event with the actual amounts moved.
///
/// What is deliberately NOT here, stated rather than implied: no price-time
/// priority matching engine, no funding rates, no liquidation engine. Takers
/// select an order explicitly. ADR-006 records why.
contract OrderBookVenue {
    struct Order {
        address maker;
        address base;
        address quote;
        /// @dev true when the maker is buying base and paying quote.
        bool makerBuysBase;
        uint256 sizeBase;
        /// @dev quote units per 1e18 base units.
        uint256 priceQuote;
        uint256 filledBase;
        bool cancelled;
    }

    Order[] public orders;

    event OrderPosted(
        uint256 indexed id,
        address indexed maker,
        bytes32 indexed market,
        bool makerBuysBase,
        uint256 sizeBase,
        uint256 priceQuote
    );
    event OrderFilled(
        uint256 indexed id,
        address indexed taker,
        uint256 baseAmount,
        uint256 quoteAmount,
        uint256 remainingBase
    );
    event OrderCancelled(uint256 indexed id, uint256 refundedBase, uint256 refundedQuote);

    error TransferFailed(address token, address from, address to, uint256 amount);
    error NotMaker();
    error AlreadyCancelled();
    error NothingToFill();
    error FillExceedsRemaining(uint256 requested, uint256 remaining);
    error ZeroAmount();

    /// @dev Checked transfer helpers. forge lint flagged the raw calls, and it was
    ///      right: a token that returns false instead of reverting would let a
    ///      "fill" record itself while no value moved. Our MockERC20 reverts, so
    ///      today the risk is zero, but the venue must not depend on that, because
    ///      the migration target is tokens we do not control.
    function _pull(address token, address from, address to, uint256 amount) internal {
        if (!IERC20Min(token).transferFrom(from, to, amount)) {
            revert TransferFailed(token, from, to, amount);
        }
    }

    function _push(address token, address to, uint256 amount) internal {
        if (!IERC20Min(token).transfer(to, amount)) {
            revert TransferFailed(token, address(this), to, amount);
        }
    }

    /// @notice Deterministic market id from the token pair. Used by RiskGuard so
    ///         offchain and onchain agree on what a market is without a registry.
    function marketId(address base, address quote) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(base, quote));
    }

    function orderCount() external view returns (uint256) {
        return orders.length;
    }

    function remainingBase(uint256 id) public view returns (uint256) {
        Order storage o = orders[id];
        if (o.cancelled) return 0;
        return o.sizeBase - o.filledBase;
    }

    /// @notice Quote amount owed for a given base amount at an order's price.
    ///         One place only, because this is where a rounding bug would live.
    function quoteFor(uint256 id, uint256 baseAmount) public view returns (uint256) {
        return (baseAmount * orders[id].priceQuote) / 1e18;
    }

    /// @notice Post an order, escrowing what the maker is selling.
    function postOrder(
        address base,
        address quote,
        bool makerBuysBase,
        uint256 sizeBase,
        uint256 priceQuote
    ) external returns (uint256 id) {
        if (sizeBase == 0 || priceQuote == 0) revert ZeroAmount();

        if (makerBuysBase) {
            // Maker pays quote, so escrow the full quote cost up front.
            uint256 cost = (sizeBase * priceQuote) / 1e18;
            if (cost == 0) revert ZeroAmount();
            _pull(quote, msg.sender, address(this), cost);
        } else {
            // Maker sells base, so escrow the base.
            _pull(base, msg.sender, address(this), sizeBase);
        }

        id = orders.length;
        orders.push(
            Order({
                maker: msg.sender,
                base: base,
                quote: quote,
                makerBuysBase: makerBuysBase,
                sizeBase: sizeBase,
                priceQuote: priceQuote,
                filledBase: 0,
                cancelled: false
            })
        );

        emit OrderPosted(id, msg.sender, marketId(base, quote), makerBuysBase, sizeBase, priceQuote);
    }

    /// @notice Take against a resting order. Partial fills allowed.
    function take(uint256 id, uint256 baseAmount) external returns (uint256 quoteAmount) {
        if (baseAmount == 0) revert ZeroAmount();
        Order storage o = orders[id];
        if (o.cancelled) revert AlreadyCancelled();

        uint256 rem = o.sizeBase - o.filledBase;
        if (rem == 0) revert NothingToFill();
        if (baseAmount > rem) revert FillExceedsRemaining(baseAmount, rem);

        quoteAmount = (baseAmount * o.priceQuote) / 1e18;
        if (quoteAmount == 0) revert ZeroAmount();

        o.filledBase += baseAmount;

        if (o.makerBuysBase) {
            // Taker sells base to the maker, receives escrowed quote.
            _pull(o.base, msg.sender, o.maker, baseAmount);
            _push(o.quote, msg.sender, quoteAmount);
        } else {
            // Taker buys base from escrow, pays quote to the maker.
            _pull(o.quote, msg.sender, o.maker, quoteAmount);
            _push(o.base, msg.sender, baseAmount);
        }

        emit OrderFilled(id, msg.sender, baseAmount, quoteAmount, o.sizeBase - o.filledBase);
    }

    /// @notice Cancel and refund the unfilled remainder.
    function cancel(uint256 id) external {
        Order storage o = orders[id];
        if (msg.sender != o.maker) revert NotMaker();
        if (o.cancelled) revert AlreadyCancelled();

        uint256 rem = o.sizeBase - o.filledBase;
        o.cancelled = true;

        uint256 refundBase;
        uint256 refundQuote;
        if (rem > 0) {
            if (o.makerBuysBase) {
                refundQuote = (rem * o.priceQuote) / 1e18;
                if (refundQuote > 0) _push(o.quote, o.maker, refundQuote);
            } else {
                refundBase = rem;
                _push(o.base, o.maker, refundBase);
            }
        }
        emit OrderCancelled(id, refundBase, refundQuote);
    }
}
