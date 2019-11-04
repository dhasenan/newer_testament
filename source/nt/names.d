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
void findNames(Bible bible, ref ulong[string] names)
{
    ulong[string] allWords;
    Set!string lower;

    foreach (book; bible.books)
    foreach (chapter; book.chapters)
    foreach (verse; chapter.verses)
    foreach (word; toWords(verse.text))
    {
        if (word.length < 3) continue;
        if (word[0] >= 'a' && word[0] <= 'z')
        {
            lower[word] = true;
        }
        else
        {
            increment(allWords, word.toLower);
        }
    }

    foreach (k, v; lower)
    {
        allWords.remove(k);
    }

    foreach (k, v; allWords)
    {
        if (k in lower)
            continue;
        else
            names[k.titleCase] = v;
    }
}

void convertNames(Bible bible, Set!string names)
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
                foreach (word; verse.text.toWords)
                {
                    if (word in names)
                    {
                        bookNames.increment(word);
                        chapterNames.increment(word);
                    }
                }
            }
            chapter.dramatisPersonae = chapterNames.keys.array;
        }
        book.dramatisPersonae = bookNames.keys.array;
    }

    // Now alter the verses
    foreach (book; bible.books)
    foreach (chapter; book.chapters)
    foreach (verse; chapter.verses)
    foreach (i, name; chapter.dramatisPersonae)
    {
        // This suffers from the Scunthorpe problem, unfortunately.
        import std.format : format;
        auto rep = "[[%s]]".format(i);
        verse.text = verse.text.replace(name, rep);
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
            string[ulong] peeps;
            foreach (verse; chapter.verses)
            {
                foreach (m; verse.text.matchAll(index))
                {
                    auto id = m[1].to!ulong;
                    if (!(id in peeps))
                    {
                        peeps[id] = chapter.dramatisPersonae[peeps.length % $];
                    }
                }
            }
            foreach (verse; chapter.verses)
            {
                Appender!string munged;
                munged.reserve(verse.text.length);
                ulong start = 0;
                foreach (m; verse.text.matchAll(index))
                {
                    munged.put(m.pre[start .. $]);
                    start = verse.text.length - m.post.length;
                    munged.put(peeps[m[1].to!ulong]);
                }
                munged.put(verse.text[start .. $]);
                verse.text = munged.data;
            }
        }
    }
}

