from pathlib import Path

import dola_ethereum_sdk
import dola_sui_sdk
from brownie import network
from dola_ethereum_sdk import init as dola_ethereum_init
from dola_ethereum_sdk import load as dola_ethereum_load
from dola_sui_sdk import init as dola_sui_init
from dola_sui_sdk import load as dola_sui_load
from dola_sui_sdk import sui_project
from sui_brownie import SuiObject


def get_dola_contract(new_dola_contract, old_dola_contract):
    new_dola_contract = dola_ethereum_load.wormhole_adapter_pool_package(network.show_active(),
                                                                         new_dola_contract).getDolaContract()
    old_dola_contract = dola_ethereum_load.wormhole_adapter_pool_package(network.show_active(),
                                                                         old_dola_contract).getDolaContract()
    return new_dola_contract, old_dola_contract


def register_new_pool(pool: str = "MATIC"):
    genesis_proposal = dola_sui_load.genesis_proposal_package()

    # dola_sui_init.create_proposal()

    pools = dola_ethereum_init.pools()
    pool_address = pools[pool]['pool_address']
    dola_chain_id = pools[pool]['dola_chain_id']
    pool_name = pools[pool]['pool_name']
    dola_pool_id = pools[pool]['dola_pool_id']
    pool_weight = pools[pool]['pool_weight']
    pool_params = [
        dola_sui_init.hex_to_vector(pool_address),
        dola_chain_id,
        dola_sui_init.coin_type_to_vector(pool_name),
        dola_pool_id,
        pool_weight,
    ]

    governance_info = sui_project.network_config['objects']['GovernanceInfo']
    pool_manager_info = sui_project.network_config['objects']['PoolManagerInfo']

    basic_params = [
        governance_info,  # 0
        dola_sui_sdk.sui_project[SuiObject.from_type(dola_sui_init.proposal())][-1],  # 1
        pool_manager_info,  # 2
    ]

    register_new_pool_tx_blocks = [
        dola_sui_init.build_register_new_pool_tx_block(genesis_proposal, len(basic_params), 0)]
    vote_proposal_final_tx_block = dola_sui_init.build_vote_proposal_final_tx_block(genesis_proposal)

    finish_proposal_tx_block = dola_sui_init.build_finish_proposal_tx_block(genesis_proposal, 1)

    sui_project.batch_transaction(
        actual_params=basic_params + pool_params,
        transactions=vote_proposal_final_tx_block + register_new_pool_tx_blocks + finish_proposal_tx_block
    )


def main():
    dola_protocol = dola_sui_load.dola_protocol_package()
    genesis_proposal = dola_sui_load.genesis_proposal_package()

    dola_sui_init.create_proposal()

    # Init poolmanager params
    # pool_address, dola_chain_id, pool_name, dola_pool_id, pool_weight
    pool_params = []

    pools = dola_ethereum_init.pools()
    for pool in pools:
        pool_address = pools[pool]['pool_address']
        dola_chain_id = pools[pool]['dola_chain_id']
        pool_name = pools[pool]['pool_name']
        dola_pool_id = pools[pool]['dola_pool_id']
        pool_weight = pools[pool]['pool_weight']
        pool_params.extend([dola_sui_init.hex_to_vector(pool_address), dola_chain_id,
                            dola_sui_init.coin_type_to_vector(pool_name),
                            dola_pool_id, pool_weight])

    basic_params = [
        dola_protocol.governance_v1.GovernanceInfo[-1],  # 0
        dola_sui_sdk.sui_project[SuiObject.from_type(dola_sui_init.proposal())][-1],  # 1
        dola_protocol.pool_manager.PoolManagerInfo[-1],  # 2
    ]

    pool_num = len(pool_params) // 5
    register_new_pool_tx_blocks = [
        dola_sui_init.build_register_new_pool_tx_block(genesis_proposal, len(basic_params), i) for i in range(pool_num)
    ]
    vote_proposal_final_tx_block = dola_sui_init.build_vote_proposal_final_tx_block(genesis_proposal)

    finish_proposal_tx_block = dola_sui_init.build_finish_proposal_tx_block(genesis_proposal, pool_num)

    sui_project.batch_transaction(
        actual_params=basic_params + pool_params,
        transactions=vote_proposal_final_tx_block + register_new_pool_tx_blocks + finish_proposal_tx_block
    )


if __name__ == "__main__":
    dola_sui_sdk.set_dola_project_path(Path("../.."))
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))

    # Export sui objects before this
    dola_sui_sdk.sui_project.active_account("TestAccount")
    dola_ethereum_sdk.set_ethereum_network("optimism-main")
    main()
    # print(get_dola_contract("0xC67Da938b884d022aF82C42abF76E7C089fA115D", "0x1FFBE74B4665037070E734daf9F79fa33B6d54a8"))
    # dola_ethereum_sdk.set_ethereum_network("optimism-main")
    # register_new_pool("OP")
    # dola_ethereum_sdk.set_ethereum_network("arbitrum-main")
    # register_new_pool("ARB")
