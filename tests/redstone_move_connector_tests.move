#[test_only]
module redstone_move_connector::tests {
    use redstone_move_connector::main;
    use std::vector;
    use redstone_move_connector::test_utils::verify_signer;
    use aptos_framework::timestamp;
    use aptos_framework::account::create_account_for_test;
    use aptos_framework::genesis;

    const DEBUG: bool = false;
    const OWNER: address = @0xCAFE;

    const E_PRICE_MISMATCH: u64 = 0;
    const E_ITEM_MISMATCH: u64 = 1;
    const E_MEDIAN_ERROR: u64 = 2;

    /// "BTC", 32 bytes total, 0 padded
    const TEST_FEED_ID: vector<u8> = x"4254430000000000000000000000000000000000000000000000000000000000";

    /// `TEST_PAYLOAD` is the same as in the Solana Rust test case for BTC,
    /// useful for debugging
    const TEST_PAYLOAD: vector<u8> = x"42544300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000063ab67468b10192aadf8bb0000000200000012bdab86371c29cc8e723548657d7089f9f8a69d2d5cd7c49eae32809e20d92a35cfc5d6aa90673a8e2a6706f5aed1bfdbee12f10d0720e0ceb2c6ef4bc60065b1c42544300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000063ab67468b10192aadf8bb0000000200000018fd7afec67a256122a6757a315b390de5af7d3f13ef2e6e953bfb672248fd35e651eb9462e56e8621ffae734ddf0cd12fdf0b94d4deee0b5137b7ba505a0d6571c42544300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000063ab683a97b0192aadf8bb000000020000001b1d057b37e2a1886dc5e1f1417f3f0b696c33e5db2806e514e6fd5f5a5d02a9a2e5d03943a6dfe5b25df63606902719e1f872e45875e11900280fffdfc35dd591b0003000000000002ed57011e0000";
    const TEST_PAYLOAD_PRICE: u256 = 6849238952113;
    /// NOTE: the `TEST_SIGNATURE` and `TEST_MSG` are from a different payload
    /// than the test payload
    const TEST_SIGNATURE: vector<u8> = x"3e46aabdce1293d4b96baa431708bfa0a5ac41ed4eed8401fb090bd987c161c009b3dd2131617e673b3619fd1c1a44c63e26efd2e3b838055c340d2531db3ffd1c";
    const TEST_MSG: vector<u8> = x"42414c5f73415641585f4156415800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000aca4bc340192a6d8f79000000020000001";

    const SIGNERS: vector<vector<u8>> = vector[
        x"109b4a318a4f5ddcbca6349b45f881b4137deafb",
        x"12470f7aba85c8b81d63137dd5925d6ee114952b",
        x"1ea62d73edf8ac05dfcea1a34b9796e937a29eff",
        x"2c59617248994d12816ee1fa77ce0a64eeb456bf",
        x"83cba8c619fb629b81a65c2e67fe15cf3e3c9747",
        x"5179834763cd2cd8349709c1c0d52137a3df718b",
        x"cd83efdf3c75b6f9a1ff300f46ac6f652792c98c",
        x"b3da302750179b2c7ea6bd3691965313addc3245",
        x"336b78b15b6ff9cc05c276d406dcd2788e6b5c5a",
        x"57331c48c0c6f256f899d118cb4d67fc75f07bee",
    ];

    const ORACLE_ADDRESS: address = @redstone_move_connector;

    #[test]
    fun e2e() {
        genesis::setup();
        let owner = create_account_for_test(ORACLE_ADDRESS);
        initialize_oracle(&owner);
        process_payload();
        get_price();
    }

    #[test]
    fun recover_signature() {
        let recovered_signer = redstone_move_connector::crypto::recover_address(
            &TEST_MSG, &TEST_SIGNATURE
        );
        verify_signer(recovered_signer);
    }

    #[test]
    fun median() {
        let items: vector<u256> = vector[150, 100, 250, 200];
        let expected_median = 150;
        let median = redstone_move_connector::median::calculate_median(&mut items);
        assert!(
            median == expected_median,
            E_MEDIAN_ERROR
        );
    }

    #[test]
    fun sort() {
        let items: vector<u256> = vector[
            5123,
            123,
            55,
            12,
            518,
            123,
            123,
            90,
            123,
            123
        ];

        let expected = vector[
            12,
            55,
            90,
            123,
            123,
            123,
            123,
            123,
            518,
            5123
        ];

        redstone_move_connector::median::sort(&mut items);

        let i = 0;
        while (i < vector::length(&items)) {
            assert!(
                *vector::borrow(&items, i) == *vector::borrow(&expected, i),
                E_ITEM_MISMATCH
            );
            i = i + 1;
        };
    }

    fun initialize_oracle(owner: &signer) {
        main::initialize(
            owner,
            SIGNERS,
            3u8,
            15u64 * 60 * 1000, // 15 minutes
            3u64 * 60 * 1000, // 3 minutes
        );
    }

    fun process_payload() {
        timestamp::update_global_time_for_test_secs(1729443646);
        main::process_redstone_payload(TEST_FEED_ID, TEST_PAYLOAD);
    }

    fun get_price() {
        let price = main::get_price(TEST_FEED_ID);
        assert!(
            price == TEST_PAYLOAD_PRICE,
            E_PRICE_MISMATCH
        );
    }
}

module redstone_move_connector::test_utils {
    use std::debug::print;
    use std::vector;

    const DEBUG: bool = false;
    const E_SIGNER_NOT_FOUND: u64 = 1;
    const SIGNERS: vector<vector<u8>> = vector[
        x"109b4a318a4f5ddcbca6349b45f881b4137deafb",
        x"12470f7aba85c8b81d63137dd5925d6ee114952b",
        x"1ea62d73edf8ac05dfcea1a34b9796e937a29eff",
        x"2c59617248994d12816ee1fa77ce0a64eeb456bf",
        x"83cba8c619fb629b81a65c2e67fe15cf3e3c9747",
        x"5179834763cd2cd8349709c1c0d52137a3df718b",
        x"cd83efdf3c75b6f9a1ff300f46ac6f652792c98c",
        x"b3da302750179b2c7ea6bd3691965313addc3245",
        x"336b78b15b6ff9cc05c276d406dcd2788e6b5c5a",
        x"57331c48c0c6f256f899d118cb4d67fc75f07bee",
    ];

    public fun debug_print(msg: vector<u8>, data: vector<u8>) {
        print(&std::string::try_utf8(msg));
        print(&data);
    }

    /// verify_signer should not be used outside of the tests, it uses a constant array of signers
    public fun verify_signer(recovered_signer: vector<u8>,) {
        // check if any of the public key or keccak are in the SIGNERS
        let i = 0;
        let signers = SIGNERS;
        let signers_len = vector::length<vector<u8>>(&signers);
        while (i < signers_len) {
            let _signer = vector::borrow(&signers, i);
            if (compare_vectors(&recovered_signer, _signer)) {
                if (DEBUG) {
                    debug_print(b"found signer", vector[]);
                };
                break
            };
            i = i + 1;
            if (i == signers_len) {
                debug_print(
                    b"signer not found",
                    recovered_signer
                );
                abort E_SIGNER_NOT_FOUND
            };
        };
    }

    fun compare_vectors(v1: &vector<u8>, v2: &vector<u8>): bool {
        if (vector::length(v1) != vector::length(v2)) return false;
        let i = 0;
        while (i < vector::length(v1)) {
            if (*vector::borrow(v1, i) != *vector::borrow(v2, i)) return false;
            i = i + 1;
        };
        true
    }

}
