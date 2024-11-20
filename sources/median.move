module redstone_move_connector::median {
    use std::vector;

    const MEDIAN_ERROR_EMPTY_VECTOR: u64 = 0;

    public fun calculate_median(values: &mut vector<u256>): u256 {
        let len = vector::length(values);
        assert!(len > 0, MEDIAN_ERROR_EMPTY_VECTOR);

        sort(values);

        if (len % 2 == 1) {
            *vector::borrow(values, len / 2)
        } else {
            *vector::borrow(values, len / 2 - 1)
        }
    }

    public fun sort(values: &mut vector<u256>) {
        let len = vector::length(values);
        let i = 1;
        while (i < len) {
            let key = *vector::borrow(values, i);
            let j = i;
            while (
                j > 0 && *vector::borrow(values, j - 1) > key
            ) {
                let prev = *vector::borrow(values, j - 1);
                *vector::borrow_mut(values, j) = prev;
                j = j - 1;
            };
            *vector::borrow_mut(values, j) = key;
            i = i + 1;
        };
    }
}
