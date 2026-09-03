#!/bin/bash
set -e

NETWORK=${1:-testnet}
CONTRACT=${2:-escrow}
ADMIN_KEY=${3:-}

if [ -z "$ADMIN_KEY" ]; then
  echo "Usage: $0 <network> <contract> <admin-key>"
  echo "Networks: testnet, futurenet, mainnet"
  echo "Contracts: escrow, fee-manager"
  exit 1
fi

NETWORK_URL=""
case $NETWORK in
  testnet)
    NETWORK_URL="https://soroban-testnet.stellar.org"
    ;;
  futurenet)
    NETWORK_URL="https://soroban-futurenet.stellar.org"
    ;;
  mainnet)
    NETWORK_URL="https://soroban-mainnet.stellar.org"
    ;;
  *)
    echo "Invalid network: $NETWORK"
    exit 1
    ;;
esac

echo "Building contract: $CONTRACT for network: $NETWORK"
cd ./contracts
cargo build --package $CONTRACT --target wasm32-unknown-unknown --release

WASM_PATH="target/wasm32-unknown-unknown/release/${CONTRACT}.wasm"
if [ ! -f "$WASM_PATH" ]; then
  echo "Error: WASM file not found at $WASM_PATH"
  exit 1
fi

echo "Deploying $CONTRACT to $NETWORK..."
CONTRACT_ID=$(stellar contract deploy \
  --wasm $WASM_PATH \
  --source-account $ADMIN_KEY \
  --network $NETWORK \
  --network-passphrase "$(stellar network info $NETWORK | grep passphrase)" \
  2>/dev/null || echo "DEPLOYMENT_FAILED")

if [ "$CONTRACT_ID" = "DEPLOYMENT_FAILED" ]; then
  echo "Error: Deployment failed"
  exit 1
fi

echo "Contract deployed successfully!"
echo "Contract ID: $CONTRACT_ID"

DEPLOYED_FILE="./contracts/.deployed-${NETWORK}.json"
mkdir -p ./contracts
cat > "$DEPLOYED_FILE" <<EOF
{
  "network": "$NETWORK",
  "contract": "$CONTRACT",
  "contract_id": "$CONTRACT_ID",
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "Deployment recorded in $DEPLOYED_FILE"

echo "Verifying contract deployment..."
stellar contract info --id $CONTRACT_ID --network $NETWORK > /dev/null && echo "Verification successful!"

exit 0
