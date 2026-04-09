import { useState, useCallback, useEffect } from 'react';
import { BrowserProvider } from 'ethers';
import { CHAINS } from '../config';

/**
 * Hook managing MetaMask wallet connection and chain switching.
 * Returns the connected address, provider, signer, and current chain info.
 */
export function useWallet() {
  const [account, setAccount] = useState(null);
  const [chainId, setChainId] = useState(null);
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);

  const currentChain =
    chainId === CHAINS.L1.chainId
      ? 'L1'
      : chainId === CHAINS.L2.chainId
        ? 'L2'
        : null;

  /** Sync internal state from whatever MetaMask currently reports */
  const syncState = useCallback(async () => {
    if (!window.ethereum) return;
    try {
      const p = new BrowserProvider(window.ethereum);
      const network = await p.getNetwork();
      setChainId(Number(network.chainId));
      setProvider(p);
      const accounts = await p.listAccounts();
      if (accounts.length > 0) {
        setAccount(accounts[0].address);
        setSigner(accounts[0]);
      }
    } catch {
      /* not connected yet — fine */
    }
  }, []);

  /** Request wallet connection */
  const connect = useCallback(async () => {
    if (!window.ethereum) {
      throw new Error('MetaMask not detected');
    }
    await window.ethereum.request({ method: 'eth_requestAccounts' });
    await syncState();
  }, [syncState]);

  /** Switch MetaMask to a given chain, adding it if unknown */
  const switchChain = useCallback(
    async (layer) => {
      const chain = CHAINS[layer];
      if (!chain || !window.ethereum) return;
      try {
        await window.ethereum.request({
          method: 'wallet_switchEthereumChain',
          params: [{ chainId: chain.chainIdHex }],
        });
      } catch (err) {
        // 4902 = chain not added yet
        if (err.code === 4902) {
          await window.ethereum.request({
            method: 'wallet_addEthereumChain',
            params: [
              {
                chainId: chain.chainIdHex,
                chainName: chain.name,
                rpcUrls: [chain.rpc],
                nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
              },
            ],
          });
        } else {
          throw err;
        }
      }
      await syncState();
    },
    [syncState],
  );

  /** Listen for MetaMask events */
  useEffect(() => {
    if (!window.ethereum) return;
    const handleChain = () => syncState();
    const handleAccounts = () => syncState();
    window.ethereum.on('chainChanged', handleChain);
    window.ethereum.on('accountsChanged', handleAccounts);
    // initial sync
    syncState();
    return () => {
      window.ethereum.removeListener('chainChanged', handleChain);
      window.ethereum.removeListener('accountsChanged', handleAccounts);
    };
  }, [syncState]);

  return { account, chainId, currentChain, provider, signer, connect, switchChain };
}
