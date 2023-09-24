# ENV_VARS:=$(shell sed -ne 's/ *\#.*$$//; /./ s/=.*$$// p' .env )
# $(foreach v,$(ENV_VARS),$(eval $(shell echo export $(v)="$($(v))")))

# include .env
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

abi-hub :; forge inspect --optimize contracts/AucentiveHub.sol:AucentiveHub abi > abi/AucentiveHub.json
abi-spoke :; forge inspect --optimize contracts/AucentiveSpoke.sol:AucentiveSpoke abi > abi/AucentiveSpoke.json
gen-types :; make abi-hub && make abi-spoke && npx typechain --target ethers-v5 ./abi/*.json --out-dir ./types-typechain
cp-types :; cp -r ./types-typechain/* ../website/src/types-typechain && cp -r ./types-typechain/* ../server/src/types-typechain

# Ensure that RPCs support forking for forge to deploy

deploy-hub-base-goerli :; @forge script script/AucentiveHub.s.sol:DeployAucentiveHub --optimize --rpc-url $(BASE_TESTNET_RPC_URL) --private-key $(BASE_TESTNET_PRIVATE_KEY) --broadcast --slow --legacy --with-gas-price 1000000000 -vvvv
deploy-ftda-base-goerli :; @forge script script/FTDataAsserter.s.sol:DeployFTDataAsserter --optimize --rpc-url $(BASE_TESTNET_RPC_URL) --private-key $(BASE_TESTNET_PRIVATE_KEY) --broadcast --slow --legacy --with-gas-price 1000000000 -vvvv

# deploy-hub-base-mainnet :; @forge script script/AucentiveHub.s.sol:DeployAucentiveHub --optimize --rpc-url $(BASE_MAINNET_RPC_URL) --private-key $(BASE_MAINNET_PRIVATE_KEY) --broadcast --slow --legacy --with-gas-price 1000000000 -vvvv

# deploy-spoke-optimism :; @forge script script/AucentiveSpoke.s.sol:DeployAucentiveSpoke --optimize --rpc-url ${RPC_URL_OPTIMISM} --private-key ${DEPLOYER_PRIVATE_KEY} --broadcast -vvvv

start-anvil :; anvil -m 'test test test test test test test test test test test junk'

# deploy-anvil :; forge create --rpc-url http://localhost:8545 \
# --constructor-args 0x \
# --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
# src/MyToken.sol:MyToken

deploy-anvil :; @forge script script/AucentiveHub.s.sol:DeployAucentiveHub --optimize --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast -vvvv

verify-hub-base-goerli :; forge verify-contract --chain base-goerli --etherscan-api-key ${BASESCAN_API_KEY} --watch --constructor-args $(cast abi-encode "constructor(address, address, address, address)" "0xe432150cce91c13a887f7D836923d5597adD8E31" "0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6" "0xF175520C52418dfE19C8098071a252da48Cd1C19" "0x4638d59b4F046F121549B9a6Af70cB3c057f901d") 0x85a5625a7614682918dE6EE382a6A39043cE294B contracts/AucentiveHub.sol:AucentiveHub

verify-ftda-base-goerli :; forge verify-contract --chain base-goerli --etherscan-api-key ${BASESCAN_API_KEY} --watch --constructor-args $(cast abi-encode "constructor(address, address, address)" "0xEF8b46765ae805537053C59f826C3aD61924Db45" "0x1F4dC6D69E3b4dAC139E149E213a7e863a813466" "0x85a5625a7614682918dE6EE382a6A39043cE294B") 0xA16f926D4DcdFCe30e53E4C89eCbF217B3fA7497 contracts/FTDataAsserter.sol:FTDataAsserter
