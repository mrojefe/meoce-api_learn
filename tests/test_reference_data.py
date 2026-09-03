"""Guards the hardcoded reference enums against the database.

`AllowedType` and `AllowedSector` are written by hand in app/core/reference.py.
That is deliberate — see their docstrings — but a handwritten copy of someone
else's data goes stale silently. These tests are what make it fail loudly
instead: add a sector in SQL without adding it here, and CI turns red with the
exact missing value.

They need a reachable database, so they are integration tests, not unit tests.
"""

import pytest

from app.core.reference import AllowedSector, AllowedType, Feature, FlagColor, PlanCode, get_enum


@pytest.fixture(scope="module")
def reference():
    """Reads the reference tables once for the whole module.

    Returns:
        dict[str, list[str]]: The "types" and "sectors" lists, as stored.
    """
    return get_enum(sectors=True, type_=True, flag_colors=True)


def test_types_match_the_database(reference):
    """Every instrument type in the database exists in AllowedType, and vice versa."""
    assert set(AllowedType) == {AllowedType(v) for v in reference["types"]}, (
        "instrument_types and AllowedType disagree — update app/core/reference.py"
    )


def test_sectors_match_the_database(reference):
    """Every sector in the database exists in AllowedSector, and vice versa."""
    in_db = set(reference["sectors"])
    in_code = {member.value for member in AllowedSector}
    assert in_code == in_db, (
        f"only in the database: {sorted(in_db - in_code)} | "
        f"only in the code: {sorted(in_code - in_db)}"
    )


@pytest.mark.parametrize("given", ["bond", "BOND", " Bond "])
def test_type_accepts_any_case(given):
    """The _missing_ hook resolves case and spacing to one member."""
    assert AllowedType(given) is AllowedType.BOND


def test_unknown_value_is_still_rejected():
    """Tolerating case must not mean tolerating anything."""
    with pytest.raises(ValueError):
        AllowedType("banana")


def test_value_is_exactly_what_the_database_holds():
    """The member name may differ from the value; the value may not drift."""
    assert AllowedSector.SERVICES_FINANCIERS.value == "SERVICES FINANCIERS"
    assert AllowedType.BOND.value == "bond"


@pytest.fixture(scope="module")
def plans():
    """Reads the subscription plans once for the whole module.

    Returns:
        list[dict]: Every row of `subscription_plans`, active or not.
    """
    from app.core.db.database import direct_query

    return direct_query("SELECT code, features, is_active FROM subscription_plans")


def test_plan_codes_match_the_database(plans):
    """Every plan in the database is named in PlanCode, and vice versa."""
    in_db = {p["code"] for p in plans}
    in_code = {member.value for member in PlanCode}
    assert in_code == in_db, (
        f"only in the database: {sorted(in_db - in_code)} | "
        f"only in the code: {sorted(in_code - in_db)}"
    )


def test_no_unknown_feature_keys(plans):
    """No plan carries a key that Feature does not name.

    This is the test that catches the typo. A key spelled `max_watchlist`
    instead of `max_watchlists` reads back as None, which the code treats as
    *unlimited* — so without this test a single missing letter silently removes
    a limit, with no error anywhere.
    """
    known = {member.value for member in Feature}
    unknown = {k for p in plans for k in p["features"]} - known
    assert not unknown, (
        f"unknown keys in subscription_plans.features: {sorted(unknown)} — "
        "a typo, or a new feature that must be added to Feature"
    )


def test_every_active_plan_defines_every_feature(plans):
    """Each active plan should name every feature explicitly.

    A missing key is indistinguishable from `null`, and `null` means unlimited
    for a limit and false for a switch. Silence therefore *decides* something,
    and it decides differently depending on the key — which is exactly how
    `multi_layout` ended up denied on the paid plans while the free plan names
    it.

    Currently failing on purpose: it documents a real gap in the data.
    """
    known = {member.value for member in Feature}
    missing = {
        p["code"]: sorted(known - set(p["features"]))
        for p in plans
        if p["is_active"] and known - set(p["features"])
    }
    assert not missing, f"plans with undefined features: {missing}"


def test_flag_colors_match_the_database(reference):
    """Every id in flag_colors is named in FlagColor, and vice versa.

    This is the test that would have caught the mistake made writing
    `FlagColor` the first time: it was built off an old migration's CHECK
    constraint, never checked against the running database, and missed two
    real rows (purple, pink) that a later migration had already added.
    """
    in_db = set(reference["flag_colors"])
    in_code = {member.value for member in FlagColor}
    assert in_code == in_db, (
        f"only in the database: {sorted(in_db - in_code)} | "
        f"only in the code: {sorted(in_code - in_db)}"
    )
