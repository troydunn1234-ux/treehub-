import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from photosort.cache import Cache  # noqa: E402
from photosort.config import load_config  # noqa: E402
from photosort.demo import make_demo_library  # noqa: E402


@pytest.fixture(scope="session")
def cfg():
    return load_config()


@pytest.fixture(scope="session")
def demo_lib(tmp_path_factory):
    return make_demo_library(tmp_path_factory.mktemp("demo"))


@pytest.fixture()
def cache(tmp_path):
    c = Cache(tmp_path / "cache.sqlite")
    yield c
    c.close()
