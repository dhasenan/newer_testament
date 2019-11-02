/** Detect the theme for each verse */
module nt.themes;

import nt.books;

import jsonizer;

import std.json;
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
        // The goal is to disallow punctuation specifically, but this also catches, well,
        // everything that we don't specifically want to keep.
        .filter!((dchar x) => isAlpha(x) || x == ' ' || x == '\u2029')
        .to!string
        .splitter(' ');
}

struct ThemeModel
{
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
        // TODO figure out which words only appear in title case and omit them
        foreach (book; bible.books)
        foreach (chapter; book.chapters)
        foreach (verse; chapter.verses)
        foreach (word; verse.text.toLower.toWords)
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
        // Should we try harder to get a theme?
        auto candidates = verse
            .toLower
            .toWords
            .filter!(x => x in wordFrequency)
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

    mixin JsonizeMe;

    /*
    JSONValue toJSON()
    {
        JSONValue v;
        v["minOccurrences"] = minOccurrences;
        v["maxOccurrences"] = maxOccurrences;
        JSONValue frequency;
        foreach (k, v; wordFrequency)
        {
            frequency[k] = v;
        }
        v["wordFrequency"] = frequency;
        JSONValue themes;
        foreach (k, v; byTheme)
        {
            themes[k] = v.map!(x => JSONValue(x)).array;
        }

        v["byTheme"] = themes;
        return v;
    }

    static ThemeModel loadJSON(string path)
    {
        import std.file : readText;
        auto o = path.readText.parseJSON;
        ThemeModel m;
        m.minOccurrences = o["minOccurrences"].uinteger;
        m.maxOccurrences = o["maxOccurrences"].uinteger;
        foreach (k, v; o["wordFrequency"].object)
        {
            m.wordFrequency[k] = v.uinteger;
        }
        foreach (k, v; o["byTheme"].object)
        {
            m.byTheme[k] = v.array.map!(x => x.str).array;
        }
        return m;
    }
    */
}
