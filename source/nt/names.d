/** Fixup to handle names. */
module nt.names;

import nt.books;
import nt.util : toWords, titleCase;
import nt.db;
import nt.dictionary;

import std.uni;
import std.array;
import std.algorithm;
import std.conv;
import std.random;
import std.regex;
import std.experimental.logger;

alias Set(T) = ulong[T];

void increment(T)(ref ulong[T] s, T key)
{
    if (auto p = key in s)
    {
        (*p)++;
    }
    else
    {
        s[key] = 1;
    }
}

/** Get a histogram of names and name-like things. */
void findNames(Bible bible, string[] knownNonNames, DB dictionary)
{
    // All names in lowercase variant
    ulong[string] nonNames;
    ulong[string] maybeNames;
    ulong found = 0;

    foreach (n; knownNonNames) nonNames[n] = 1;

    // Identify names, adding to dramatis personae sections as we go
    foreach (book; bible.books)
    {
        foreach (chapter; book.chapters)
        {
            foreach (verse; chapter.verses)
            {
                foreach (ref lex; verse.analyzed)
                {
                    if (lex.inflect != "NNP" && lex.inflect != "NNPS")
                    {
                        lex.person = -1;
                        continue;
                    }
                    auto basicNoun = lex.inflect == "NNP" ? "NN" : "NNS";
                    auto key = lex.word.toLower;
                    if (key in nonNames)
                    {
                        lex.inflect = basicNoun;
                        continue;
                    }
                    if (dictionary.getWord(key) is null)
                    {
                        nonNames[key] = 1;
                        lex.inflect = basicNoun;
                        continue;
                    }
                    increment(bible.nameHistogram, key);
                    // This is O(n²), which isn't awesome, but we're only going to deal with a
                    // couple thousand entries in the absolute worst case.
                    lex.person = cast(long)chapter.dramatisPersonae.countUntil(key);
                    if (lex.person < 0)
                    {
                        lex.person = cast(long)chapter.dramatisPersonae.length;
                        chapter.dramatisPersonae ~= key;
                        if (!book.dramatisPersonae.canFind(key))
                        {
                            book.dramatisPersonae ~= key;
                        }
                    }
                    if (chapter.dramatisPersonae[lex.person] != key)
                    {
                        errorf("name mismatch: expected %s but got %s", key,
                                chapter.dramatisPersonae[lex.person]);
                    }
                }
            }
        }
        tracef("book %s has %s people mentioned", book.name, book.dramatisPersonae.length);
    }
    tracef("finished with %s names", bible.nameHistogram.length);
}

/**
Args:
    chapterFactor: the ratio of people involved in each verse, compared to the chapter
        (lower means more consistent set of people described)
    bookFactor: the ratio of people involved in each chapter, compared to the book
        (lower means more consistent set of people described)
  */
void swapNames(Bible bible, string[] names, double chapterFactor, double bookFactor)
{
    ulong[Chapter] requiredPeepsCount;
    auto index = regex(`\[\[(\d+)\]\]`);
    foreach (book; bible.books)
    {
        ulong minRequiredPeeps = 0;
        foreach (chapter; book.chapters)
        {
            ulong chapterRequiredPeeps;
            foreach (verse; chapter.verses)
            {
                // Figure out how many people we need in this verse.
                Set!ulong peeps;
                foreach (lex; verse.analyzed)
                {
                    if (lex.person >= 0)
                    {
                        increment(peeps, lex.person);
                    }
                }
                if (chapterRequiredPeeps < peeps.length)
                    chapterRequiredPeeps = peeps.length;
            }
            requiredPeepsCount[chapter] = chapterRequiredPeeps;
            if (minRequiredPeeps < chapterRequiredPeeps)
                minRequiredPeeps = chapterRequiredPeeps;
        }
        // We definitely can't make the book work with fewer people than that.
        // We might be able to use more, though.
        // For instance, we might not reference more than about five people per verse,
        // but it would be a little weird to have a book about only five people.
        // How many do we add?
        minRequiredPeeps = cast(ulong)(chapterFactor * bookFactor * minRequiredPeeps + 0.99);
        if (minRequiredPeeps < 1 || minRequiredPeeps > names.length) minRequiredPeeps = 50;

        book.dramatisPersonae = randomSample(names, minRequiredPeeps).array;

        foreach (chapter; book.chapters)
        {
            // Ideally we'd use a non-uniform distribution here.
            // We'd have groups of main characters, recurring characters, and one-off characters.
            // Stuff for later.
            auto count = cast(ulong)(requiredPeepsCount[chapter] * chapterFactor);
            if (count < 4) count = 4;
            chapter.dramatisPersonae = randomSample(book.dramatisPersonae, count).array;
            long[long] peepIds;
            foreach (verse; chapter.verses)
            {
                foreach (ref lex; verse.analyzed)
                {
                    if (lex.person < 0) continue;
                    auto id = lex.person;
                    if (!(id in peepIds))
                    {
                        peepIds[id] = cast(long)(peepIds.length % chapter.dramatisPersonae.length);
                        tracef("mapped person %s to %s", id, peepIds[id]);
                    }
                    lex.person = peepIds[id];
                    lex.word = chapter.dramatisPersonae[lex.person];
                }
            }
        }
    }
}

void findNamesMain(string[] args)
{
    import std.getopt;
    import std.stdio;
    import jsonizer;

    string input;
    string output;
    string dictionaryFile;
    string stopwordFile;
    auto opts = getopt(args,
            config.required,
            "i|input", "input bible", &input,
            config.required,
            "o|output", "output directory", &output,
            config.required,
            "d|dictionary", "path to dictionary database", &dictionaryFile,
            "s|stopwords", "path to stopwords (known non-names) file", &stopwordFile);
    if (opts.helpWanted)
    {
        defaultGetoptPrinter("find names in the Bible", opts.options);
        return;
    }

    string[] knownNonNames;
    if (stopwordFile)
    {
        foreach (line; File(stopwordFile).byLineCopy)
        {
            import std.string : strip;
            auto s = line.strip;
            if (s.length && !s.startsWith("#"))
            {
                knownNonNames ~= s;
            }
        }
    }
    auto bible = readJSON!Bible(input);
    auto db = new DB(dictionaryFile);
    scope (exit) db.cleanup;
    findNames(bible, knownNonNames, db);
    writeJSON(output, bible);
}
