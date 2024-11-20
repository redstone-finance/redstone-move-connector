use client_rs::constants::*;
use std::str::FromStr;

use anyhow::Result;
use aptos_sdk::{
    bcs,
    move_types::{identifier::Identifier, language_storage::ModuleId},
    rest_client::Client,
    transaction_builder::TransactionFactory,
    types::{
        account_address::AccountAddress,
        chain_id::ChainId,
        transaction::{EntryFunction, TransactionPayload},
        LocalAccount,
    },
};
use url::Url;

pub struct AptosRelayer {
    client: Client,
    account: LocalAccount,
    config: RelayerConfig,
    transaction_factory: TransactionFactory,
}

pub struct RelayerConfig {
    module_id: ModuleId,
    function: Identifier,
}

impl AptosRelayer {
    pub fn new(
        client: Client,
        account: LocalAccount,
        config: RelayerConfig,
    ) -> Self {
        let transaction_factory = TransactionFactory::new(ChainId::new(177))
            .with_gas_unit_price(100)
            .with_max_gas_amount(10000);
        Self {
            client,
            account,
            config,
            transaction_factory,
        }
    }

    pub fn make_process_redstone_payload_tx(
        &self,
        feed_id: Vec<u8>,
        payload: Vec<u8>,
    ) -> Result<TransactionPayload> {
        let module = self.config.module_id.clone();
        let function = self.config.function.clone();
        let ty_args = vec![];
        let args = vec![bcs::to_bytes(&feed_id)?, bcs::to_bytes(&payload)?];

        Ok(TransactionPayload::EntryFunction(EntryFunction::new(
            module, function, ty_args, args,
        )))
    }

    pub async fn initialize(&self) -> Result<()> {
        let transaction_payload =
            TransactionPayload::EntryFunction(EntryFunction::new(
                ModuleId::new(
                    AccountAddress::from_str(REDSTONE_CONNECTOR_MOVE)
                        .expect("Invalid address"),
                    Identifier::new("main").expect("Invalid name identifier"),
                ),
                Identifier::new("initialize")
                    .expect("Invalid function identifier"),
                vec![],
                vec![
                    bcs::to_bytes(
                        &PRIMARY_SIGNERS
                            .iter()
                            .map(|signer| signer.to_vec())
                            .collect::<Vec<_>>(),
                    )?,
                    bcs::to_bytes(&3u8)?,
                    bcs::to_bytes(&(60u64 * 60 * 15))?,
                    bcs::to_bytes(&(60u64 * 60 * 15))?,
                ],
            ));

        let res = self.send_transaction(transaction_payload, true).await;
        println!("Initialize response: {:?}", res);

        Ok(())
    }

    pub async fn send_transaction(
        &self,
        payload: TransactionPayload,
        simulate: bool,
    ) -> Result<()> {
        let transaction = self
            .transaction_factory
            .payload(payload)
            .sender(self.account.address())
            .sequence_number(
                self.client
                    .get_account(self.account.address())
                    .await?
                    .inner()
                    .sequence_number,
            )
            .build();

        let signed_transaction = self.account.sign_transaction(transaction);

        if simulate {
            let simulate_response = self
                .client
                .simulate_bcs_with_gas_estimation(
                    &signed_transaction,
                    true,
                    true,
                )
                .await
                .expect("Failed to simulate transaction");

            println!(
                "Simulate response: {:?}",
                simulate_response.inner().info
            );
        }

        let response = self
            .client
            .submit(&signed_transaction)
            .await
            .expect("Failed to submit transaction");

        println!("Transaction submitted: {:?}", response);

        println!("Hash: {}", response.inner().hash);

        Ok(())
    }

    pub async fn process_redstone_payload(
        &self,
        feed_id: Vec<u8>,
        payload: Vec<u8>,
    ) -> Result<()> {
        let tx_payload =
            self.make_process_redstone_payload_tx(feed_id, payload)?;
        self.send_transaction(tx_payload, true).await
    }
}

fn make_feed_id_bytes(feed_id: &str) -> [u8; 32] {
    let mut bytes = [0; 32];
    bytes[..feed_id.len()].copy_from_slice(feed_id.as_bytes());
    bytes
}

// Example usage:
#[tokio::main]
async fn main() -> Result<()> {
    let client = Client::new(Url::parse(
        "https://testnet.porto.movementnetwork.xyz/v1/",
    )?);
    let info = client.get_ledger_information().await?;
    println!(
        "chain: {:?}; block height: {:?}",
        info.inner().chain_id,
        info.inner().block_height
    );
    let account = LocalAccount::from_private_key(
        dotenv::var("MOVEMENT_PRIVATE_KEY")
            .expect("MOVEMENT_PRIVATE_KEY env var not set")
            .as_str(),
        2,
    )
    .expect("Invalid private key");
    println!("Account address: {:?}", account.address());
    println!(
        "Balance: {:?}",
        client
            .view_apt_account_balance(account.address())
            .await?
            .inner()
    );
    let config = RelayerConfig {
        module_id: ModuleId::new(
            AccountAddress::from_str(REDSTONE_CONNECTOR_MOVE)
                .expect("Invalid address"),
            Identifier::new("main").expect("Invalid name identifier"),
        ),
        function: Identifier::new("process_redstone_payload")
            .expect("Invalid function identifier"),
    };
    let relayer = AptosRelayer::new(client, account, config);

    let modules = relayer
        .client
        .get_account_modules(AccountAddress::from_str(
            REDSTONE_CONNECTOR_MOVE,
        )?)
        .await?;

    assert!(modules.inner().len() > 1, "No modules found");

    if std::env::var("INITIALIZE").is_ok() {
        relayer.initialize().await?;
    }

    // fetch fresh payload
    let feed_id = make_feed_id_bytes("BTC");
    let payload = make_payload("BTC");
    println!("Feed ID: {:?}", feed_id);

    relayer
        .process_redstone_payload(feed_id.to_vec(), payload)
        .await?;

    Ok(())
}

pub fn make_payload(feed_id: &str) -> Vec<u8> {
    let output = std::process::Command::new("redstone-payload-cli")
        .arg(feed_id)
        .arg("-s")
        .arg("3")
        .arg("-b")
        .output()
        .expect("Failed to execute redstone-payload-cli command");

    if !output.status.success() {
        panic!(
            "payload-util command failed: {:?}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    // Convert the output to a string and clean it up
    let output_str = String::from_utf8_lossy(&output.stdout);

    serde_json::from_str(&output_str).expect("parse json payload")
}
