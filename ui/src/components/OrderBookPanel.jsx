import { useState, useEffect, useCallback } from 'react';
import { formatEther } from 'ethers';

/**
 * Visual orderbook: asks (red) on top sorted ascending, bids (green) on bottom sorted descending.
 * Spread displayed between them.
 */
export function OrderBookPanel({ contracts }) {
  const [asks, setAsks] = useState([]); // [{price, totalQty}]
  const [bids, setBids] = useState([]);
  const [bestBid, setBestBid] = useState(null);
  const [bestAsk, setBestAsk] = useState(null);
  const [error, setError] = useState(false);

  const fetchBook = useCallback(async () => {
    try {
      // Fetch all price levels
      const [buyPrices, sellPrices] = await Promise.all([
        contracts.bookRead.getBuyPrices(),
        contracts.bookRead.getSellPrices(),
      ]);

      // For each price level, sum the quantities of all orders
      const buildLevel = async (side, price) => {
        const orderIds = await contracts.bookRead.getOrdersAtPrice(side, price);
        let totalQty = 0n;
        for (const id of orderIds) {
          const order = await contracts.bookRead.getOrder(id);
          // Only count OPEN or PARTIALLY_FILLED
          if (order.status <= 1) {
            totalQty += order.quantity - order.filledQuantity;
          }
        }
        return { price, totalQty };
      };

      const bidLevels = await Promise.all(
        buyPrices.map((p) => buildLevel(0, p)),
      );
      const askLevels = await Promise.all(
        sellPrices.map((p) => buildLevel(1, p)),
      );

      // Filter out empty levels
      const filteredBids = bidLevels.filter((l) => l.totalQty > 0n);
      const filteredAsks = askLevels.filter((l) => l.totalQty > 0n);

      // Sort: bids descending, asks ascending
      filteredBids.sort((a, b) => (a.price > b.price ? -1 : 1));
      filteredAsks.sort((a, b) => (a.price < b.price ? -1 : 1));

      setBids(filteredBids);
      setAsks(filteredAsks);

      // Best bid/ask
      try {
        const [bb, ba] = await Promise.all([
          contracts.bookRead.getBestBid(),
          contracts.bookRead.getBestAsk(),
        ]);
        setBestBid(bb.price > 0n ? bb : null);
        setBestAsk(ba.price > 0n ? ba : null);
      } catch {
        setBestBid(null);
        setBestAsk(null);
      }

      setError(false);
    } catch {
      setError(true);
    }
  }, [contracts]);

  useEffect(() => {
    fetchBook();
    const iv = setInterval(fetchBook, 5000);
    return () => clearInterval(iv);
  }, [fetchBook]);

  const fmt = (v) => formatEther(v);

  // Find max qty for bar width scaling
  const allQtys = [...asks, ...bids].map((l) => l.totalQty);
  const maxQty = allQtys.length > 0 ? allQtys.reduce((a, b) => (a > b ? a : b), 0n) : 1n;

  const spread =
    bestBid && bestAsk ? bestAsk.price - bestBid.price : null;

  const renderRow = (level, side) => {
    const pct = maxQty > 0n ? Number((level.totalQty * 10000n) / maxQty) / 100 : 0;
    return (
      <div className={`ob-row ob-${side}`} key={`${side}-${level.price}`}>
        <div
          className={`ob-bar ob-bar-${side}`}
          style={{ width: `${pct}%` }}
        />
        <span className="ob-price">{fmt(level.price)}</span>
        <span className="ob-qty">{fmt(level.totalQty)}</span>
      </div>
    );
  };

  return (
    <div className="panel orderbook-panel">
      <h3>Order Book</h3>
      {error ? (
        <p className="muted">Unable to fetch orderbook</p>
      ) : (
        <div className="ob-container">
          <div className="ob-header-row">
            <span>Price (ETH)</span>
            <span>Quantity</span>
          </div>

          <div className="ob-asks">
            {asks.length === 0 ? (
              <p className="muted ob-empty">No asks</p>
            ) : (
              /* Reverse so lowest ask is closest to spread */
              [...asks].reverse().map((l) => renderRow(l, 'ask'))
            )}
          </div>

          <div className="ob-spread">
            {spread !== null ? (
              <>Spread: {fmt(spread)}</>
            ) : (
              'No spread'
            )}
          </div>

          <div className="ob-bids">
            {bids.length === 0 ? (
              <p className="muted ob-empty">No bids</p>
            ) : (
              bids.map((l) => renderRow(l, 'bid'))
            )}
          </div>
        </div>
      )}
    </div>
  );
}
