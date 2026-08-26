"""Guards the hardcoded reference enums against the database.

`AllowedType` and `AllowedSector` are written by hand in app/core/enums.py.
That is deliberate — see their docstrings — but a handwritten copy of someone
else's data goes stale silently. These tests are what make it fail loudly
instead: add a sector in SQL without adding it here, and CI turns red with the
exact missing value.

They need a reachable database, so they are integration tests, not unit tests.
"""

import pytest

from app.core.database import get_enum
from app.core.enums import AllowedSector, AllowedType


@pytest.fixture(scope="module")
def reference():
    """Reads the reference tables once for the whole module.

    Returns:
        dict[str, list[str]]: The "types" and "sectors" lists, as stored.
    """
    return get_enum(sectors=True, type_=True)


def test_types_match_the_database(reference):
    """Every instrument type in the database exists in AllowedType, and vice versa."""
    assert set(AllowedType) == {AllowedType(v) for v in reference["types"]}, (
        "instrument_types and AllowedType disagree — update app/core/enums.py"
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
