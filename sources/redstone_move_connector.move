module redstone_move_connector::main {
    use std::vector;
    use std::signer;
    use std::event;
    use std::option::{Self, Option};
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};
    use redstone_move_connector::conv::{
        from_bytes_to_u64,
        from_bytes_to_u256
    };
    use redstone_move_connector::median::calculate_median;
    use redstone_move_connector::crypto::recover_address;

    // Constants
    const UNSIGNED_METADATA_BYTE_SIZE_BS: u64 = 3;
    const DATA_PACKAGES_COUNT_BS: u64 = 2;
    const DATA_POINTS_COUNT_BS: u64 = 3;
    const SIGNATURE_BS: u64 = 65;
    const DATA_POINT_VALUE_BYTE_SIZE_BS: u64 = 4;
    const DATA_FEED_ID_BS: u64 = 32;
    const TIMESTAMP_BS: u64 = 6;
    const REDSTONE_MARKER_BS: u64 = 9;
    const REDSTONE_MARKER: vector<u8> = x"000002ed57011e0000";
    const REDSTONE_MARKER_LEN: u64 = 9;

    // Error codes
    const E_NOT_OWNER: u64 = 0;
    const E_INVALID_REDSTONE_MARKER: u64 = 1;
    const E_TIMESTAMP_TOO_OLD: u64 = 2;
    const E_TIMESTAMP_TOO_FUTURE: u64 = 3;
    const E_INSUFFICIENT_SIGNER_COUNT: u64 = 4;
    const E_INVALID_FEED_ID: u64 = 5;
    const E_NOT_INITIALIZED: u64 = 6;
    const E_ALREADY_INITIALIZED: u64 = 7;

    struct PriceData has store {
        feed_id: vector<u8>,
        value: u256,
        timestamp: u64,
    }

    struct Config has store, copy, drop {
        owner: address,
        signer_count_threshold: u8,
        signers: vector<vector<u8>>,
        max_timestamp_delay_ms: u64,
        max_timestamp_ahead_ms: u64,
        is_initialized: bool,
    }

    struct PriceOracle has key {
        prices: Table<vector<u8>, PriceData>,
        config: Config,
    }

    struct DataPoint has copy, drop {
        feed_id: vector<u8>,
        value: vector<u8>,
    }

    struct DataPackage has copy, drop {
        signer_address: vector<u8>,
        timestamp: u64,
        data_points: vector<DataPoint>,
    }

    struct Payload has copy, drop {
        data_packages: vector<DataPackage>,
    }

    #[event]
    struct ProcessedRedstonePayload has store, drop {
        feed_id: vector<u8>,
        value: u256,
        timestamp: u64,
    }

    // TODO add reinitialization lock
    public entry fun initialize(
        caller: &signer,
        signers: vector<vector<u8>>,
        signer_count_threshold: u8,
        max_timestamp_delay_ms: u64,
        max_timestamp_ahead_ms: u64,
    ) {
        let config = Config {
            owner: signer::address_of(caller),
            signer_count_threshold,
            signers,
            max_timestamp_delay_ms,
            max_timestamp_ahead_ms,
            is_initialized: true,
        };

        let oracle = PriceOracle {
            prices: table::new(),
            config,
        };

        move_to(caller, oracle);
    }

    #[view]
    public fun get_price(feed_id: vector<u8>): u256 acquires PriceOracle {
        let oracle = borrow_global_mut<PriceOracle>(@redstone_move_connector);
        assert!(
            table::contains(&oracle.prices, feed_id),
            E_INVALID_FEED_ID
        );
        let price_data = table::borrow(&oracle.prices, feed_id);
        price_data.value
    }

    /// process_redstone_payload can be invoked by any principal, no access 
    /// control but the signature is verified - as long as the data is right,
    /// it is acceptable by anyone to call the method
    public entry fun process_redstone_payload(
        feed_id: vector<u8>,
        payload: vector<u8>,
    ) acquires PriceOracle {
        let oracle = borrow_global_mut<PriceOracle>(@redstone_move_connector);
        assert!(
            oracle.config.is_initialized,
            E_NOT_INITIALIZED
        );
        let current_timestamp = timestamp::now_microseconds() / 1000;

        verify_redstone_marker(&payload);

        let parsed_payload = parse_raw_payload(&mut payload);

        verify_data_packages(&parsed_payload, &oracle.config);

        let values = extract_values(&parsed_payload, &feed_id);
        let median_value = calculate_median(&mut values);

        if (!table::contains(&oracle.prices, feed_id)) {
            let new_price_data = PriceData {feed_id, value: 0, timestamp: 0,};
            table::add(
                &mut oracle.prices,
                feed_id,
                new_price_data
            );
        };

        let price_data = table::borrow_mut(&mut oracle.prices, feed_id);
        price_data.value = median_value;
        price_data.timestamp = current_timestamp; // TODO take this from data package

        event::emit(ProcessedRedstonePayload{
            feed_id,
            value:median_value,
            timestamp: current_timestamp
        });
    }

    public entry fun update_config(
        caller: &signer,
        signers: Option<vector<vector<u8>>>,
        signer_count_threshold: Option<u8>,
        max_timestamp_delay_ms: Option<u64>,
        max_timestamp_ahead_ms: Option<u64>,
    ) acquires PriceOracle {
        let oracle = borrow_global_mut<PriceOracle>(@redstone_move_connector);
        assert!(
            signer::address_of(caller) == oracle.config.owner,
            E_NOT_OWNER
        );

        if (option::is_some(&signers)) {
            oracle.config.signers = option::extract(&mut signers);
        };
        if (option::is_some(&signer_count_threshold)) {
            oracle.config.signer_count_threshold = option::extract(
                &mut signer_count_threshold
            );
        };
        if (option::is_some(&max_timestamp_delay_ms)) {
            oracle.config.max_timestamp_delay_ms = option::extract(
                &mut max_timestamp_delay_ms
            );
        };
        if (option::is_some(&max_timestamp_ahead_ms)) {
            oracle.config.max_timestamp_ahead_ms = option::extract(
                &mut max_timestamp_ahead_ms
            );
        };
    }

    fun verify_redstone_marker(bytes: &vector<u8>) {
        assert!(
            vector::length<u8>(bytes) >= REDSTONE_MARKER_LEN,
            E_INVALID_REDSTONE_MARKER
        );
        let marker = REDSTONE_MARKER;
        let i = vector::length<u8>(bytes) - REDSTONE_MARKER_LEN;
        while (i < vector::length<u8>(bytes)) {
            assert!(
                *vector::borrow(bytes, i) == *vector::borrow(
                    &marker,
                    i - (
                        vector::length<u8>(bytes) - REDSTONE_MARKER_LEN
                    )
                ),
                E_INVALID_REDSTONE_MARKER
            );
            i = i + 1;
        };
    }

    fun parse_raw_payload(payload: &mut vector<u8>): Payload {
        trim_redstone_marker(payload);
        trim_payload(payload)
    }

    fun trim_redstone_marker(payload: &mut vector<u8>) {
        let i = 0;
        while (i < REDSTONE_MARKER_BS) {
            vector::pop_back(payload);
            i = i + 1;
        };
    }

    fun trim_payload(payload: &mut vector<u8>): Payload {
        let data_packages_count = trim_metadata(payload);
        let data_packages = trim_data_packages(payload, data_packages_count);
        Payload { data_packages }
    }

    fun trim_metadata(payload: &mut vector<u8>): u64 {
        let unsigned_metadata_size = trim_end(
            payload,
            UNSIGNED_METADATA_BYTE_SIZE_BS
        );
        let unsigned_metadata_size = from_bytes_to_u64(&unsigned_metadata_size);
        let _ = trim_end(payload, unsigned_metadata_size);
        let package_count = trim_end(payload, DATA_PACKAGES_COUNT_BS);
        from_bytes_to_u64(&package_count)
    }

    fun trim_data_packages(payload: &mut vector<u8>, count: u64): vector<DataPackage> {
        let data_packages = vector::empty();
        let i = 0;
        while (i < count) {
            let data_package = trim_data_package(payload);
            vector::push_back(&mut data_packages, data_package);
            i = i + 1;
        };
        data_packages
    }

    fun trim_data_package(payload: &mut vector<u8>): DataPackage {
        let signature = trim_end(payload, SIGNATURE_BS);
        let tmp = *payload;
        let data_point_count = trim_data_point_count(payload);
        let value_size = trim_data_point_value_size(payload);
        let timestamp = trim_timestamp(payload);
        let size = data_point_count * (value_size + DATA_FEED_ID_BS) + DATA_POINT_VALUE_BYTE_SIZE_BS
            + TIMESTAMP_BS + DATA_POINTS_COUNT_BS;
        let signable_bytes = trim_end(&mut tmp, size);
        let signer_address = recover_address(&signable_bytes, &signature);
        let data_points = parse_data_points(
            payload,
            data_point_count,
            value_size
        );

        DataPackage {
            signer_address,
            timestamp,
            data_points
        }
    }

    fun trim_data_point_count(payload: &mut vector<u8>): u64 {
        let data_point_count = trim_end(payload, DATA_POINTS_COUNT_BS);
        from_bytes_to_u64(&data_point_count)
    }

    fun trim_data_point_value_size(payload: &mut vector<u8>): u64 {
        let value_size = trim_end(
            payload,
            DATA_POINT_VALUE_BYTE_SIZE_BS
        );
        from_bytes_to_u64(&value_size)
    }

    fun trim_timestamp(payload: &mut vector<u8>): u64 {
        let timestamp = trim_end(payload, TIMESTAMP_BS);
        from_bytes_to_u64(&timestamp)
    }

    fun parse_data_points(
        payload: &mut vector<u8>,
        count: u64,
        value_size: u64
    ): vector<DataPoint> {
        let data_points = vector::empty();
        let i = 0;
        while (i < count) {
            let data_point = parse_data_point(payload, value_size);
            vector::push_back(&mut data_points, data_point);
            i = i + 1;
        };
        data_points
    }

    fun parse_data_point(
        payload: &mut vector<u8>,
        value_size: u64
    ): DataPoint {
        let value = trim_end(payload, value_size);
        let feed_id = trim_end(payload, DATA_FEED_ID_BS);
        DataPoint {feed_id, value}
    }

    fun verify_data_packages(payload: &Payload, config: &Config,) {
        let i = 0;
        while (
            i < vector::length<DataPackage>(&payload.data_packages)
        ) {
            let package = vector::borrow(&payload.data_packages, i);
            verify_timestamp(package.timestamp, config,);
            i = i + 1;
        };
        verify_signer_count(
            &payload.data_packages,
            config.signer_count_threshold,
            &config.signers
        );
    }

    fun verify_timestamp(
        package_timestamp: u64,
        config: &Config,
    ) {
        let current_time = timestamp::now_microseconds() / 1000; // Convert to milliseconds
        assert!(
            package_timestamp + config.max_timestamp_delay_ms >= current_time,
            E_TIMESTAMP_TOO_OLD
        );
        assert!(
            package_timestamp <= current_time + config.max_timestamp_ahead_ms,
            E_TIMESTAMP_TOO_FUTURE
        );
    }

    fun verify_signer_count(
        data_packages: &vector<DataPackage>,
        threshold: u8,
        signers: &vector<vector<u8>>
    ) {
        let count = 0;
        let i = 0;
        while (
            i < vector::length<DataPackage>(data_packages)
        ) {
            let package = vector::borrow(data_packages, i);
            if (vector::contains(signers, &package.signer_address)) {
                count = count + 1;
            };
            if (count >= threshold) { return };
            i = i + 1;
        };
        assert!(false, E_INSUFFICIENT_SIGNER_COUNT);
    }

    fun extract_values(
        payload: &Payload,
        feed_id: &vector<u8>
    ): vector<u256> {
        let values = vector::empty<u256>();
        let i = 0;
        while (
            i < vector::length<DataPackage>(&payload.data_packages)
        ) {
            let package = vector::borrow(&payload.data_packages, i);
            let j = 0;
            while (
                j < vector::length<DataPoint>(&package.data_points)
            ) {
                let data_point = vector::borrow(&package.data_points, j);
                if (&data_point.feed_id == feed_id) {
                    // Convert value from vector<u8> to u256 here
                    let value = from_bytes_to_u256(&data_point.value);
                    vector::push_back(&mut values, value);
                };
                j = j + 1;
            };
            i = i + 1;
        };
        values
    }

    /// NOTE: there are probably better ways of going about parsing the payload
    /// without copying over and over as in case of `trim_end`, but this is
    /// consistent with the existing interface
    fun trim_end(v: &mut vector<u8>, len: u64): vector<u8> {
        let v_len = vector::length<u8>(v);
        if (len >= v_len) {
            *v
        } else {
            let split_index = v_len - len;
            let result = vector::empty();
            while (vector::length<u8>(v) > split_index) {
                vector::push_back(&mut result, vector::pop_back(v));
            };
            vector::reverse(&mut result);
            result
        }
    }
}
