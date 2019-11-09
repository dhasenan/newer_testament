/**
 * USFM format handling.
 *
 * This is tailored strongly to the stuff I've encountered in the real world, which is dominated by
 * the official World English Bible distribution. It also ignores a lot of data, like introduction
 * parts, cross-references, and footnotes.
 */
module nt.input.usfm;

import nt.books;
import nt.util;

import std.experimental.logger;
import std.string;

Book usfmToBook(string text)
{
    auto book = new Book;
    string remaining = text;

    // First find the name
    remaining = remaining[remaining.indexOf(`\toc2`) + 5 .. $];
    book.name = remaining[0 .. remaining.indexOf("\n")].strip;

    enum chapterMarker = `\c `;
    remaining = remaining[remaining.indexOf(chapterMarker) .. $];
    uint chapterNumber = 1;
    while (remaining.length)
    {
        // Last time, we left on the `\c` for the next chapter's start,
        // so we'll chop it off now.
        remaining = remaining[2 .. $];
        auto end = remaining.index(chapterMarker);
        auto chapText = remaining[0 .. end];
        remaining = remaining[end .. $];
        book.chapters ~= readChapter(chapText, chapterNumber);
        chapterNumber++;
    }

    return book;
}

/// Line-oriented terms where we want to omit the markup and its line
enum skipLines = [
    // Titles and stuff
    "\\ms", "\\ms1", "\\ms2", "\\ms3",
    "\\mt", "\\mt1", "\\mt2", "\\mt3",
    "\\mr", "\\mr1", "\\mr2", "\\mr3",
    "\\s", "\\s1", "\\s2", "\\s3",
    "\\t", "\\t1", "\\t2", "\\t3",
    "\\r", "\\r1", "\\r2", "\\r3",
    // Poetry
    "\\qa", // section name
    "\\qd", // instructions to the music director
    // chapter presentation text
    "\\cl", "\\cp", "\\cd",
    // Used exclusively? in Psalms. Musical direction etc
    "\\d",
    // speaker identification, should use it for quote attribution hints later
    "\\sp",
];

/// Section-oriented terms where we want to omit the markup and its section
enum skipSections = [
    "\\x", // crossref
    "\\f", // footnote
    "\\qs", // Selah!
    "\\va", "\\vp", // verse presentation stuff
];

/// Markup that we want to remove (but preserve its contents)
enum removeMarkup = [
    // Words of Jesus
    "\\wj",
    // Poetry stuff
    "\\qac",
    "\\qm", "\\qm1", "\\qm2", // embedded poetry markers
    "\\qc", // center
    // lists
    "\\li", "\\li1", "\\lim", "\\lim1", "\\lh", "\\lf",
    // continue previous paragraph even if we're in a new chapter
    "\\nb",
    // letter aspects (opening, closing, signature)
    "\\po", "\\cls", "\\sig",
    "\\add", // translator added this for clarity; we'll keep it
    "\\bk", // name of some bible book
];

Chapter readChapter(string text, int chapterNumber)
{
    auto chapter = new Chapter;
    chapter.chapter = chapterNumber;
    enum verseMarker = `\v `;
    auto remaining = text;
    auto s = remaining.indexOf(verseMarker);
    if (s < 0) return null;
    remaining = remaining[s .. $];
    while (remaining.length)
    {
        assert(remaining.startsWith(verseMarker));
        remaining = remaining[3 .. $];
        remaining = remaining[1 + remaining.indexOf(' ') .. $];
        auto end = remaining.index(verseMarker);
        auto current = remaining[0 .. end];
        remaining = remaining[end .. $];

        /* We could simply do a bunch of string.replace here.
           However, footnotes are done a bit differently, so we need something a little fancier. */
        import std.array : Appender;
        Appender!string a;
        a.reserve(current.length);
        while (current.length)
        {
            auto nextCommand = current.index('\\');
            a ~= current[0 .. nextCommand];
            current = current[nextCommand .. $];

            if (current.length == 0) break;

            auto commandDelimiter = current.index(' ');
            auto commandStar = current.index('*');
            auto laterCommand = current[1..$].index('\\');
            if (commandStar < commandDelimiter) commandDelimiter = commandStar + 1;
            if (laterCommand < commandDelimiter) commandDelimiter = laterCommand;

            auto command = current[0 .. commandDelimiter].strip;
            current = current[commandDelimiter .. $];

whichCommand:
            switch (command)
            {
                static foreach (cmd; skipLines)
                {
                case cmd:
                }
                    current = current[current.index('\n') .. $];
                    break;
                static foreach (cmd; skipSections)
                {
                case cmd:
                    current = current[current.index(cmd ~ '*') + 1 + cmd.length .. $];
                    break whichCommand;
                }
                static foreach (cmd; removeMarkup)
                {
                case cmd:
                case cmd ~ "*":
                }
                    break;
                case "\\p":
                case "\\pi":
                case "\\pi1":
                case "\\pm":
                case "\\pmo":
                case "\\pmr":
                case "\\mi":
                case "\\pc":
                case "\\ph":
                case "\\ph1":
                case "\\m":
                    a ~= newParagraphMark;
                    break;
                case "\\b":
                    a ~= newLineMark;
                    break;
                case "\\q":
                case "\\q1":
                    a ~= newLineMark ~ "\t";
                    break;
                case "\\q2":
                    a ~= newLineMark ~ "\t\t";
                    break;
                case "\\q3":
                    a ~= newLineMark ~ "\t\t\t";
                    break;
                default:
                    warningf("skipping unknown command %s", command);
                    break;
            }
        }
        auto verse = new Verse;
        verse.text = a.data.replace(" \n", "").replace("\n", "");
        chapter.verses ~= verse;
    }
    return chapter;
}

ulong index(string s, char c)
{
    auto a = s.indexOf(c);
    if (a < 0) return s.length;
    return cast(ulong)a;
}

ulong index(string s, string c)
{
    auto a = s.indexOf(c);
    if (a < 0) return s.length;
    return cast(ulong)a;
}

bool contains(string haystack, string needle)
{
    return indexOf(haystack, needle) >= 0;
}

unittest
{
    enum text = `\id PS2  
\h Psalm 151 
\toc1 Psalm 151 
\toc2 Psalm 151 
\toc3 Ps151 
\mt1 PSALM 151 
\ip \bk Psalm 151\bk* is recognized as Deuterocanonical Scripture by the Greek Orthodox and Russian Orthodox Churches. 
\c 1  
\cp 151
\d This Psalm is a genuine one of David, though extra,\f + \fr 1:0  \ft or, supernumerary\f* composed when he fought in single combat with Goliath. 
\q1
\v 1 I was small among my brothers, 
\q2 and youngest in my father’s house. 
\q2 I tended my father’s sheep. 
\q1
\v 2 My hands formed a musical instrument, 
\q2 and my fingers tuned a lyre. 
\q1
\v 3 Who shall tell my Lord? 
\q2 The Lord himself, he himself hears. 
\q1
\v 4 He sent forth his angel and took me from my father’s sheep, 
\q2 and he anointed me with his anointing oil. 
\q1
\v 5 My brothers were handsome and tall; 
\q2 but the Lord didn’t take pleasure in them. 
\q1
\v 6 I went out to meet the Philistine, 
\q2 and he cursed me by his idols. 
\q1
\v 7 But I drew his own sword and beheaded him, 
\q2 and removed reproach from the children of Israel.
`;
    auto book = usfmToBook(text);
    assert(book.name == "Psalm 151");
    import std.format : format;
    assert(book.chapters.length == 1, format("expected 1 chapter, got %s", book.chapters.length));
    auto chap = book.chapters[0];
    assert(chap.verses.length == 7);
    assert(chap.verses[0].text.contains("I was small among my brothers,"
                ~ newLineMark ~ "\t\t and youngest in my father’s house."
                ~ newLineMark ~ "\t\t I tended my father’s sheep."));
}
