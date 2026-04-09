import { useState, useEffect, useCallback } from 'react';
import { parseEther, formatEther } from 'ethers';
import { toast } from './Toast';

export function TradePanel({ account, contracts, currentChain, switchChain }) {
  const [orderType, setOrderType] = useState('LIMIT');
  const [side, setSide] = useState(0); // 0=BUY, 1=SELL
  const [price, setPrice] = useState('');
  const [quantity, setQuantity] = useState('');
  const [useL1, setUseL1] = useState(false);
  const [loading, setLoading] = useState(false);
  const [trades, setTrades] = useState([]);

  /** Fetch recent trades from SettlementL2 */
  const fetchTrades = useCallback(async () => {
    try {
      const nextId = await contracts.settlementL2Read.nextTradeId();
      const n = Number(nextId);
      const start = Math.max(0, n - 20);
      const results = [];
      for (let i = n - 1; i >= start; i--) {
        try {
          const t = await contracts.settlementL2Read.trades(i);
          results.push({
            tradeId: Number(t[0]),
            maker: t[1],
            taker: t[2],
            price: t[3],
            baseAmount: t[4],
            quoteAmount: t[5],
            crossChain: t[6],
            timestamp: Number(t[7]),
          });
        } catch {
          break;
        }
      }
      setTrades(results);
    } catch {
      /* settlement contract might not be reachable */
    }
  }, [contracts]);

  useEffect(() => {
    fetchTrades();
    const iv = setInterval(fetchTrades, 8000);
    return () => clearInterval(iv);
  }, [fetchTrades]);

  const placeOrder = async () => {
    if (!account) {
      toast('Connect wallet first');
      return;
    }
    if (!quantity || isNaN(Number(quantity))) {
      toast('Enter a valid quantity');
      return;
    }
    if (orderType === 'LIMIT' && (!price || isNaN(Number(price)))) {
      toast('Enter a valid price for limit order');
      return;
    }
    if (currentChain !== 'L2') {
      await switchChain('L2');
      toast('Switched to L2 -- please retry', 'info');
      return;
    }
    if (!contracts.engine) {
      toast('Engine contract not available');
      return;
    }

    setLoading(true);
    try {
      const qty = parseEther(quantity);
      if (orderType === 'LIMIT') {
        const px = parseEther(price);
        const tx = await contracts.engine.placeLimitOrder(side, px, qty, useL1);
        toast('Limit order submitted...', 'info');
        await tx.wait();
        toast('Limit order placed', 'success');
      } else {
        const tx = await contracts.engine.placeMarketOrder(side, qty);
        toast('Market order submitted...', 'info');
        await tx.wait();
        toast('Market order filled', 'success');
      }
      setPrice('');
      setQuantity('');
      fetchTrades();
    } catch (err) {
      toast(err.shortMessage || err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="panel trade-panel">
      <h3>Place Order</h3>

      <div className="toggle-row">
        <button
          className={`toggle-btn ${orderType === 'LIMIT' ? 'active' : ''}`}
          onClick={() => setOrderType('LIMIT')}
        >
          Limit
        </button>
        <button
          className={`toggle-btn ${orderType === 'MARKET' ? 'active' : ''}`}
          onClick={() => setOrderType('MARKET')}
        >
          Market
        </button>
      </div>

      <div className="toggle-row">
        <button
          className={`toggle-btn buy ${side === 0 ? 'active' : ''}`}
          onClick={() => setSide(0)}
        >
          Buy
        </button>
        <button
          className={`toggle-btn sell ${side === 1 ? 'active' : ''}`}
          onClick={() => setSide(1)}
        >
          Sell
        </button>
      </div>

      {orderType === 'LIMIT' && (
        <input
          className="input"
          type="text"
          placeholder="Price (ETH)"
          value={price}
          onChange={(e) => setPrice(e.target.value)}
        />
      )}

      <input
        className="input"
        type="text"
        placeholder="Quantity"
        value={quantity}
        onChange={(e) => setQuantity(e.target.value)}
      />

      <label className="checkbox-label">
        <input
          type="checkbox"
          checked={useL1}
          onChange={(e) => setUseL1(e.target.checked)}
        />
        Use L1 Collateral
      </label>

      <button
        className={`btn btn-full ${side === 0 ? 'btn-buy' : 'btn-sell'}`}
        onClick={placeOrder}
        disabled={loading || !account}
      >
        {loading
          ? 'Submitting...'
          : `${side === 0 ? 'Buy' : 'Sell'} ${orderType === 'LIMIT' ? 'Limit' : 'Market'}`}
      </button>

      <h4 className="mt">Recent Trades</h4>
      <div className="trades-list">
        {trades.length === 0 ? (
          <p className="muted">No trades yet</p>
        ) : (
          <table className="mini-table">
            <thead>
              <tr>
                <th>Price</th>
                <th>Qty</th>
                <th>Time</th>
              </tr>
            </thead>
            <tbody>
              {trades.map((t) => (
                <tr key={t.tradeId}>
                  <td className="mono">{formatEther(t.price)}</td>
                  <td className="mono">{formatEther(t.baseAmount)}</td>
                  <td className="muted">
                    {new Date(t.timestamp * 1000).toLocaleTimeString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
