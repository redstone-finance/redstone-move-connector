# redstone-move-connector

Redstone Data on Movement Testnet

Movement Porto Testnet deployment: `0x112e0d5c408de9321877722c60ddfd81649cd1fcf7944beefc132903a20bdbec` [Move Explorer link](https://explorer.movementlabs.xyz/account/0x112e0d5c408de9321877722c60ddfd81649cd1fcf7944beefc132903a20bdbec/modules/code/main?network=porto+testnet)

## Usage

### On-chain

```move
module price_consumer::main {
    use redstone_move_connector::main as redstone;

    const BTC_FEED_ID: vector<u8> = x"4254432d5553442d535041524b00000000000000000000000000000000000000";
    const ETH_FEED_ID: vector<u8> = x"4554482d5553442d535041524b00000000000000000000000000000000000000";

    #[view]
    public fun get_btc_price(): u256 {
        redstone::get_price(BTC_FEED_ID)
    }

    #[view]
    public fun get_eth_price(): u256 {
        redstone::get_price(ETH_FEED_ID)
    }
}
```

### Off-chain

```bash
#!/bin/bash

MODULE_ADDRESS="0x112e0d5c408de9321877722c60ddfd81649cd1fcf7944beefc132903a20bdbec"
FEED_ID="4254430000000000000000000000000000000000000000000000000000000000" # BTC

movement move view \
    --function-id $MODULE_ADDRESS::main::get_price \
    --args hex:$FEED_ID
```

### Pushing the data

The data is pushed periodically on-chain, but to ensure freshest data, you can push it before calling the `redstone::get_price` method, too

The data can be pushed by any party due to signer verification happening
on-chain, providing on-demand availability

You can request the payload using the `@redstone-finance/sdk` [npm package](https://www.npmjs.com/package/@redstone-finance/sdk), or with `redstone-payload-cli` [npm package](https://www.npmjs.com/package/redstone-payload-cli), the data can then be pushed on-chain

There is a Rust example in the `./client-rs` directory
