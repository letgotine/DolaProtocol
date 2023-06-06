from pathlib import Path

from flask import Flask
from flask_cors import CORS

import dola_ethereum_sdk
import relayer

app = Flask(__name__)
CORS(app)


@app.route('/relay_fee/<src_chain_id>/<dst_chain_id>/<call_name>/<feed_nums>')
def relay_fee(src_chain_id, dst_chain_id, call_name, feed_nums):
    return relayer.get_relay_fee(src_chain_id, dst_chain_id, call_name, feed_nums)


@app.route('/max_relay_fee/<src_chain_id>/<dst_chain_id>/<call_name>')
def max_relay_fee(src_chain_id, dst_chain_id, call_name):
    return relayer.get_max_relay_fee(src_chain_id, dst_chain_id, call_name)


if __name__ == '__main__':
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))

    app.run(host='::', port=5000)