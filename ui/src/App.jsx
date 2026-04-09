import { useWallet } from './hooks/useWallet';
import { useContracts } from './hooks/useContracts';
import { Header } from './components/Header';
import { Balances } from './components/Balances';
import { OrderBookPanel } from './components/OrderBookPanel';
import { TradePanel } from './components/TradePanel';
import { OpenOrders } from './components/OpenOrders';
import { ToastContainer } from './components/Toast';

export default function App() {
  const wallet = useWallet();
  const contracts = useContracts(wallet.signer);

  return (
    <div className="app">
      <ToastContainer />
      <Header
        account={wallet.account}
        chainId={wallet.chainId}
        currentChain={wallet.currentChain}
        connect={wallet.connect}
        switchChain={wallet.switchChain}
      />

      <main className="main-grid">
        <Balances
          account={wallet.account}
          contracts={contracts}
          currentChain={wallet.currentChain}
          switchChain={wallet.switchChain}
        />
        <OrderBookPanel contracts={contracts} />
        <TradePanel
          account={wallet.account}
          contracts={contracts}
          currentChain={wallet.currentChain}
          switchChain={wallet.switchChain}
        />
      </main>

      <OpenOrders
        account={wallet.account}
        contracts={contracts}
        currentChain={wallet.currentChain}
        switchChain={wallet.switchChain}
      />
    </div>
  );
}
