use anchor_lang::prelude::*;
use solana_program::hash::hash;
use wormhole_governance::instructions::{Acc, GovernanceMessage, OWNER};
use wormhole_governance::ID;

include!("payloads.rs");

fn encode_anchor_ix_data(fn_name: &str, args: &[u8]) -> Vec<u8> {
    let mut data = Vec::with_capacity(8 + args.len());
    let hash_bytes = hash(fn_name.as_bytes()).to_bytes();
    data.extend_from_slice(&hash_bytes[..8]);
    data.extend_from_slice(args);
    data
}

fn check_governance_payload(
    payload_hex: &str,
    program_id: Pubkey,
    accounts: Vec<Acc>,
    expected_data: Vec<u8>,
) {
    let h = hex::decode(payload_hex).unwrap();
    let actual = GovernanceMessage::deserialize(&mut h.as_slice()).unwrap();

    let expected = GovernanceMessage {
        governance_program_id: crate::ID,
        program_id,
        accounts,
        data: expected_data,
    };
    assert_eq!(actual, expected);
}

#[test]
fn test_migration_upgrade_ntt_imp() {
    check_governance_payload(
        PAYLOAD0,
        Pubkey::try_from("BPFLoaderUpgradeab1e11111111111111111111111").unwrap(),
        vec![
            Acc { // nttProgramDataAddr
                pubkey: Pubkey::try_from("CKKGtQ2m1t4gHUz2tECGQNqaaFtGsoc9eBjzm61qqV2Q").unwrap(),
                is_signer: false,
                is_writable: true,
            },
            Acc { // nttProgramId
                pubkey: Pubkey::try_from("STTUVCMPuNbk21y1J6nqEGXSQ8HKvFmFBKnCvKHTrWn").unwrap(),
                is_signer: false,
                is_writable: true,
            },
            Acc { // buffer
                pubkey: Pubkey::new_from_array([0xbf; 32]),
                is_signer: false,
                is_writable: true,
            },
            Acc { // spill account, the placeholder string "owner"
                pubkey: OWNER,
                is_signer: false,
                is_writable: true,
            },
            Acc { // SYSVAR_RENT_ADDR
                pubkey: Pubkey::try_from("SysvarRent111111111111111111111111111111111").unwrap(),
                is_signer: false,
                is_writable: false,
            },
            Acc { // SYSVAR_CLOCK_ADDR
                pubkey: Pubkey::try_from("SysvarC1ock11111111111111111111111111111111").unwrap(),
                is_signer: false,
                is_writable: false,
            },
            Acc { // ntt program's authority, the placeholder string "owner"
                pubkey: OWNER,
                is_signer: true,
                is_writable: false,
            },
        ],
        vec![3u8],
    )
}


#[test]
fn test_migration_set_paused() {
    check_governance_payload(
        PAYLOAD1,
        Pubkey::try_from("STTUVCMPuNbk21y1J6nqEGXSQ8HKvFmFBKnCvKHTrWn").unwrap(),
        vec![
            Acc { // payer, the placeholder string "owner"
                pubkey: OWNER,
                is_signer: true,
                is_writable: false,
            },
            Acc { // nttConfigPda
                pubkey: Pubkey::try_from("DCWd3ygRyr9qESyRfPRCMQ6o1wAsPu2niPUc48ixWeY9").unwrap(),
                is_signer: false,
                is_writable: true,
            }
        ],
        encode_anchor_ix_data("global:set_paused", &[1u8]),
    );
}

#[test]
fn test_migration_transfer_mint_authority() {
    check_governance_payload(
        PAYLOAD2,
        Pubkey::try_from("STTUVCMPuNbk21y1J6nqEGXSQ8HKvFmFBKnCvKHTrWn").unwrap(),
        vec![
            Acc { // payer, the placeholder string "owner"
                pubkey: OWNER,
                is_signer: true,
                is_writable: true,
            },
            Acc { // nttConfigPda
                pubkey: Pubkey::try_from("DCWd3ygRyr9qESyRfPRCMQ6o1wAsPu2niPUc48ixWeY9").unwrap(),
                is_signer: false,
                is_writable: false,
            },
            Acc { // nttTokenAuthorityPda
                pubkey: Pubkey::try_from("Bjui9tuxKGsiF5FDwosfUsRUXg9RZCKidbThfm6CRtRt").unwrap(),
                is_signer: false,
                is_writable: false,
            },
            Acc { // usdsMintAddr
                pubkey: Pubkey::try_from("USDSwr9ApdHk5bvJKMjzff41FfuX8bSxdKcR81vTwcA").unwrap(),
                is_signer: false,
                is_writable: true,
            },
            Acc { // SPL_TOKEN_PROGRAM_ID
                pubkey: Pubkey::try_from("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA").unwrap(),
                is_signer: false,
                is_writable: false,
            },
            Acc { // custodyAta
                pubkey: Pubkey::try_from("4CVeJ5oZPL77ewm9DdjEEnh6vLSWKvcPhzgvhpKcZRuL").unwrap(),
                is_signer: false,
                is_writable: true,
            },
        ],
        encode_anchor_ix_data("global:transfer_mint_authority", &[0x17u8; 32]),
    );

}
