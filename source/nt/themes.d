/** Detect the theme for each verse */
module nt.themes;

import nt.books;
import nt.db;
import nt.util;

import jsonizer;

import std.algorithm;
import std.array;
import std.container.dlist;
import std.conv;
import std.experimental.logger;
import std.json;
import std.random;
import std.stdio;
import std.string;
import std.typecons;
import std.uni;


void findThemesMain(string[] args)
{
    import std.getopt;

    ulong id;
    string database;
    auto theme = new ThemeModel;
    string occurrences = "10-1000";

    auto opts = getopt(args,
            config.required,
            "d|db", "database", &database,
            config.required,
            "id", "id of an existing bible", &theme.bibleId,
            "n|name", "name of the theme", &theme.name,
            "l|history-length", "how many verses of history to keep (for variety)",
            &theme.historyLength,
            "o|occurrences",
            "range of how many sentences can have a word for it to be considered a theme word",
            &occurrences);

    auto db = new DB(database);
    scope (exit) db.cleanup;
    db.beginTransaction;
    db.save(theme);
    tracef("saved theme %s; building model", theme.id);
    findThemes(db, theme);
    tracef("model %s built", theme.id);
    db.commit;
    writefln("Theme model %s saved", theme.id);
}

void findThemes(DB db, ThemeModel theme)
{
    // First we need to build a word histogram.
    // We're going to do this in memory for simplicity.
    ulong[string] histogram;
    foreach (verse; db.allVerses(theme.bibleId))
    {
        foreach (lex; verse.analyzed)
        {
            if (auto p = lex.word in histogram)
            {
                (*p)++;
            }
            else
            {
                histogram[lex.word] = 1;
            }
        }
    }

    // Now we can build our data
    foreach (sentence; db.allSentences(theme.bibleId))
    {
        string rarest = "";
        ulong commonness = ulong.max;
        foreach (lex; sentence.analyzed)
        {
            auto r = histogram[lex.word];
            if (r < commonness && r >= theme.minOccurrences && r <= theme.maxOccurrences)
            {
                rarest = lex.word;
                commonness = r;
            }
        }
        auto ts = new ThemedSentence;
        ts.sentenceId = sentence.id;
        ts.themeModelId = theme.id;
        ts.theme = rarest;
        db.save(ts);
    }
}

Sentence findFreeSentence(ThemeModel model, DB db, string theme)
{
    auto matches = db.sentencesByTheme(model.id, theme);
    foreach (attempt; 1 .. 20)
    {
        auto m = choice(matches, model.rng);
        if (model.tryTake(m.id))
        {
            return m;
        }
    }
    foreach (m; matches)
    {
        if (model.tryTake(m.id))
        {
            return m;
        }
    }
    return null;
}
