/** Contract addresses from devnet deployment */
export const ADDRESSES = {
  VAULT: '0x663F3ad617193148711d28f5334eE4Ed07016602',
  SETTLEMENT_L1: '0x2E983A1Ba5e8b38AAAeC4B440B9dDcFBf72E15d1',
  MARGIN: '0x663F3ad617193148711d28f5334eE4Ed07016602',
  BOOK: '0x2E983A1Ba5e8b38AAAeC4B440B9dDcFBf72E15d1',
  SETTLEMENT_L2: '0x8438Ad1C834623CfF278AB6829a248E37C2D7E3f',
  ENGINE: '0xBC9129Dc0487fc2E169941C75aABC539f208fb01',
};

export const ETH_ADDRESS = '0x0000000000000000000000000000000000000000';

export const CHAINS = {
  L1: {
    chainId: 1337,
    chainIdHex: '0x539',
    name: 'L1 Devnet',
    rpc: 'http://localhost:9555',
  },
  L2: {
    chainId: 42069,
    chainIdHex: '0xa455',
    name: 'L2 Devnet',
    rpc: 'http://localhost:9545',
  },
};

/** Minimal ABIs — only the functions the UI needs */

export const VAULT_ABI = [
  'function deposit(address token, uint256 amount) external payable',
  'function withdraw(address token, uint256 amount) external',
  'function freeBalance(address user, address token) external view returns (uint256)',
  'function lockedBalance(address user, address token) external view returns (uint256)',
];

export const MARGIN_ABI = [
  'function depositL2(address token, uint256 amount) external payable',
  'function withdrawL2(address token, uint256 amount) external',
  'function freeBalanceL2(address user, address token) external view returns (uint256)',
  'function l1FreeCache(address token, address user) external view returns (uint256)',
  'function l1LockedCache(address token, address user) external view returns (uint256)',
  'function verifyAndUpdateL1Balance(address user, address token) external',
];

export const BOOK_ABI = [
  'function getOrder(uint256 orderId) external view returns (tuple(uint256 orderId, address trader, uint8 side, uint8 orderType, uint256 price, uint256 quantity, uint256 filledQuantity, uint256 timestamp, uint8 status, bool isL1Backed))',
  'function getBestBid() external view returns (uint256 price, uint256 totalQty)',
  'function getBestAsk() external view returns (uint256 price, uint256 totalQty)',
  'function getBuyPrices() external view returns (uint256[])',
  'function getSellPrices() external view returns (uint256[])',
  'function getOrdersAtPrice(uint8 side, uint256 price) external view returns (uint256[])',
  'function nextOrderId() external view returns (uint256)',
];

export const ENGINE_ABI = [
  'function placeLimitOrder(uint8 side, uint256 price, uint256 quantity, bool useL1Collateral) external returns (uint256 orderId, tuple(uint256 tradeId, uint256 price, uint256 quantity, address maker, address taker)[] fills)',
  'function placeMarketOrder(uint8 side, uint256 quantity) external returns (tuple(uint256 tradeId, uint256 price, uint256 quantity, address maker, address taker)[] fills)',
  'function cancelOrder(uint256 orderId) external',
];

export const SETTLEMENT_L2_ABI = [
  'function trades(uint256 tradeId) external view returns (uint256, address, address, uint256, uint256, uint256, bool, uint256)',
  'function nextTradeId() external view returns (uint256)',
];
