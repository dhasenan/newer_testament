/** Handler for the overall classure of the testament and its books. */
module nt.books;
import jsonizer;

struct dbignore {}

abstract class DBObject
{
    ulong id;
}

class Bible : DBObject
{
    @dbignore { mixin JsonizeMe; }
    @jsonize
    {
        string name;
        @dbignore Book[] books;
        @dbignore ulong[string] nameHistogram;
    }

    this() {}
    this(string name) { this.name = name; }

    auto allVerses()
    {
        import std.algorithm, std.range;
        return books
            .map!(x => x.chapters)
            .joiner()
            .map!(x => x.verses)
            .joiner();
    }
}

class Book : DBObject
{
    ulong bibleId;
    @dbignore { mixin JsonizeMe; }
    @jsonize
    {
        @dbignore string[] dramatisPersonae;
        string name;
        @dbignore Chapter[] chapters;
        ulong bookNumber;
    }

    this() {}
    this(string name) { this.name = name; }
}

class Chapter : DBObject
{
    @dbignore { mixin JsonizeMe; }
    @jsonize
    {
        @dbignore string[] dramatisPersonae;
        uint chapter;
        @dbignore Verse[] verses;
    }
    ulong bookId;
    @dbignore Sentence[] sentences;

    this() {}
    this(uint chapter)
    {
        this.chapter = chapter;
    }
}

class Verse : DBObject
{
    @dbignore { mixin JsonizeMe; }
    @jsonize
    {
        uint verse;
        string text;
        Lex[] analyzed;
        string theme;
    }
    // do away with chapters as a separate entity, we don't need them
    ulong chapterNum;
    ulong bookId;

    this() {}
    this(uint verse, string text)
    {
        this.verse = verse;
        this.text = text;
    }
}

class Lex
{
    mixin JsonizeMe;
    @jsonize
    {
        /// The base word, or punctuation if it's not a word
        string word;
        /// The inflection category, eg NN for a singular noun
        string inflect;
        /// The index of the variant of the inflection used
        ubyte variant;
        /// Whitespace following this word
        string whitespace;
        /// The ID of the person this refers to, if it's a proper noun
        long person = -1;
        /// The case indicator for this word: 0 -> lower, 1 -> title, 2 -> upper
        ubyte upper;
    }
}

/**
 * Flags enum for quote status of a sentence.
 */
enum Quote
{
    /// this is pure narration
    none = 0,
    /// this is the start of a quote
    start = 1,
    /// this is the end of a quote
    end = 2,
    /// this is both the start and end of a quote
    whole = 3,
    /// this is a sentence wholly contained within a quote
    middle = 4,
    /// this is a sentence containing a quote
    contains = 8,
}

enum Tense
{
    present = 1,
    past = 2,
    future = 4,
    progressive = 8,
    perfect = 16
}


class Sentence : DBObject
{
    /// the book in which this thing occurs
    ulong bookId;
    /// the chapter and verse where this sentence starts
    ulong chapterNum, verse;
    /// the raw text of the sentence
    string raw;
    /// the analyzed text of the sentence
    Lex[] analyzed;
    /// whether this sentence is part of or contains a quote
    Quote quote;
    /// the main tense of this sentence (tense of its primary verb)
    Tense tense;
    /// the 0-based index of this sentence
    ulong offset;
}

class ThemeModel : DBObject
{
    ulong bibleId;
    string name;
    ulong historyLength;
    ulong minOccurrences;
    ulong maxOccurrences;
    ubyte[] verseChain, bookChain, characterChain;

    import std.container.dlist;
    import std.random;

    bool tryTake(ulong sentence)
    {
        if (auto p = sentence in _lastSeen)
        {
            if (_count - *p < historyLength)
            {
                return false;
            }
        }
        _order.insertBack(sentence);
        _lastSeen[sentence] = _count;
        _count++;
        while (_lastSeen.length > historyLength && !_order.empty)
        {
            _lastSeen.remove(_order.front);
            _order.removeFront;
        }
        if (_order.empty) _lastSeen = null;
        return true;
    }

    void clearHistory()
    {
        _count = 0;
        _lastSeen = null;
        _order = typeof(_order).init;
    }

    @dbignore Random rng;
    private @dbignore
    {
        // how many things we've generated, a sort of clock
        ulong _count;
        // verse id -> _count time we last saw it
        ulong[ulong] _lastSeen;
        // queue of last times we've seen a thing
        DList!ulong _order;
    }
}

class ThemedSentence : DBObject
{
    ulong sentenceId;
    ulong themeModelId;
    string theme;
    /// the book in which this thing occurs
    ulong bookId;
    /// the chapter and verse where this sentence starts
    ulong chapterNum, verse;
    /// whether this sentence is part of or contains a quote
    Quote quote;
    /// the main tense of this sentence (tense of its primary verb)
    Tense tense;
    /// the 0-based index of this sentence
    ulong offset;

    string token()
    {
        import std.format;
        return format("%s-%s-%s", theme, quote, tense);
    }
}
