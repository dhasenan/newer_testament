/** Handler for the overall classure of the testament and its books. */
module nt.books;
import jsonizer;
import std.uuid;

immutable UUID uuidZero = UUID([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);

struct dbignore {}

abstract class DBObject
{
    UUID id = uuidZero;
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
    UUID bibleId;
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
    UUID bookId;
    Sentence[] sentences;

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
    UUID chapterId;

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


class Sentence
{
    /// the unique ID of this sentence
    UUID id;
    /// the ID of the sentence this came from; if this is original, it points to itself
    UUID sourceId;
    /// the id of the chapter it's from
    UUID chapterId;
    /// the verse in which this sentence starts
    ulong verse;
    /// the raw text of the sentence
    string raw;
    /// the analyzed text of the sentence
    Lex[] analyzed;
    /// the theme of the sentence, what it's about
    string theme;
    /// whether this sentence is part of or contains a quote
    Quote quote;
    /// the main tense of this sentence (tense of its primary verb)
    Tense tense;

    this()
    {
        id = randomUUID;
        sourceId = id;
    }
}

