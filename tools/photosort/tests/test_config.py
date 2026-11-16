import pytest
import yaml

from photosort.config import ConfigError, load_config, parse_config

REQUIRED = ["Gym & Fitness", "Food & Drinks", "Screenshots", "Receipts & Documents", "Cars & Rides",
            "Nature & Outdoors", "Trees", "Sunsets & Sky", "Pets & Animals", "Friends & Family", "Selfies",
            "Travel", "Memes & Saved Images", "Work", "Shopping", "Videos", "Duplicates & Similar"]


def test_default_config_has_all_categories(cfg):
    names = [c.name for c in cfg.categories]
    for n in REQUIRED:
        assert n in names
    assert cfg.folder == "Sorted by Claude"
    assert cfg.by_rule("review").album == "Review to delete"
    assert "Unsorted" in cfg.album_names()


def test_bad_configs_rejected():
    for raw in [
        {"categories": []},
        {"categories": [{"name": "A", "rule": "nope"}]},
        {"categories": [{"name": "A", "flags": ["not_a_flag"]}]},
        {"categories": [{"name": "A", "threshold": 2}]},
        {"categories": [{"name": "A"}, {"name": "A"}]},
        {"categories": [{"name": "A", "album": "x/y"}]},
        {"categories": [{"name": "A", "typo_key": 1}]},
        {"categories": [{"name": "A"}], "duplicates": {"max_distance": 9}},
    ]:
        with pytest.raises(ConfigError):
            parse_config(raw)


def test_local_overlay_merges_by_name(tmp_path):
    (tmp_path / "c.yaml").write_text(yaml.safe_dump({
        "threshold": 0.5, "categories": [{"name": "A", "labels": ["x"]}, {"name": "B", "labels": ["y"]}]}))
    (tmp_path / "c.local.yaml").write_text(yaml.safe_dump({
        "travel": {"min_km": 99}, "categories": [{"name": "A", "threshold": 0.9}, {"name": "C", "flags": ["video"]}]}))
    cfg = load_config(tmp_path / "c.yaml")
    assert cfg.category("A").threshold == 0.9 and cfg.category("A").labels == ["x"]
    assert [c.name for c in cfg.categories] == ["A", "B", "C"]
    assert cfg.travel["min_km"] == 99 and cfg.travel["home"] == "auto"
