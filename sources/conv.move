module redstone_move_connector::conv {
    use aptos_std::vector;

    public fun from_bytes_to_u64(bytes: &vector<u8>): u64 {
        let result = 0u64;
        let i = 0;
        while (i < vector::length<u8>(bytes)) {
            result = (result << 8)|(*vector::borrow(bytes, i) as u64);
            i = i + 1;
        };
        result
    }

    public fun from_bytes_to_u256(bytes: &vector<u8>): u256 {
        let result = 0u256;
        let i = 0;
        while (i < vector::length<u8>(bytes)) {
            result = (result << 8)|(*vector::borrow(bytes, i) as u256);
            i = i + 1;
        };
        result
    }
}
