import { useState, useEffect, useCallback } from 'react';
import { formatEther } from 'ethers';
import { toast } from './Toast';

const SIDE_LABELS = ['BUY', 'SELL'];
const STATUS_LABELS = ['OPEN', 'PARTIAL', 'FILLED', 'CANCELLED'];

export function OpenOrders({ account, contracts, currentChain, switchChain }) {
  const [orders, setOrders] = useState([]);
  const [cancelling, setCancelling] = useState(null);

  const fetchOrders = useCallback(async () => {
    if (!account) {
      setOrders([]);
      return;
    }
    try {
      const nextId = await contracts.bookRead.nextOrderId();
      const n = Number(nextId);
      const results = [];
      // Scan backwards to find user's orders (cap scan at 200 for perf)
      const start = Math.max(0, n - 200);
      for (let i = n - 1; i >= start; i--) {
        try {
          const o = await contracts.bookRead.getOrder(i);
          if (
            o.trader.toLowerCase() === account.toLowerCase() &&
            o.status <= 1 // OPEN or PARTIALLY_FILLED
          ) {
            results.push({
              orderId: Number(o.orderId),
              side: Number(o.side),
              orderType: Number(o.orderType),
              price: o.price,
              quantity: o.quantity,
              filledQuantity: o.filledQuantity,
              status: Number(o.status),
              isL1Backed: o.isL1Backed,
            });
          }
        } catch {
          /* order might not exist */
        }
      }
      setOrders(results);
    } catch {
      /* ignore */
    }
  }, [account, contracts]);

  useEffect(() => {
    fetchOrders();
    const iv = setInterval(fetchOrders, 8000);
    return () => clearInterval(iv);
  }, [fetchOrders]);

  const cancelOrder = async (orderId) => {
    if (currentChain !== 'L2') {
      await switchChain('L2');
      toast('Switched to L2 -- please retry cancel', 'info');
      return;
    }
    if (!contracts.engine) {
      toast('Engine contract not available');
      return;
    }
    setCancelling(orderId);
    try {
      const tx = await contracts.engine.cancelOrder(orderId);
      await tx.wait();
      toast(`Order #${orderId} cancelled`, 'success');
      fetchOrders();
    } catch (err) {
      toast(err.shortMessage || err.message);
    } finally {
      setCancelling(null);
    }
  };

  return (
    <div className="panel open-orders-panel">
      <h3>Open Orders</h3>
      {!account ? (
        <p className="muted">Connect wallet to view</p>
      ) : orders.length === 0 ? (
        <p className="muted">No open orders</p>
      ) : (
        <table className="orders-table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Side</th>
              <th>Price</th>
              <th>Qty</th>
              <th>Filled</th>
              <th>Status</th>
              <th>L1</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {orders.map((o) => (
              <tr key={o.orderId}>
                <td className="mono">{o.orderId}</td>
                <td className={o.side === 0 ? 'green' : 'red'}>
                  {SIDE_LABELS[o.side]}
                </td>
                <td className="mono">{formatEther(o.price)}</td>
                <td className="mono">{formatEther(o.quantity)}</td>
                <td className="mono">{formatEther(o.filledQuantity)}</td>
                <td>{STATUS_LABELS[o.status]}</td>
                <td>{o.isL1Backed ? 'Yes' : 'No'}</td>
                <td>
                  <button
                    className="btn btn-sm btn-danger"
                    onClick={() => cancelOrder(o.orderId)}
                    disabled={cancelling === o.orderId}
                  >
                    {cancelling === o.orderId ? '...' : 'Cancel'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
