import { useState, useEffect, useCallback } from 'react';
import { formatEther, parseEther } from 'ethers';
import { ETH_ADDRESS } from '../config';
import { toast } from './Toast';

export function Balances({ account, contracts, currentChain, switchChain }) {
  const [l1Free, setL1Free] = useState(null);
  const [l1Locked, setL1Locked] = useState(null);
  const [l2Free, setL2Free] = useState(null);
  const [l1CacheFree, setL1CacheFree] = useState(null);
  const [l1CacheLocked, setL1CacheLocked] = useState(null);
  const [depositAmt, setDepositAmt] = useState('');
  const [withdrawAmt, setWithdrawAmt] = useState('');
  const [loading, setLoading] = useState(false);

  const fetchBalances = useCallback(async () => {
    if (!account) return;
    try {
      const [free, locked] = await Promise.all([
        contracts.vaultRead.freeBalance(account, ETH_ADDRESS),
        contracts.vaultRead.lockedBalance(account, ETH_ADDRESS),
      ]);
      setL1Free(free);
      setL1Locked(locked);
    } catch {
      /* devnet might be down */
    }
    try {
      const free = await contracts.marginRead.freeBalanceL2(account, ETH_ADDRESS);
      setL2Free(free);
    } catch {
      /* devnet might be down */
    }
    try {
      const [cf, cl] = await Promise.all([
        contracts.marginRead.l1FreeCache(ETH_ADDRESS, account),
        contracts.marginRead.l1LockedCache(ETH_ADDRESS, account),
      ]);
      setL1CacheFree(cf);
      setL1CacheLocked(cl);
    } catch {
      /* ignore */
    }
  }, [account, contracts]);

  useEffect(() => {
    fetchBalances();
    const iv = setInterval(fetchBalances, 8000);
    return () => clearInterval(iv);
  }, [fetchBalances]);

  const fmt = (v) => (v !== null ? formatEther(v) : '--');

  const handleDeposit = async (layer) => {
    if (!depositAmt || isNaN(Number(depositAmt))) {
      toast('Enter a valid amount');
      return;
    }
    setLoading(true);
    try {
      const value = parseEther(depositAmt);
      if (layer === 'L1') {
        if (currentChain !== 'L1') {
          await switchChain('L1');
          toast('Switched to L1 -- please retry deposit', 'info');
          setLoading(false);
          return;
        }
        const tx = await contracts.vault.deposit(ETH_ADDRESS, value, { value });
        toast('L1 deposit submitted...', 'info');
        await tx.wait();
        toast('L1 deposit confirmed', 'success');
      } else {
        if (currentChain !== 'L2') {
          await switchChain('L2');
          toast('Switched to L2 -- please retry deposit', 'info');
          setLoading(false);
          return;
        }
        const tx = await contracts.margin.depositL2(ETH_ADDRESS, value, { value });
        toast('L2 deposit submitted...', 'info');
        await tx.wait();
        toast('L2 deposit confirmed', 'success');
      }
      setDepositAmt('');
      fetchBalances();
    } catch (err) {
      toast(err.shortMessage || err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleWithdraw = async (layer) => {
    if (!withdrawAmt || isNaN(Number(withdrawAmt))) {
      toast('Enter a valid amount');
      return;
    }
    setLoading(true);
    try {
      const value = parseEther(withdrawAmt);
      if (layer === 'L1') {
        if (currentChain !== 'L1') {
          await switchChain('L1');
          toast('Switched to L1 -- please retry', 'info');
          setLoading(false);
          return;
        }
        const tx = await contracts.vault.withdraw(ETH_ADDRESS, value);
        await tx.wait();
        toast('L1 withdrawal confirmed', 'success');
      } else {
        if (currentChain !== 'L2') {
          await switchChain('L2');
          toast('Switched to L2 -- please retry', 'info');
          setLoading(false);
          return;
        }
        const tx = await contracts.margin.withdrawL2(ETH_ADDRESS, value);
        await tx.wait();
        toast('L2 withdrawal confirmed', 'success');
      }
      setWithdrawAmt('');
      fetchBalances();
    } catch (err) {
      toast(err.shortMessage || err.message);
    } finally {
      setLoading(false);
    }
  };

  const refreshCache = async () => {
    if (!account) return;
    setLoading(true);
    try {
      if (currentChain !== 'L2') {
        await switchChain('L2');
        toast('Switched to L2 -- please retry', 'info');
        setLoading(false);
        return;
      }
      const tx = await contracts.margin.verifyAndUpdateL1Balance(account, ETH_ADDRESS);
      await tx.wait();
      toast('L1 cache refreshed', 'success');
      fetchBalances();
    } catch (err) {
      toast(err.shortMessage || err.message);
    } finally {
      setLoading(false);
    }
  };

  if (!account) {
    return (
      <div className="panel balances-panel">
        <h3>Balances</h3>
        <p className="muted">Connect wallet to view</p>
      </div>
    );
  }

  return (
    <div className="panel balances-panel">
      <h3>Balances</h3>

      <div className="balance-section">
        <h4>L1 Vault</h4>
        <div className="balance-row">
          <span>Free ETH</span>
          <span className="mono">{fmt(l1Free)}</span>
        </div>
        <div className="balance-row">
          <span>Locked ETH</span>
          <span className="mono">{fmt(l1Locked)}</span>
        </div>
      </div>

      <div className="balance-section">
        <h4>L2 Margin</h4>
        <div className="balance-row">
          <span>Free ETH</span>
          <span className="mono">{fmt(l2Free)}</span>
        </div>
      </div>

      <div className="balance-section">
        <h4>L1 Cache on L2</h4>
        <div className="balance-row">
          <span>Cached Free</span>
          <span className="mono">{fmt(l1CacheFree)}</span>
        </div>
        <div className="balance-row">
          <span>Cached Locked</span>
          <span className="mono">{fmt(l1CacheLocked)}</span>
        </div>
        <button className="btn btn-sm btn-full" onClick={refreshCache} disabled={loading}>
          Refresh L1 Cache
        </button>
      </div>

      <div className="balance-section">
        <h4>Deposit</h4>
        <input
          className="input"
          type="text"
          placeholder="Amount (ETH)"
          value={depositAmt}
          onChange={(e) => setDepositAmt(e.target.value)}
        />
        <div className="btn-row">
          <button className="btn btn-sm" onClick={() => handleDeposit('L1')} disabled={loading}>
            L1 Vault
          </button>
          <button className="btn btn-sm" onClick={() => handleDeposit('L2')} disabled={loading}>
            L2 Margin
          </button>
        </div>
      </div>

      <div className="balance-section">
        <h4>Withdraw</h4>
        <input
          className="input"
          type="text"
          placeholder="Amount (ETH)"
          value={withdrawAmt}
          onChange={(e) => setWithdrawAmt(e.target.value)}
        />
        <div className="btn-row">
          <button className="btn btn-sm" onClick={() => handleWithdraw('L1')} disabled={loading}>
            L1 Vault
          </button>
          <button className="btn btn-sm" onClick={() => handleWithdraw('L2')} disabled={loading}>
            L2 Margin
          </button>
        </div>
      </div>
    </div>
  );
}
