from pathlib import Path
from typing import Union

import sui_brownie

DOLA_CONFIG = {
    "DOLA_PROJECT_PATH": Path(__file__).parent.parent.parent.parent,
    "DOLA_SUI_PATH": Path(__file__).parent.parent.parent.parent.joinpath("sui")
}

sui_project = sui_brownie.SuiProject(project_path=DOLA_CONFIG["DOLA_SUI_PATH"], network="sui-mainnet")


def set_dola_project_path(path: Union[Path, str], network="sui-mainnet"):
    global sui_project
    if isinstance(path, str):
        path = Path(path)
    DOLA_CONFIG["DOLA_PROJECT_PATH"] = path
    DOLA_CONFIG["DOLA_SUI_PATH"] = path.joinpath("sui")
    assert DOLA_CONFIG["DOLA_SUI_PATH"].exists(), f"Path error:{DOLA_CONFIG['DOLA_SUI_PATH'].absolute()}!"
    sui_project = sui_brownie.SuiProject(project_path=DOLA_CONFIG["DOLA_SUI_PATH"], network=network)
    sui_project.load_config()
    sui_project.read_cache()
