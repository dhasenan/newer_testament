/** Fixup to handle names. */
module nt.names;

import nt.books;
import nt.util : toWords, titleCase;

import std.uni;
import std.array;
import std.algorithm;
import std.conv;
import std.random;
import std.regex;

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
void findNames(Bible bible)
{
    ulong[string] names;
    foreach (book; bible.books)
    {
        ulong[string] bookPeople;
        foreach (chapter; book.chapters)
        {
            ulong[string] chapterPeople;
            foreach (verse; chapter.verses)
            {
                foreach (lex; verse.analyzed)
                {
                    if (lex.inflect == "NNP")
                    {
                        increment(names, lex.word);
                        increment(bookPeople, lex.word);
                        increment(chapterPeople, lex.word);
                    }
                }
            }
            chapter.dramatisPersonae = chapterPeople.keys;
        }
        book.dramatisPersonae = bookPeople.keys;
    }
    bible.nameHistogram = names;
}

void convertNames(Bible bible)
{
    // Figure out what names we have in each book and chapter
    foreach (book; bible.books)
    {
        ulong[string] bookNames;
        foreach (chapter; book.chapters)
        {
            ulong[string] chapterNames;
            foreach (verse; chapter.verses)
            {
                foreach (lex; verse.analyzed)
                {
                    if (lex.word in bible.nameHistogram)
                    {
                        bookNames.increment(lex.word);
                        chapterNames.increment(lex.word);
                    }
                }
            }
            chapter.dramatisPersonae = chapterNames.keys.array.sort.array;
        }
        book.dramatisPersonae = bookNames.keys.array.sort.array;
    }

    // Now alter the verses
    foreach (book; bible.books)
    foreach (chapter; book.chapters)
    foreach (verse; chapter.verses)
    foreach (i, name; chapter.dramatisPersonae)
    {
        foreach (ref Lex lex; verse.analyzed)
        {
            if (lex.inflect == "NNP" && lex.word == name)
            {
                lex.person = i;
            }
        }
    }
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
                foreach (m; verse.text.matchAll(index))
                {
                    peeps[m[1].to!ulong] = true;
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
            ulong[ulong] peepIds;
            foreach (verse; chapter.verses)
            {
                foreach (ref lex; verse.analyzed)
                {
                    if (lex.inflect != "NNP") continue;
                    auto id = lex.person;
                    if (!(id in peepIds))
                    {
                        peepIds[id] = peepIds.length % chapter.dramatisPersonae.length;
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
    string output, histogramFile;
    auto opts = getopt(args,
            config.required,
            "i|input", "input bible", &input,
            config.required,
            "o|output", "output directory", &output,
            "n|names", "name histogram output", &histogramFile);
    if (opts.helpWanted)
    {
        defaultGetoptPrinter("find names in the Bible", opts.options);
        return;
    }

    auto bible = readJSON!Bible(input);
    findNames(bible);
    convertNames(bible);
    writeJSON(output, bible);
}
