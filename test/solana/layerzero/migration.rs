use anchor_lang::prelude::*;
use oft::instructions::SetOFTConfigParams;
use solana_program::hash::hash;
use governance::{
    msg_codec::{Acc, GovernanceMessage}, CPI_AUTHORITY_PLACEHOLDER
};

include!("payloads.rs");

#[test]
fn test_migration_unpause_oapp() {
    let h = hex::decode(PAYLOAD0).unwrap();
    let actual = GovernanceMessage::decode(&mut h.as_slice()).unwrap();

    let mut origin_caller = [0u8; 32];
    origin_caller[12..].copy_from_slice(&hex::decode("BE8E3e3618f7474F8cB1d074A26afFef007E98FB").unwrap());

    let accounts = vec![
        Acc {
            pubkey: CPI_AUTHORITY_PLACEHOLDER,
            is_signer: true,
            is_writable: false,
        },
        Acc {
            pubkey: Pubkey::new_from_array([0x05; 32]),
            is_signer: false,
            is_writable: true,
        },
    ];

    let hash_bytes = hash("global:set_oft_config".as_bytes()).to_bytes();
    let mut data = Vec::new();
    data.extend_from_slice(&hash_bytes[..8]);
    borsh::BorshSerialize::serialize(&SetOFTConfigParams::Paused(false), &mut data)
        .expect("Failed to serialize SetOFTConfigParams");

    let expected = GovernanceMessage {
        origin_caller,
        program_id: Pubkey::new_from_array([0x0f; 32]),
        accounts,
        data,
    };

    assert_eq!(actual, expected);
}
