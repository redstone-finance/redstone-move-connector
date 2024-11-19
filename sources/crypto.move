module redstone_move_connector::crypto {
    use std::vector;
    use std::option;
    use aptos_std::aptos_hash::keccak256;
    use aptos_std::secp256k1::{
        ecdsa_recover,
        ecdsa_raw_public_key_to_bytes,
        ecdsa_signature_from_bytes,
    };

    const E_INVALID_SIGNATURE: u64 = 0;
    const E_INVALID_RECOVERY_ID: u64 = 1;

    /// `recover_address` doesn't check the signature validity, it just recovers the address.
    /// the signatures are validated at a later step by checking if the
    /// recovered signers are present in the configured signers array and meets
    /// the minimum signers threshold
    ///
    /// the function might abort with invalid signature error if address recovery fails
    public fun recover_address(
        msg: &vector<u8>,
        signature: &vector<u8>
    ): vector<u8> {
        // Verify signature length is 65 bytes
        assert!(
            vector::length<u8>(signature) == 65,
            E_INVALID_SIGNATURE
        );

        // Extract r, s and v components
        let sig_bytes = vector::empty<u8>();
        let i = 0;
        while (i <64) {
            vector::push_back(
                &mut sig_bytes,
                *vector::borrow(signature, i)
            );
            i = i + 1;
        };

        // Get recovery id (v) and normalize it
        let v = *vector::borrow(signature, 64);
        let v = if (v >= 27) {v - 27} else { v };
        assert!(v <4, E_INVALID_RECOVERY_ID);

        // Create ECDSASignature struct
        let sig = ecdsa_signature_from_bytes(sig_bytes);

        // Attempt to recover the public key
        let pk_opt = ecdsa_recover(keccak256(*msg), v, &sig);

        // If recovery failed, abort
        assert!(
            option::is_some(&pk_opt),
            E_INVALID_SIGNATURE
        );

        // Get public key bytes
        let pk = option::extract(&mut pk_opt);
        let pk_bytes = ecdsa_raw_public_key_to_bytes(&pk);

        // Calculate Keccak256 hash of public key
        let hashed = keccak256(pk_bytes);

        // Take last 20 bytes as Ethereum address
        let addr = vector::empty<u8>();
        let i = 12; // Skip first 12 bytes
        while (i <32) {
            vector::push_back(
                &mut addr,
                *vector::borrow(&hashed, i)
            );
            i = i + 1;
        };

        addr
    }
}
