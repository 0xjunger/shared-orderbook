import { CHAINS } from '../config';

export function Header({ account, chainId, currentChain, connect, switchChain }) {
  const shortAddr = account
    ? `${account.slice(0, 6)}...${account.slice(-4)}`
    : null;

  const chainLabel =
    currentChain
      ? `${currentChain} (${chainId})`
      : chainId
        ? `Unknown (${chainId})`
        : 'Not connected';

  return (
    <header className="header">
      <div className="header-left">
        <span className="logo">Shared Orderbook</span>
        <span className="pair-label">ETH / ETH</span>
      </div>

      <div className="header-right">
        <span className="chain-badge">{chainLabel}</span>

        <button
          className="btn btn-sm"
          onClick={() => switchChain('L1')}
          disabled={currentChain === 'L1'}
        >
          L1
        </button>
        <button
          className="btn btn-sm"
          onClick={() => switchChain('L2')}
          disabled={currentChain === 'L2'}
        >
          L2
        </button>

        {account ? (
          <span className="address-badge">{shortAddr}</span>
        ) : (
          <button className="btn btn-primary" onClick={connect}>
            Connect Wallet
          </button>
        )}
      </div>
    </header>
  );
}
