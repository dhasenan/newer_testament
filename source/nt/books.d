/** Handler for the overall classure of the testament and its books. */
module nt.books;
import jsonizer;

class Bible
{
    mixin JsonizeMe;
    @jsonize
    {
        string name;
        Book[] books;
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

class Book
{
    mixin JsonizeMe;
    @jsonize
    {
        string[] dramatisPersonae;
        string name;
        Chapter[] chapters;
    }

    this() {}
    this(string name) { this.name = name; }
}

class Chapter
{
    mixin JsonizeMe;
    @jsonize
    {
        string[] dramatisPersonae;
        uint chapter;
        Verse[] verses;
    }

    this() {}
    this(uint chapter) { this.chapter = chapter; }
}

class Verse
{
    mixin JsonizeMe;
    @jsonize
    {
        uint verse;
        string text;
        Lex[] analyzed;
        string theme;
    }

    this() {}
    this(uint verse, string text)
    {
        this.verse = verse;
        this.text = text;
    }
}

struct Lex
{
    mixin JsonizeMe;
    @jsonize
    {
        /// The base word, or punctuation if it's not a word
        string word;
        /// The inflection category, eg NN for a singular noun
        string inflect;
        /// Whitespace following this word
        string whitespace;
        /// The ID of the person this refers to, if it's a proper noun
        ulong person;
    }
}
