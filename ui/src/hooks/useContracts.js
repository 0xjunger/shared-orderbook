import { useMemo } from 'react';
import { Contract, JsonRpcProvider } from 'ethers';
import {
  ADDRESSES,
  CHAINS,
  VAULT_ABI,
  MARGIN_ABI,
  BOOK_ABI,
  ENGINE_ABI,
  SETTLEMENT_L2_ABI,
} from '../config';

/**
 * Returns read-only contract instances (via JsonRpcProvider) and
 * signer-connected instances when a signer is available.
 */
export function useContracts(signer) {
  const l1Provider = useMemo(
    () => new JsonRpcProvider(CHAINS.L1.rpc),
    [],
  );
  const l2Provider = useMemo(
    () => new JsonRpcProvider(CHAINS.L2.rpc),
    [],
  );

  // Read-only contracts (always available — no wallet needed)
  const vaultRead = useMemo(
    () => new Contract(ADDRESSES.VAULT, VAULT_ABI, l1Provider),
    [l1Provider],
  );
  const marginRead = useMemo(
    () => new Contract(ADDRESSES.MARGIN, MARGIN_ABI, l2Provider),
    [l2Provider],
  );
  const bookRead = useMemo(
    () => new Contract(ADDRESSES.BOOK, BOOK_ABI, l2Provider),
    [l2Provider],
  );
  const settlementL2Read = useMemo(
    () => new Contract(ADDRESSES.SETTLEMENT_L2, SETTLEMENT_L2_ABI, l2Provider),
    [l2Provider],
  );

  // Signer-connected contracts (only when wallet is connected)
  const vault = useMemo(
    () => (signer ? new Contract(ADDRESSES.VAULT, VAULT_ABI, signer) : null),
    [signer],
  );
  const margin = useMemo(
    () => (signer ? new Contract(ADDRESSES.MARGIN, MARGIN_ABI, signer) : null),
    [signer],
  );
  const engine = useMemo(
    () => (signer ? new Contract(ADDRESSES.ENGINE, ENGINE_ABI, signer) : null),
    [signer],
  );

  return {
    l1Provider,
    l2Provider,
    // read-only
    vaultRead,
    marginRead,
    bookRead,
    settlementL2Read,
    // write (signer)
    vault,
    margin,
    engine,
  };
}
