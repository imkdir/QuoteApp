"""In-memory quote provider for the QuoteApp backend."""

from app.models.quote import Quote


_QUOTES: list[Quote] = [
    Quote(
        id="gatsby-01",
        preview="So we beat on, boats against the current...",
        text="So we beat on, boats against the current, borne back ceaselessly into the past.",
    ),
    Quote(
        id="jane-eyre-01",
        preview="I am no bird; and no net ensnares me...",
        text="I am no bird; and no net ensnares me: I am a free human being with an independent will.",
    ),
    Quote(
        id="hamlet-01",
        preview="There is nothing either good or bad, but thinking makes it so.",
        text="There is nothing either good or bad, but thinking makes it so.",
    ),
    Quote(
        id="pride-01",
        preview="I could easily forgive his pride, if he had not mortified mine.",
        text="I could easily forgive his pride, if he had not mortified mine.",
    ),
]


def list_quotes() -> list[Quote]:
    """Returns all available quotes for the current build."""

    return _QUOTES
