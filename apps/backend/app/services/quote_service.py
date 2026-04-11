"""In-memory quote provider for the QuoteApp backend."""

from app.models.quote import Quote

_QUOTES: list[Quote] = [
    Quote(
        id="meditations-01",
        preview="A candour affected is a dagger concealed...",
        text="A candour affected is a dagger concealed. The feigned friendship of the wolf is the most comtemptible of all, and to be shunned beyond everything. A man who is truly good and sincere and well-meaning wil show it by his looks, and no one can fail to see it.",
    ),
    Quote(
        id="infinite-jest-03",
        preview="Sometimes it’s hard to believe the...",
        text="Sometimes it’s hard to believe the sun’s the same sun over all different parts of the planet.",
    ),
    Quote(
        id="infinite-jest-02",
        preview="It’s not necessarily pejorative to...",
        text="It’s not necessarily pejorative to compare a cornered bureaucrat to a cornered rat.",
    ),
    Quote(
        id="infinite-jest-01",
        preview="They were the age staring down the...",
        text="They were the age staring down the barrel not of Is anything true but of Am I true, of What am I, of What is this thing, and it made them strange.",
    ),
]


def list_quotes() -> list[Quote]:
    """Returns all available quotes for the current build."""

    return _QUOTES
