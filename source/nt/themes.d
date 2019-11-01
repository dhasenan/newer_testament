/** Detect the theme for each verse */
module nt.themes;

import nt.books;

import jsonizer;

import std.algorithm;
import std.array;
import std.container.dlist;
import std.conv;
import std.string;
import std.typecons;
import std.uni;

auto toWords(string s)
{
    return s
        .toLower
        .substitute!(
            ";", "",
            ",", "",
            ".", "",
            "-", "",
            ":", "",
            "'", "",
            "\"", "")
        .to!string
        .splitter(' ');
}

struct ThemeModel
{
    mixin JsonizeMe;
    @jsonize
    {
        ulong minOccurrences = 20, maxOccurrences = 1000;
        ulong[string] wordFrequency;
        string[][string] byTheme;
    }

    // LRU cache for verses used
    DList!string byTime;
    ulong[string] byVerse;
    ulong count = 0;
    ulong historyLength = 500;

    void build(Bible bible)
    {
        foreach (book; bible.books)
        foreach (chapter; book.chapters)
        foreach (verse; chapter.verses)
        foreach (word; verse.text.toWords)
        {
            if (auto p = word in wordFrequency)
            {
                (*p)++;
            }
            else
            {
                wordFrequency[word.idup] = 1;
            }
        }
        foreach (book; bible.books)
        foreach (chapter; book.chapters)
        foreach (verse; chapter.verses)
        {
            // TODO track number of distinct books this thing appears in
            auto t = theme(verse.text);
            if (t.length == 0) continue;
            if (auto v = t in byTheme)
            {
                (*v) ~= verse.text;
            }
            else
            {
                byTheme[t] = [verse.text];
            }
        }
    }

    void shuffle(uint seed)
    {
        import std.random;
        Random r;
        r.seed(seed);
        foreach (k, ref v; byTheme)
        {
            v = randomShuffle(v).array;
        }
    }

    string theme(string verse)
    {
        auto candidates = verse
            .toWords
            .map!(x => tuple(x.idup, wordFrequency[x]))
            .filter!(t => t[1] < maxOccurrences)
            .filter!(t => t[1] > minOccurrences);
        if (candidates.empty) return "";
        return candidates.minElement!(x => x[1])[0];
    }

    string toVerse(string theme)
    {
        auto p = theme in byTheme;
        if (p is null) return "";
        auto verses = *p;
        foreach (v; verses)
        {
            if (v in byVerse) continue;
            byVerse[v] = count;
            byTime.insertBack(v);
            count++;
            while (byVerse.length > historyLength)
            {
                auto rem = byTime.front;
                byTime.removeFront;
                byVerse.remove(rem);
            }
            return v;
        }
        // We didn't find anything for this theme that hasn't been used recently.
        // Let's just call it a day.
        return "";
    }
}
