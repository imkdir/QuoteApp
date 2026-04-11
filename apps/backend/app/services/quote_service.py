"""In-memory quote provider for the QuoteApp backend."""

from app.models.quote import Quote

_QUOTES: list[Quote] = [
    Quote(
        id="meditations-01",
        text="A candour affected is a dagger concealed. The feigned friendship of the wolf is the most contemptible of all, and to be shunned beyond everything. A man who is truly good and sincere and well-meaning will show it by his looks, and no one can fail to see it.",
    ),
    Quote(
        id="infinite-jest-03",
        text="Sometimes it’s hard to believe the sun’s the same sun over all different parts of the planet.",
    ),
    Quote(
        id="infinite-jest-02",
        text="It’s not necessarily pejorative to compare a cornered bureaucrat to a cornered rat.",
    ),
    Quote(
        id="infinite-jest-01",
        text="They were the age staring down the barrel not of Is anything true but of Am I true, of What am I, of What is this thing, and it made them strange.",
    ),
    Quote(
        id="emily-dickenson-01",
        text="This is my letter to the world,\nThat never wrote to me,— \nThe simple news that Nature told,\nWith tender majesty.\n\nHer message is committed \nTo hands I cannot see; \nFor love of her, sweet countrymen, \nJudge tenderly of me!",
    ),
]


def list_quotes() -> list[Quote]:
    """Returns all available quotes for the current build."""

    return _QUOTES
