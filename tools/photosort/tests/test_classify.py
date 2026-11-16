from photosort.classify import Classifier, noisy_or
from photosort.model import Features, PhotoRecord

HOME = (10.0, 20.0)


def rec(**kw):
    kw.setdefault("uuid", "U1")
    kw.setdefault("has_exif", True)
    kw.setdefault("camera_make", "Cam")
    return PhotoRecord(**kw)


def cats(cfg, r, f=None, clip=None, **ckw):
    return Classifier(cfg, **ckw).classify(r, f, clip)


def test_noisy_or():
    assert noisy_or([]) == 0
    assert abs(noisy_or([0.5, 0.5]) - 0.75) < 1e-9
    assert noisy_or([1.0, 0.2]) == 1.0


def test_flags(cfg):
    assert cats(cfg, rec(is_screenshot=True)).categories == ["Screenshots"]
    assert "Selfies" in cats(cfg, rec(is_selfie=True)).categories
    assert "Selfies" in cats(cfg, rec(lens_model="Phone front camera 2.7mm")).categories
    d = cats(cfg, rec(is_movie=True, labels=["gym"]))
    assert d.categories == ["Videos", "Gym & Fitness"]          # multi-album membership


def test_labels_whole_word_and_plural(cfg):
    assert "Trees" in cats(cfg, rec(labels=["palm tree"])).categories
    assert "Trees" in cats(cfg, rec(labels=["trees"])).categories
    assert "Trees" not in cats(cfg, rec(labels=["street"])).categories       # 'street' contains 'tree'
    assert "Trees" not in cats(cfg, rec(labels=["christmas tree"])).categories
    assert "Cars & Rides" not in cats(cfg, rec(labels=["carpet"])).categories


def test_screenshot_excluded_from_content_albums(cfg):
    d = cats(cfg, rec(is_screenshot=True, labels=["food", "dog"]))
    assert d.categories == ["Screenshots"]


def test_weak_labels_need_support(cfg):
    assert cats(cfg, rec(labels=["outdoor"])).unsorted
    assert "Nature & Outdoors" in cats(cfg, rec(labels=["outdoor", "plant"])).categories
    d = cats(cfg, rec(labels=["outdoor"]), clip={"Nature & Outdoors": 0.3})
    assert "Nature & Outdoors" in d.categories


def test_clip_alone_and_threshold(cfg):
    assert "Gym & Fitness" in cats(cfg, rec(), clip={"Gym & Fitness": 0.7}).categories
    assert cats(cfg, rec(), clip={"Gym & Fitness": 0.3}).unsorted


def test_keywords_in_caption(cfg):
    assert "Receipts & Documents" in cats(cfg, rec(caption="Warranty receipt for the drill")).categories


def test_people(cfg):
    assert "Friends & Family" in cats(cfg, rec(persons=["A"], face_count=1)).categories
    assert "Friends & Family" in cats(cfg, rec(face_count=3)).categories
    solo = cats(cfg, rec(is_selfie=True, face_count=1))
    assert solo.categories == ["Selfies"]
    group = cats(cfg, rec(is_selfie=True, face_count=2))
    assert set(group.categories) == {"Selfies", "Friends & Family"}


def test_saved_images(cfg):
    assert "Memes & Saved Images" in cats(cfg, rec(camera_make="")).categories
    assert "Memes & Saved Images" not in cats(cfg, rec(camera_make="Cam")).categories
    assert "Memes & Saved Images" not in cats(cfg, rec(camera_make="", has_exif=False)).categories
    assert "Memes & Saved Images" in cats(cfg, rec(uti="com.compuserve.gif")).categories


def test_travel(cfg):
    far = cats(cfg, rec(latitude=48.0, longitude=2.0), home=HOME)
    assert "Travel" in far.categories and far.km_from_home > 1000
    near = cats(cfg, rec(latitude=10.2, longitude=20.1), home=HOME)
    assert "Travel" not in near.categories and near.km_from_home < 40
    assert "Travel" not in cats(cfg, rec(latitude=48.0, longitude=2.0), home=None).categories
    assert "Travel" not in cats(cfg, rec(), home=HOME).categories


def test_review_to_delete(cfg):
    sharp = Features(1, 1, 90.0, 120.0, 50.0)
    assert "Blurry / Accidental" not in cats(cfg, rec(), sharp).categories
    d = cats(cfg, rec(), Features(1, 1, 3.0, 120.0, 40.0))
    assert d.albums == ["Review to delete"]
    assert "Blurry / Accidental" in cats(cfg, rec(), Features(1, 1, 2.0, 5.0, 2.0)).categories      # blank
    assert "Blurry / Accidental" in cats(cfg, rec(), Features(1, 1, 30.0, 8.0, 9.0)).categories     # dark
    assert "Blurry / Accidental" not in cats(cfg, rec(), Features(1, 1, 11.0, 120.0, 40.0)).categories  # only soft
    assert "Blurry / Accidental" not in cats(cfg, rec(labels=["sunset"]), Features(1, 1, 3.0, 120.0, 40.0)).categories
    assert "Blurry / Accidental" not in cats(cfg, rec(is_screenshot=True), Features(1, 1, 3.0, 120.0, 40.0)).categories
    assert "Blurry / Accidental" not in cats(cfg, rec(), Features(status="nothumb")).categories


def test_duplicates_and_unsorted(cfg):
    d = cats(cfg, rec(), dup_info={"U1": (3, "extra")})
    assert d.categories == ["Duplicates & Similar"] and d.dup_group == 3
    u = cats(cfg, rec())
    assert u.unsorted and u.albums == ["Unsorted"]


def test_per_category_threshold(cfg):
    import copy
    c2 = copy.deepcopy(cfg)
    c2.category("Food & Drinks").threshold = 0.95
    assert "Food & Drinks" not in Classifier(c2).classify(rec(labels=["food"])).categories
    assert "Food & Drinks" in Classifier(c2).classify(rec(labels=["food", "pizza"])).categories
