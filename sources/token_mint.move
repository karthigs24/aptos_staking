module aptosx::token_mint {
    use std::string;
    use std::error;
    use std::signer;
    use std::simple_map;
    use std::option;

    use aptos_framework::aptos_coin::{Self};
    use aptos_framework::coin::{Self, BurnCapability, FreezeCapability, MintCapability};

    const EINVALID_BALANCE: u64 = 0;
    const EACCOUNT_DOESNT_EXIST: u64 = 1;
    const ENO_CAPABILITIES: u64 = 2;
    const ENOT_APTOSX_ADDRESS: u64 = 3;


    const STAKE_VAULT_SEED: vector<u8> = b"aptosx::token_mint::stake_vault";
    use aptos_framework::account;

    struct UserStakeInfo has key {
        amount: u64,
    }

    struct StakeVault has key {
        resource_addr: address,
        signer_cap: account::SignerCapability
    }

    struct ValidatorSet has key {
        validators: simple_map::SimpleMap<address, bool>,
    }

    struct Capabilities has key {
        burn_cap: BurnCapability<AptosXCoin>,
        freeze_cap: FreezeCapability<AptosXCoin>,
        mint_cap: MintCapability<AptosXCoin>,
    }

    struct AptosXCoin {}

    public entry fun initialize(
        account: &signer,
        decimals: u8,
    ) {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<AptosXCoin>(
            account,
            string::utf8(b"AptosX"),
            string::utf8(b"APTX"),
            decimals,
            true,
        );

        move_to(account, ValidatorSet {
            validators: simple_map::create<address, bool>(),
        });

        move_to(account, Capabilities {
            burn_cap,
            freeze_cap,
            mint_cap,
        });

        let (stake_vault, signer_cap) = account::create_resource_account(account, STAKE_VAULT_SEED);
        let resource_addr = signer::address_of(&stake_vault);
        coin::register<aptos_coin::AptosCoin>(&stake_vault);
        let stake_info = StakeVault {
            resource_addr, 
            signer_cap
        };
        move_to<StakeVault>(account, stake_info);
    }

    public fun is_aptosx_address(addr: address): bool {
        addr == @aptosx
    }

    public entry fun add_validator(account: &signer, validator_address: address) acquires ValidatorSet {
        assert!(
            is_aptosx_address(signer::address_of(account)),
            error::permission_denied(ENOT_APTOSX_ADDRESS),
        );

        let validator_set = borrow_global_mut<ValidatorSet>(@aptosx);
        simple_map::add(&mut validator_set.validators, validator_address, true);
    }

        public entry fun remove_validator(account: &signer, validator_address: address) acquires ValidatorSet {
        assert!(
            is_aptosx_address(signer::address_of(account)),
            error::permission_denied(ENOT_APTOSX_ADDRESS),
        );
        let validator_set = borrow_global_mut<ValidatorSet>(@aptosx);

        simple_map::remove(&mut validator_set.validators, &validator_address );
    }


       public entry fun deposit(staker: &signer, amount: u64) acquires UserStakeInfo, Capabilities, StakeVault {
        let staker_addr = signer::address_of(staker);

        if (!exists<UserStakeInfo>(staker_addr)) {
            let stake_info = UserStakeInfo {
                amount: 0, 
            };
            move_to<UserStakeInfo>(staker, stake_info);
        };

        let resource_addr = borrow_global<StakeVault>(@aptosx).resource_addr;

        if (!coin::is_account_registered<AptosXCoin>(staker_addr)) {
            coin::register<AptosXCoin>(staker);
        };

        let stake_info = borrow_global_mut<UserStakeInfo>(staker_addr);
        coin::transfer<aptos_coin::AptosCoin>(staker, resource_addr, amount);
        stake_info.amount = stake_info.amount + amount;

        let mod_account = @aptosx;
        assert!(
            exists<Capabilities>(mod_account),
            error::not_found(ENO_CAPABILITIES),
        );
        let capabilities = borrow_global<Capabilities>(mod_account);
        let coins_minted = coin::mint(amount, &capabilities.mint_cap);
        coin::deposit(staker_addr, coins_minted);
    }

         public entry fun withdraw(staker: &signer, amount: u64) acquires UserStakeInfo, Capabilities, StakeVault {
        let staker_addr = signer::address_of(staker);
        assert!(exists<UserStakeInfo>(staker_addr), EACCOUNT_DOESNT_EXIST);

        let stake_info = borrow_global_mut<UserStakeInfo>(staker_addr);
        assert!(stake_info.amount >= amount, EINVALID_BALANCE);
        
        stake_info.amount = stake_info.amount - amount;

        let vault = borrow_global<StakeVault>(@aptosx);
        let resource_account = account::create_signer_with_capability(&vault.signer_cap);
        coin::transfer<aptos_coin::AptosCoin>(&resource_account, staker_addr, amount);

        let coin = coin::withdraw<AptosXCoin>(staker, amount);
        let mod_account = @aptosx;
        assert!(
            exists<Capabilities>(mod_account),
            error::not_found(ENO_CAPABILITIES),
        );
        let capabilities = borrow_global<Capabilities>(mod_account);
        coin::burn<AptosXCoin>(coin, &capabilities.burn_cap);
    }
}
