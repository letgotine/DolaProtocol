import os
import time
import urllib.parse

import brownie
import requests
from brownie import (
    network,
    config, )

from dola_ethereum_sdk import load, get_account, set_ethereum_network


def get_scan_api_key(net="polygon-test"):
    if "polygon-zk" in net:
        return os.getenv("POLYGON_ZK_API_KEY")
    elif "bsc" in net:
        return os.getenv("BSC_API_KEY")
    elif "arbitrum" in net:
        return os.getenv("ARBITRUM_API_KEY")
    elif "optimism" in net:
        return os.getenv("OPTIMISM_API_KEY")
    elif "polygon" in net:
        return os.getenv("POLYGON_API_KEY")


def get_wormhole_chain_id():
    return config["networks"][network.show_active()]["wormhole_chainid"]


def get_wormhole():
    return config["networks"][network.show_active()]["wormhole"]


def usdt():
    return config["networks"][network.show_active()]["tokens"]["USDT"]


def wbtc():
    return config["networks"][network.show_active()]["tokens"]["WBTC"]


def usdc():
    return config["networks"][network.show_active()]["tokens"]["USDC"]


def eth():
    return "0x0000000000000000000000000000000000000000"


def pools():
    return config["networks"][network.show_active()]["pools"]


def scan_rpc_url():
    return config["networks"][network.show_active()]["scan_rpc_url"]


def graphql_url(net):
    return config["networks"][net]["graphql_url"]


def register_owner(vaa, package_address):
    account = get_account()
    omnipool = load.wormhole_adapter_pool_package(network=network.show_active(), package_address=package_address)
    omnipool.registerOwner(vaa, {'from': account})


def delete_owner(vaa, package_address):
    account = get_account()
    omnipool = load.wormhole_adapter_pool_package(network=network.show_active(), package_address=package_address)
    omnipool.deleteOwner(vaa, {'from': account})


def register_spender(vaa, package_address):
    account = get_account()
    omnipool = load.wormhole_adapter_pool_package(network=network.show_active(), package_address=package_address)
    omnipool.registerSpender(vaa, {'from': account})


def delete_spender(vaa, package_address):
    account = get_account()
    omnipool = load.wormhole_adapter_pool_package(network=network.show_active(), package_address=package_address)
    omnipool.deleteSpender(vaa, {'from': account})


def bridge_pool_read_vaa(nonce=None):
    bridge_pool = load.wormhole_adapter_pool_package()

    if nonce is None:
        nonce = bridge_pool.getNonce() - 1

    return str(bridge_pool.cachedVAA(nonce)), nonce


def build_rpc_params(address, topic, api_key, start_block=0, end_block=99999999, limit=5):
    return {
        'module': 'logs',
        'action': 'getLogs',
        'address': str(address),
        'fromBlock': str(start_block),
        'toBlock': str(end_block),
        'topic0': str(topic),
        'page': '1',
        'offset': str(limit),
        'apikey': api_key
    }


def relay_events(lending_portal, system_portal, start_block=0, end_block=9999999999, limit=10, net="polygon-test"):
    topic = brownie.web3.keccak(text="RelayEvent(uint64,uint64,uint256)").hex()
    api_key = get_scan_api_key(net)

    base_url = scan_rpc_url()

    system_rpc_params = build_rpc_params(
        system_portal, topic, api_key, start_block, end_block, limit)
    lending_rpc_params = build_rpc_params(
        lending_portal, topic, api_key, start_block, end_block, limit)
    headers = {}
    if "bsc" in net:
        headers = {
            'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
            'accept-language': 'zh,en;q=0.9,zh-CN;q=0.8',
            'cache-control': 'max-age=0',
            'cookie': '__stripe_mid=f0d7920d-dcf7-4f6c-926b-4381d16e2de09c7c5b; _gid=GA1.2.1608275934.1679541907; cf_clearance=qa.p7TdsepyFo0KzvZ2lfIlu1inGNy6mBSMfljWlBVw-1679544250-0-150; __cuid=d0e32142731a4b6a836bd4170892451f; __cf_bm=Nqn43kjTCFGnJA8hkEREgEj2cl_vIaM3KjGccp8RAn0-1679556064-0-AWqNjZOldwrmf77Zm4B3Pw7iAH+TVo4TviCd8flOviO0aA5EHI4nPZo/XAUveVRHAioAl+zD/71Dstoz0g1e/537mW5XHOAAy/9If5a2+n4i/qNnacDo4GScVC0StWNmiw==; amp_fef1e8=509f1beb-3ca0-426c-8a74-daa262842771R...1gs6ler9e.1gs6lfq49.v.7.16; _ga=GA1.1.327633374.1670917759; __stripe_sid=7331455c-b4fb-4f57-9aad-6507bfb2ab5ca17e57; _ga_PQY6J2Q8EP=GS1.1.1679556080.19.0.1679556090.0.0.0',
            'dnt': '1',
            'referer': 'https://docs.bscscan.com/v/bscscan-testnet/api-endpoints/logs',
            'sec-ch-ua': '"Not_A Brand";v="99", "Google Chrome";v="109", "Chromium";v="109"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"Linux"',
            'sec-fetch-dest': 'document',
            'sec-fetch-mode': 'navigate',
            'sec-fetch-site': 'same-site',
            'sec-fetch-user': '?1',
            'upgrade-insecure-requests': '1',
            'user-agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36'
        }

    system_request_url = f"{base_url}?{urllib.parse.urlencode(system_rpc_params)}"

    system_relay_result = requests.get(
        system_request_url,
        headers=headers
    )

    lending_request_url = f"{base_url}?{urllib.parse.urlencode(lending_rpc_params)}"

    lending_relay_result = requests.get(
        lending_request_url,
        headers=headers
    )

    if system_relay_result.status_code == 200 and lending_relay_result.status_code == 200:
        system_relay_events = decode_relay_events(system_relay_result.json())
        lending_relay_events = decode_relay_events(lending_relay_result.json())
    else:
        system_relay_events = []
        lending_relay_events = []

    return sorted(system_relay_events + lending_relay_events, key=lambda x: x['block_number'])


def get_gas_price(net):
    api_key = get_scan_api_key(net)

    base_url = scan_rpc_url()

    request_url = f'{base_url}?module=proxy&action=eth_gasPrice&apikey={api_key}'
    response = requests.get(request_url)

    return response.json()['result']


def decode_relay_events(response):
    events = []

    if response:
        for event in response['result']:
            block_number = int(event['blockNumber'], 16)
            tx_hash = event['transactionHash']
            timestamp = int(event['timeStamp'], 16)
            data = event['data']
            nonce = int(data[2:66], 16)
            sequence = int(data[66:130], 16)
            relay_fee = int(data[130:], 16)
            events.append({
                'blockNumber': block_number,
                'transactionHash': tx_hash,
                'nonce': nonce,
                'sequence': sequence,
                'amount': relay_fee,
                'blockTimestamp': timestamp,
            })

    return events


def query_relay_event_by_get_logs(lending_portal: str, system_portal: str, start_block=0):
    log_filter = {'fromBlock': start_block, 'address': [lending_portal, system_portal],
                  'topics': ['0x262e3a296d702e5f4781f85336010cc0549f5344a6f46b406efdce9a120f6598']}
    logs = brownie.web3.eth.get_logs(log_filter)
    return decode_relay_logs(logs)


def decode_relay_logs(logs):
    events = []

    if logs:
        for log in logs:
            block_number = int(log['blockNumber'])
            tx_hash = log['transactionHash'].hex()
            timestamp = int(time.time())
            data = log['data']
            nonce = int(data[2:66], 16)
            sequence = int(data[66:130], 16)
            relay_fee = int(data[130:], 16)
            events.append({
                'blockNumber': block_number,
                'transactionHash': tx_hash,
                'nonce': nonce,
                'sequence': sequence,
                'amount': relay_fee,
                'blockTimestamp': timestamp,
            })
    return events


def current_block_number():
    return brownie.web3.eth.block_number


def get_payload_from_chain(tx_id):
    tx = brownie.chain.get_transaction(tx_id)
    return tx.events['LogMessagePublished']['payload']


if __name__ == "__main__":
    set_ethereum_network("arbitrum-main")
    tx = brownie.chain.get_transaction("0x0e4a568d0ec91649cfb0dbe2d42f888fbd5a1403cb7361edfeb0b5761adc3d1b")
    payload = str(tx.events['LogMessagePublished']['payload'])
    print(payload)
